//
//  SessionProbe.swift
//  CourtWatch
//
//  Asks the server whether this cookie jar is signed in, and takes nothing but
//  the jar to do it.
//
//  Sending nothing is what makes this useful. It can be exercised by the test
//  suite, by a gate, and by anyone at any moment, without a single attempt
//  being spent against an account that arms a captcha after one wrong try. So
//  where the app has a choice between believing the sign-in reply — a shape
//  nobody has ever captured on success — and asking a question whose two
//  answers were both measured, it asks.
//
//  Matched pair, captured minutes apart: a signed-in browser and an anonymous
//  probe.
//
//      signed in    headers.response_code = "0000"
//      anonymous    headers.response_code = "0021"
//
//  ## Why this file classifies for itself
//
//  There is already a classifier — `ResponseCode.classify` — and it is correct,
//  and it must not be used here. `"0021"` is in `ResponseCode.expiry`, because
//  on the availability endpoint it means the handshake went stale and a
//  re-handshake is the right answer.
//
//  On *this* endpoint `"0021"` is the ordinary answer. It is what the app gets
//  almost every time it asks, because almost all the time nobody is signed in.
//  Routing it through the shared classifier would make the app throw away a
//  perfectly healthy session and re-handshake **every time it checked its own
//  state** — a loop, against a WAF-fronted host belonging to the Township,
//  produced entirely by reusing a rule that is right everywhere else.
//
//  So the rule is not in the code, it is in which endpoint is being asked, and
//  it therefore lives where the asking happens. A grep gate keeps
//  `ResponseCode.classify` out of this file, and the behaviour is pinned by
//  counting handshakes across ten consecutive probes rather than by checking
//  what the probe reported — a state-only assertion passes the loop, which is
//  exactly why it would have shipped.
//
//  Nothing here can throw the session away. A genuinely stale handshake is
//  replayed once by asking the session for a renewed pairing; there is no path
//  in this file that discards a jar because of an answer it did not like.
//

import Foundation

nonisolated struct SessionProbe: Sendable {

    /// Sent exactly as the browser sends it, including the `options` value.
    ///
    /// `%5Bobject%20Object%5D` is the string `[object Object]` — the web UI
    /// interpolating an object into a URL by accident. It is copied rather
    /// than corrected: this API has been observed to be literal about what it
    /// is given, and a "tidied" query is an experiment nobody asked for.
    static let endpoint =
        "https://anc.apm.activecommunities.com/wcscparksandrec"
        + "/rest/common/logincheck?locale=en-US&options=%5Bobject%20Object%5D"

    /// The answer that means this jar is signed in.
    static let authenticatedCode = "0000"

    /// The answer that means it simply is not. **Not an expiry here.**
    static let anonymousCode = "0021"

    /// Stale-handshake codes *on this endpoint*: the shared set, minus the one
    /// code that means something entirely different when this is the question.
    ///
    /// Derived from the shared set rather than copied, so a newly observed
    /// stale code still only has to be written down once — and so the
    /// divergence stays visibly one code wide instead of becoming a second
    /// list that drifts.
    static let staleCodes = ResponseCode.expiry.subtracting([anonymousCode])

    /// What the jar turned out to be.
    ///
    /// Three cases, not a boolean. A probe that could not reach the server has
    /// not established that anybody is anonymous, and collapsing those two
    /// would let a dropped connection quietly sign someone out.
    nonisolated enum Outcome: Equatable, Sendable {
        case authenticated
        case anonymous

        /// The reply could not be read. Carries what went wrong so a block
        /// page, a schema change and a dead network stay distinguishable.
        case unreadable(APIError)
    }

    private let session: CourtSession

    init(session: CourtSession) {
        self.session = session
    }

    /// Only the envelope is read. The body differs between the two captures as
    /// well, and neither difference is worth depending on: one is a timestamp
    /// this app has no business parsing, and the other's populated shape is a
    /// bare string in the single capture anyone has.
    private nonisolated struct ProbeEnvelope: Decodable, Sendable {
        let headers: ResponseHeaders
    }

    func check() async -> Outcome {
        var replayed = false

        while true {
            do {
                let token =
                    replayed
                    ? try await session.renewedToken()
                    : try await session.token()

                let transport = await session.currentTransport()

                // A cache-buster, as the web UI sends. Nothing depends on the
                // value; it exists so an intermediary cannot answer this from
                // a copy of somebody else's session state.
                var request = URLRequest(
                    url: URL(string: "\(Self.endpoint)&ui_random=\(Int.random(in: 1...9_999_999))")!)
                request.httpMethod = "GET"
                request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
                request.setValue("court-watch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

                let (data, _) = try await transport.send(request)

                let envelope: ProbeEnvelope
                do {
                    envelope = try JSONDecoder().decode(ProbeEnvelope.self, from: data)
                } catch {
                    // The same distinction the availability path draws, and for
                    // the same reason: the HTTP status is never judged, so a
                    // block page arrives looking exactly like a schema change.
                    guard AvailabilityClient.looksLikeJSON(data) else {
                        return .unreadable(.notJSON)
                    }

                    return .unreadable(.decoding(String(describing: error)))
                }

                let code = envelope.headers.responseCode

                if code == Self.authenticatedCode {
                    return .authenticated
                }

                // The whole point of this file. Normal, cheap, and emphatically
                // not a reason to touch the session.
                if code == Self.anonymousCode {
                    return .anonymous
                }

                if Self.staleCodes.contains(code) {
                    // One replay, then it is terminal — the same bound the
                    // availability path keeps, and for the same WAF-facing
                    // reason.
                    guard replayed == false else {
                        return .unreadable(.sessionExpired(code: code))
                    }

                    replayed = true
                    continue
                }

                return .unreadable(
                    .service(code: code, message: envelope.headers.responseMessage))
            } catch let error as APIError {
                return .unreadable(error)
            } catch {
                return .unreadable(.transport(.unknown))
            }
        }
    }
}
