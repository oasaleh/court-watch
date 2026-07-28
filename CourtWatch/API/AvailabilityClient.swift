//
//  AvailabilityClient.swift
//  CourtWatch
//
//  Fetches a day's court availability.
//
//  Two things here are load-bearing and easy to get subtly wrong:
//
//    * Success is read from the response envelope, never from the HTTP status.
//      The API answers 200 for every outcome, including "Invalid CSRF token",
//      so a status check would classify failures as successes.
//    * The retry is exactly one re-handshake and one replay, counted with a
//      local. The site sits behind an F5 ASM WAF; a client that retries in a
//      loop earns a block on the user's address, and a recursive
//      implementation is how the terminal guard gets lost in a later edit.
//

import Foundation

nonisolated struct AvailabilityClient: Sendable {

    static let endpoint = URL(
        string: "https://anc.apm.activecommunities.com/wcscparksandrec"
            + "/rest/reservation/quickreservation/availability?locale=en-US")!

    /// Tennis. Other facility groups are out of scope for this app.
    static let tennisFacilityGroupID = 20

    private let session: CourtSession

    init(session: CourtSession) {
        self.session = session
    }

    /// A server-side time window. Phase 4 drives this from the start-time
    /// filter; here it is a parameter that gets sent.
    nonisolated struct SlotWindow: Sendable, Equatable {
        let start: SlotTime
        let end: SlotTime

        init(start: SlotTime, end: SlotTime) {
            self.start = start
            self.end = end
        }
    }

    nonisolated struct AvailabilityRequestBody: Encodable, Sendable {
        let facilityGroupID: Int
        let customerID: Int
        let companyID: Int
        let reserveDate: String
        let startTime: String?
        let endTime: String?
        let resident: Bool
        let reload: Bool
        let changeTimeRange: Bool

        enum CodingKeys: String, CodingKey {
            case facilityGroupID = "facility_group_id"
            case customerID = "customer_id"
            case companyID = "company_id"
            case reserveDate = "reserve_date"
            case startTime = "start_time"
            case endTime = "end_time"
            case resident
            case reload
            case changeTimeRange = "change_time_range"
        }

        /// `start_time` and `end_time` are encoded explicitly as null when
        /// absent rather than omitted.
        ///
        /// The measured working payload includes both keys with null values.
        /// Swift's default would drop them for a nil optional, and an endpoint
        /// this undocumented is not worth discovering the difference on.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(facilityGroupID, forKey: .facilityGroupID)
            try container.encode(customerID, forKey: .customerID)
            try container.encode(companyID, forKey: .companyID)
            try container.encode(reserveDate, forKey: .reserveDate)

            if let startTime {
                try container.encode(startTime, forKey: .startTime)
            } else {
                try container.encodeNil(forKey: .startTime)
            }

            if let endTime {
                try container.encode(endTime, forKey: .endTime)
            } else {
                try container.encodeNil(forKey: .endTime)
            }

            try container.encode(resident, forKey: .resident)
            try container.encode(reload, forKey: .reload)
            try container.encode(changeTimeRange, forKey: .changeTimeRange)
        }
    }

    /// Whether a body even claims to be JSON, judged by its first meaningful
    /// byte and nothing else.
    ///
    /// Deliberately this boring. It needs to be right in the common case — an
    /// HTML block page, a login interstitial, an empty body — not clever, and
    /// anything that inspected further would be guessing about a system that
    /// belongs to someone else. A body that starts with `{` or `[` and then
    /// fails to parse is a schema change; anything else was never the API.
    static func looksLikeJSON(_ data: Data) -> Bool {
        for byte in data {
            switch byte {
            // Leading whitespace is legal and common: space, tab, newline,
            // carriage return.
            case 0x20, 0x09, 0x0A, 0x0D:
                continue

            case UInt8(ascii: "{"), UInt8(ascii: "["):
                return true

            default:
                return false
            }
        }

        // Empty, or nothing but whitespace. Not the API either.
        return false
    }

    static func makeBody(
        day: Date, window: SlotWindow?, identity: Identity = .anonymous
    ) -> AvailabilityRequestBody {
        AvailabilityRequestBody(
            facilityGroupID: tennisFacilityGroupID,

            // Zero is what unlocks the anonymous path. A real customer id sent
            // without a login is rejected 1507 — which is not a hypothetical
            // any more, now that the app can send a real one: it is exactly
            // the failure the anonymous replay below exists to absorb.
            customerID: identity.customerID,

            companyID: 0,
            reserveDate: CourtTime.dayString(from: day),
            startTime: window?.start.apiString,
            endTime: window?.end.apiString,
            resident: false,
            reload: false,
            changeTimeRange: window != nil
        )
    }

    /// What came back, and whether it came back as the identity that was asked
    /// for.
    ///
    /// The downgrade is reported in the returned value rather than held on the
    /// client, because the client is a struct handed around by value and a flag
    /// on it would be shared state with no owner. An app that dropped to
    /// anonymous while still saying "signed in" would be telling the user a lie
    /// they have no way to detect.
    nonisolated struct FetchOutcome: Sendable {
        let availability: Availability

        /// True when a signed-in fetch was refused and replayed anonymously.
        let downgradedToAnonymous: Bool
    }

    /// The anonymous fetch, unchanged in behaviour and in spelling.
    ///
    /// Kept so the proven path reads exactly as it always did, and so every
    /// existing caller and test still says what it meant. It is a one-line
    /// alias, not a second route: the implementation below is the only one.
    func fetch(on day: Date, window: SlotWindow? = nil) async throws -> Availability {
        try await fetch(on: day, window: window, as: .anonymous).availability
    }

    func fetch(
        on day: Date, window: SlotWindow? = nil, as identity: Identity
    ) async throws -> FetchOutcome {
        var sending = identity
        var payload = try JSONEncoder().encode(
            Self.makeBody(day: day, window: window, identity: sending))

        // Two plain counters, deliberately not recursion, and deliberately not
        // one counter doing both jobs — they bound two different things.
        var reHandshaked = false
        var replayedAnonymously = false

        while true {
            // One call, so the token and the jar cannot come from either side
            // of an interleaved invalidation. Asking for them separately left
            // a suspension point between the two in which a concurrent sign
            // out sent the old token with the new cookies.
            //
            // After an expiry the rotation is folded into the same call rather
            // than done as a separate invalidate followed by a fetch, which
            // reopens the gap this closes — the session offers the combined
            // form precisely so a retry does not have to spell it as two.
            let pairing =
                reHandshaked
                ? try await session.renewedPairing()
                : try await session.pairing()

            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(pairing.token, forHTTPHeaderField: "X-CSRF-Token")
            request.setValue("court-watch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

            // Sent through the transport the session currently owns, so the
            // token always travels with the cookies it was minted against.
            let (data, _) = try await pairing.transport.send(request)

            let envelope: AvailabilityEnvelope
            do {
                envelope = try JSONDecoder().decode(AvailabilityEnvelope.self, from: data)
            } catch {
                // Not a session problem either way. Re-handshaking would not
                // change the shape of the response, so both paths are terminal
                // for this request and neither issues a second POST.
                //
                // Which of the two it is decides what the user is told, and the
                // difference is worth one look at the first byte: the HTTP
                // status is deliberately never judged here, so a WAF
                // interstitial or a captive-portal page arrives exactly like a
                // schema change. Telling someone the app needs updating when
                // they are merely being filtered sends them to the App Store to
                // fix a network problem.
                guard Self.looksLikeJSON(data) else {
                    throw APIError.notJSON
                }

                throw APIError.decoding(String(describing: error))
            }

            switch ResponseCode.classify(envelope.headers) {
            case .success:
                let availability = Availability(envelope: envelope)

                guard availability.slotTimes.isEmpty == false else {
                    throw APIError.slotTimesMissing
                }

                return FetchOutcome(
                    availability: availability, downgradedToAnonymous: replayedAnonymously)

            case .expired(let code):
                // The second expiry is terminal. Without this the client loops
                // against a live, WAF-fronted public system.
                guard reHandshaked == false else {
                    throw APIError.sessionExpired(code: code)
                }

                // Rotating the pairing is now the first thing the next turn of
                // the loop does, as one call, rather than being done here and
                // fetched separately a moment later.
                reHandshaked = true

            case .service(let code, let message):
                // 1507 and friends mean the request was wrong, not the session.
                //
                // There is exactly one thing about the request this client can
                // usefully change, and it is the identity: a real customer id
                // on a session the server does not consider entitled to it was
                // measured to come back 1507. So a **signed-in** fetch that is
                // refused is replayed once as anonymous, and the user keeps the
                // grid they had before they ever signed in.
                //
                // **This is not a credential retry.** The replay is the same
                // availability POST with a different integer; this request has
                // never contained a credential and cannot acquire one. The rule
                // against resubmitting a credential automatically is about
                // something else entirely, and conflating the two would forbid
                // the one mechanism protecting the user from their own sign-in.
                //
                // Bounded at one, and only in the signed-in direction: an
                // anonymous fetch that is refused fails exactly as it always
                // has, with one POST and no replay.
                guard sending.isSignedIn, replayedAnonymously == false else {
                    throw APIError.service(code: code, message: message)
                }

                replayedAnonymously = true
                sending = .anonymous
                payload = try JSONEncoder().encode(
                    Self.makeBody(day: day, window: window, identity: .anonymous))
            }
        }
    }
}
