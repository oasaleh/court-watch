//
//  FailureSimulation.swift
//  CourtWatch
//
//  A debug-only way to make every failure actually happen on a device.
//
//  Four of the failure classes cannot be produced by any device setting — you
//  cannot turn off Wi-Fi in a way that yields a WAF block page, a schema
//  change, a refused request, or an exhausted session. Without this, a human
//  checking the failure copy can confirm one screen and take the rest on trust.
//
//  **The injection point is the transport, not the screen**, and that choice
//  does real work beyond convenience: because it injects where the test suite
//  already injects, inducing a stale-token code exercises the *real* client,
//  its *real* re-handshake, and its *real* one-shot retry end to end in the
//  running app, rather than posing a screen that looks like the outcome. It is
//  the only way SESS-04's terminal path is ever seen rather than asserted.
//
//  The whole file is `#if DEBUG`. That is gated by building `-configuration
//  Release` and searching the *binary* for the trigger string — a stronger
//  claim than any grep over source, because it is a statement about the
//  artifact rather than about the text that produced it.
//
//  It lives in `Support` rather than under `Features` deliberately: it vends a
//  transport, and the feature directory is grep-gated against exactly that kind
//  of type.
//
//  Selection is by **process environment**, not by `UserDefaults`. The launch
//  argument form writes into the defaults argument domain, and `FavoritesStore`
//  reads `UserDefaults` — keeping the harness out of that store entirely means
//  it cannot perturb the favorites the checkpoint is about to exercise.
//
//      SIMCTL_CHILD_COURTWATCH_SIMULATE_FAILURE=blocked \
//          xcrun simctl launch <udid> <bundle-id>
//

#if DEBUG

    import Foundation

    nonisolated enum FailureSimulation {

        /// Read from the process environment. Measured to arrive when set via
        /// `SIMCTL_CHILD_` on `xcrun simctl launch`.
        static let environmentKey = "COURTWATCH_SIMULATE_FAILURE"

        /// What can be induced.
        ///
        /// Note that `degraded` and `warning` are **not** failures. They are the
        /// two ordinary states the captured data cannot produce — every court in
        /// both captures publishes sixteen readable statuses — and they are the
        /// whole reason the defensive decoding and the notices are worth looking
        /// at by eye.
        enum Scenario: String, CaseIterable, Sendable {

            /// A transport failure with a not-connected code.
            case offline

            /// A transport failure with a timed-out code, which must read
            /// differently from `offline`.
            case timeout

            /// An HTML error page instead of JSON, as an F5 ASM WAF or a
            /// captive portal would send.
            case blocked

            /// JSON of the wrong shape, which must read differently from
            /// `blocked`.
            case garbled

            /// A non-expiry service code.
            case refused

            /// An expiry code, twice — driving the real re-handshake and the
            /// real one-shot retry to their terminal state.
            case expired

            /// A success carrying no slot times.
            case empty

            /// A good payload with one short court, one court carrying
            /// unreadable statuses mid-row, and one resource that cannot be
            /// read at all.
            case degraded

            /// A good payload carrying a warning the app has not accounted for,
            /// alongside the residency notice it has.
            case warning

            /// One good response, then nothing — a failed refresh over data
            /// that is still on screen.
            case stale

            // MARK: Sign-in
            //
            // Every one of these answers from a payload built by hand. **This
            // is the only place a credential failure may ever be rehearsed**:
            // one wrong attempt against the real service arms an extra
            // verification step on the user's actual booking account, which
            // this app cannot undo. A fabricated reply tells you everything
            // about how the app behaves and costs nothing, which makes the live
            // version not merely dangerous but pointless.

            /// The credentials are refused — driven by the **real captured
            /// failure body**, which is the one true example anyone has and
            /// which carries the trap: `response_code` `0000` on a rejection.
            case signInRefused

            /// The service demands a verification challenge the app cannot
            /// present.
            case signInCaptcha

            /// A sign-in that works, confirms, and yields an id.
            case signedIn

            /// A sign-in that works and hands back nothing usable.
            case signInNoIdentity

            /// A sign-in whose body reports success and whose session check
            /// disagrees. The app must end up **anonymous**, which is the one
            /// case where it deliberately disbelieves a success.
            case signInUnconfirmed

            /// A signed-in fetch the server refuses, driving the real anonymous
            /// replay rather than posing its result.
            case signedInRefused
        }

        /// Unset, empty, or unrecognised means no simulation.
        ///
        /// **Defaults to reality on purpose.** A harness that failed closed
        /// would make a mistyped value look like a broken app, and the person
        /// typing it is about to judge whether the app is broken.
        static func scenario(from value: String?) -> Scenario? {
            guard let value, value.isEmpty == false else { return nil }

            return Scenario(rawValue: value)
        }

        /// The session to fetch through, or `nil` when nothing is being
        /// simulated and the app should talk to the real endpoint.
        ///
        /// The transport is process-wide rather than per-session because a
        /// session does not survive everything: `invalidate()` replaces the
        /// transport it holds, and the app builds this session once at launch.
        /// A scenario like `stale` — one good response, then failures — is a
        /// claim about the *sequence* of loads rather than about one of them,
        /// so what answers has to outlive any single session.
        static func makeSession() -> CourtSession? {
            guard let transport = sharedTransport else { return nil }

            return CourtSession { transport }
        }

        private static let sharedTransport: (any HTTPTransport)? = {
            guard
                let scenario = scenario(
                    from: ProcessInfo.processInfo.environment[environmentKey])
            else { return nil }

            return makeTransport(for: scenario)
        }()

        /// A fresh transport for one scenario. The test suite drives these
        /// directly, which is what makes the checkpoint trustworthy: without it
        /// an approval could rest on a harness producing something other than
        /// what it claims, and the whole exercise would prove nothing.
        static func makeTransport(for scenario: Scenario) -> SimulatedTransport {
            switch scenario {
            case .offline:
                return SimulatedTransport { _, _ in
                    .failure(APIError.transport(.notConnectedToInternet))
                }

            case .timeout:
                return SimulatedTransport { _, _ in
                    .failure(APIError.transport(.timedOut))
                }

            case .blocked:
                return answering(post: .success(Data(blockPage.utf8)))

            case .garbled:
                return answering(post: .success(Data(wrongShape.utf8)))

            case .refused:
                return answering(
                    post: .success(Data(envelope(code: "1507", message: "Invalid request").utf8)))

            case .expired:
                // Both attempts answer the same expiry code. The client
                // re-handshakes once, replays once, and stops — two handshakes
                // and two POSTs, exactly as the client suite pins for the real
                // thing.
                return answering(
                    post: .success(
                        Data(envelope(code: "0012", message: "Invalid CSRF token").utf8)))

            case .empty:
                return answering(post: .success(Data(emptyDay.utf8)))

            case .degraded:
                return answering(post: .success(Data(degradedPayload.utf8)))

            case .warning:
                return answering(post: .success(Data(warningPayload.utf8)))

            case .stale:
                // The first POST succeeds; everything from then on fails,
                // including the handshake, which is what being disconnected
                // after a good load actually looks like.
                return SimulatedTransport { request, postsAnswered in
                    if request.httpMethod == "POST" {
                        return postsAnswered == 0
                            ? .success(Data(goodPayload.utf8))
                            : .failure(APIError.transport(.notConnectedToInternet))
                    }

                    return postsAnswered == 0
                        ? .success(Data(handshakePage.utf8))
                        : .failure(APIError.transport(.notConnectedToInternet))
                }

            case .signInRefused:
                return routing(signIn: capturedRejection)

            case .signInCaptcha:
                return routing(signIn: captchaDemand)

            case .signedIn:
                return routing(signIn: inventedSuccess, check: signedInCheck)

            case .signInNoIdentity:
                return routing(signIn: inventedSuccessWithoutIdentity, check: signedInCheck)

            case .signInUnconfirmed:
                // The body says it worked. The check — the only part of this
                // whose answers were actually measured — says the jar is
                // anonymous. The app must believe the check.
                return routing(signIn: inventedSuccess, check: anonymousCheck)

            case .signedInRefused:
                return routing(
                    signIn: inventedSuccess, check: signedInCheck, refusingRealCustomerID: true)
            }
        }

        /// The common shape: the handshake always succeeds, every POST gets the
        /// same answer.
        ///
        /// Answering by request rather than from a queue means a retry behaves
        /// like the first attempt, which is what a person tapping Try Again
        /// expects and what a drained queue would get wrong.
        private static func answering(
            post answer: Result<Data, any Error>
        ) -> SimulatedTransport {
            SimulatedTransport { request, _ in
                request.httpMethod == "POST" ? answer : .success(Data(handshakePage.utf8))
            }
        }

        /// Answers the sign-in POST, the session check and the availability
        /// POST **separately**.
        ///
        /// They are three different URLs, and a scenario that answered them
        /// alike would make a signed-in grid impossible to look at — the thing
        /// the person running the checkpoint is there to judge.
        private static func routing(
            signIn: String,
            check: String = anonymousCheck,
            refusingRealCustomerID: Bool = false
        ) -> SimulatedTransport {
            SimulatedTransport { request, _ in
                let url = request.url?.absoluteString ?? ""

                if url.contains("logincheck") {
                    return .success(Data(check.utf8))
                }

                if url.contains("signin") {
                    return .success(Data(signIn.utf8))
                }

                guard request.httpMethod == "POST" else {
                    return .success(Data(handshakePage.utf8))
                }

                // Judged on what the request actually carries rather than on a
                // count, so it drives the real fallback whatever order the
                // person at the checkpoint does things in: sign in first,
                // browse first, refresh in between.
                if refusingRealCustomerID && carriesRealCustomerID(request) {
                    return .success(
                        Data(envelope(code: "1507", message: "Invalid request").utf8))
                }

                return .success(Data(goodPayload.utf8))
            }
        }

        /// Whether an availability POST is claiming to be somebody.
        private static func carriesRealCustomerID(_ request: URLRequest) -> Bool {
            guard
                let body = request.httpBody,
                let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                let identifier = object["customer_id"] as? Int
            else { return false }

            return identifier != 0
        }
    }

    // MARK: - The transport

    /// Answers from a closure and records what it was asked, in the same shape
    /// the client suite already uses — because that shape is known to drive
    /// every path in the client.
    ///
    /// Reaches no network by construction: there is no `URLSession` here.
    nonisolated final class SimulatedTransport: HTTPTransport, @unchecked Sendable {

        private let lock = NSLock()
        private let respond: @Sendable (URLRequest, Int) -> Result<Data, any Error>
        private var recorded: [URLRequest] = []
        private var postsAnswered = 0

        init(respond: @escaping @Sendable (URLRequest, Int) -> Result<Data, any Error>) {
            self.respond = respond
        }

        var requestCount: Int { lock.withLock { recorded.count } }
        var postCount: Int { lock.withLock { recorded.filter { $0.httpMethod == "POST" }.count } }

        /// Everything it was asked, so a test can check what actually went out
        /// rather than inferring it from a total.
        var recordedRequests: [URLRequest] { lock.withLock { recorded } }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let result: Result<Data, any Error> = lock.withLock {
                recorded.append(request)

                let answer = respond(request, postsAnswered)

                if request.httpMethod == "POST" { postsAnswered += 1 }

                return answer
            }

            let body = try result.get()

            return (
                body,
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    // MARK: - Payloads, built by hand

    /// Small on purpose: three courts is enough to see a short row beside a
    /// whole one, and it makes the screen legible at a glance instead of eighty
    /// rows deep.
    nonisolated extension FailureSimulation {

        fileprivate static let handshakePage =
            "<script>window.__csrfToken = \"370060c8-52de-4fc9-a95c-b5cfff762b53\";</script>"

        fileprivate static let blockPage = """
            <html><head><title>Request Rejected</title></head>
            <body>The requested URL was rejected. Please consult with your administrator.</body>
            </html>
            """

        fileprivate static let wrongShape = """
            {"headers": {"response_code": "0000"}, "body": {"schedule": [], "version": 2}}
            """

        /// The published day, 7 AM to 10 PM.
        fileprivate static let slotTimes = [
            "07:00:00", "08:00:00", "09:00:00", "10:00:00",
            "11:00:00", "12:00:00", "13:00:00", "14:00:00",
            "15:00:00", "16:00:00", "17:00:00", "18:00:00",
            "19:00:00", "20:00:00", "21:00:00", "22:00:00",
        ]

        /// The notice all 80 courts carry in both captures, which the app has
        /// already accounted for by only ever showing today.
        fileprivate static let residencyNotice =
            "Non-residents cannot make reservations more than 2 day(s) in advance."

        fileprivate static func envelope(code: String, message: String) -> String {
            """
            {"headers":{"response_code":"\(code)","response_message":"\(message)",
            "sessionRefreshedOn":null},"body":{"availability":{"time_slots":[],
            "resources":[],"time_increment":60}}}
            """
        }

        fileprivate static let emptyDay = """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"availability":{"time_slots":[],
            "resources":[],"time_increment":60}}}
            """

        private static func availability(resources: [String]) -> String {
            let times = slotTimes.map { "\"\($0)\"" }.joined(separator: ", ")

            return """
                {
                  "headers": {
                    "response_code": "0000", "response_message": "Successful",
                    "sessionRefreshedOn": null
                  },
                  "body": { "availability": {
                    "time_slots": [\(times)],
                    "resources": [\(resources.joined(separator: ",\n"))],
                    "time_increment": 60
                  } }
                }
                """
        }

        private static func resource(
            id: String, name: String, details: [String], warnings: [String] = [residencyNotice]
        ) -> String {
            let warningList = warnings.map { "\"\($0)\"" }.joined(separator: ", ")

            return """
                {
                  "resource_id": \(id),
                  "resource_name": \(name),
                  "warning_messages": [\(warningList)],
                  "time_slot_details": [\(details.joined(separator: ", "))]
                }
                """
        }

        /// A plausible day: mostly booked in the evening, free in the middle.
        private static let ordinaryStatuses = [
            "0", "0", "1", "1", "0", "0", "1", "0",
            "0", "1", "1", "1", "1", "0", "1", "0",
        ].map { "{\"status\": \($0)}" }

        private static let otherStatuses = [
            "1", "0", "0", "1", "1", "0", "0", "1",
            "0", "0", "1", "1", "0", "1", "0", "1",
        ].map { "{\"status\": \($0)}" }

        /// The same row with 11 AM, noon and 1 PM unreadable.
        ///
        /// Deliberately in the *middle*. A shift caused by dropping them rather
        /// than holding their places would be visible here as the afternoon
        /// sliding an hour earlier, which is the one wrong answer this app must
        /// never give.
        private static let statusesWithUnreadableMiddle = otherStatuses.enumerated().map {
            index, detail in
            (4...6).contains(index) ? "{\"status\": null}" : detail
        }

        /// Courts spread across four real facilities.
        ///
        /// Deliberately not one facility. The harness has to show a grid
        /// whatever the person running it happens to have favorited, and a
        /// payload naming a single place shows them the choose-your-facilities
        /// invitation instead of the screen they are trying to judge. These
        /// four are real names from the capture, so a favorite made against the
        /// live API resolves against the simulation too.
        private static func spread(
            bearBranch3: [String],
            shadowbend2: [String],
            meadowlake1: [String],
            extraWarningOnShadowbend1: Bool = false
        ) -> [String] {
            let resources = [
                resource(id: "1", name: "\"Bear Branch Tennis 1\"", details: ordinaryStatuses),
                resource(id: "2", name: "\"Bear Branch Tennis 2\"", details: otherStatuses),
                resource(id: "3", name: "\"Bear Branch Tennis 3\"", details: bearBranch3),
                resource(
                    id: "4", name: "\"Shadowbend Tennis 1\"", details: ordinaryStatuses,
                    warnings: extraWarningOnShadowbend1
                        ? [residencyNotice, "This facility is closed for maintenance today."]
                        : [residencyNotice]),
                resource(id: "5", name: "\"Shadowbend Tennis 2\"", details: shadowbend2),
                resource(id: "6", name: "\"Meadowlake Tennis 1\"", details: meadowlake1),
                resource(id: "7", name: "\"Falconwing Tennis 1\"", details: ordinaryStatuses),
            ]

            return resources
        }

        fileprivate static let goodPayload = availability(
            resources: spread(
                bearBranch3: ordinaryStatuses,
                shadowbend2: otherStatuses,
                meadowlake1: ordinaryStatuses))

        /// Everything the tolerant decoding and the notices exist for, at once:
        /// whole rows, rows with unreadable statuses in the middle, short rows
        /// on two different facilities, and a resource that cannot be read at
        /// all.
        fileprivate static let degradedPayload = availability(
            resources: spread(
                // Ten details against sixteen slots: short, named, padded.
                bearBranch3: Array(ordinaryStatuses.prefix(10)),
                shadowbend2: statusesWithUnreadableMiddle,
                // A second short court, so the notice reads in the plural.
                meadowlake1: Array(ordinaryStatuses.prefix(12))
            )
                // No readable id: dropped, and counted. Reads in the singular.
                + [
                    resource(
                        id: "null", name: "\"Cranebrook Tennis 1\"", details: ordinaryStatuses)
                ])

        // MARK: Sign-in payloads
        //
        // **No real credential appears anywhere here, or anywhere in this
        // repository.** The two session-check envelopes are captured; the
        // rejection is captured; everything else is invented and says so.

        /// The **real captured rejection**, kept verbatim.
        ///
        /// Note `response_code: "0000"` — *Successful* — beside
        /// `success: false`. That is the trap this whole path exists around,
        /// and keeping the body unedited is what makes the rehearsal worth
        /// anything.
        ///
        /// Note also `need_verify_recaptcha: true`: the captured rejection
        /// **already carries the captcha flag**, which is why a refusal and a
        /// challenge cannot be told apart by that flag alone.
        static let capturedRejection = """
            {"headers":{"sessionRefreshedOn":null,"sessionExtendedCount":0,
            "response_code":"0000","response_message":"Successful"},
            "body":{"result":{"success":false,"message":"Invalid login name or password",
            "error_type":0,"redirect_url":null,"security_sign_token":null,
            "public_customer_id":null,"sign_in_token_id":null,"customer":null,
            "access_token":null,"refresh_token":null,"ak_update_succeed":false,
            "enable_gpap":false,"need_verify_recaptcha":true}}}
            """

        /// A challenge with no reason named.
        ///
        /// Derived from the captured rejection by clearing the message rather
        /// than by setting the flag, because the flag is already set there. A
        /// pure challenge is a refusal that demands verification while saying
        /// nothing about the credentials; a refusal that names a reason is a
        /// refusal. That ordering is the app's rule, and this payload is the
        /// shape it distinguishes.
        fileprivate static let captchaDemand = """
            {"headers":{"sessionRefreshedOn":null,"response_code":"0000",
            "response_message":"Successful"},
            "body":{"result":{"success":false,"message":null,
            "need_verify_recaptcha":true}}}
            """

        /// **Invented.** No success response has ever been captured, so this
        /// follows the field names the captured failure revealed and adds
        /// nothing beyond them. The id is obviously fake.
        fileprivate static let inventedSuccess = """
            {"headers":{"sessionRefreshedOn":"2026-07-27 10:13:17","response_code":"0000",
            "response_message":"Successful"},
            "body":{"result":{"success":true,"message":null,"error_type":0,
            "public_customer_id":4471056,"sign_in_token_id":"simulated-token-id",
            "security_sign_token":"simulated-security-token",
            "access_token":"simulated-access-token","refresh_token":"simulated-refresh-token",
            "customer":null,"ak_update_succeed":true,"enable_gpap":false,
            "need_verify_recaptcha":false}}}
            """

        /// **Invented**, the same shape with nothing usable to identify anyone.
        fileprivate static let inventedSuccessWithoutIdentity = """
            {"headers":{"sessionRefreshedOn":"2026-07-27 10:13:17","response_code":"0000",
            "response_message":"Successful"},
            "body":{"result":{"success":true,"message":null,"public_customer_id":null,
            "customer":null,"access_token":"simulated-access-token",
            "need_verify_recaptcha":false}}}
            """

        /// The **captured** signed-in answer from the session check.
        fileprivate static let signedInCheck = """
            {"headers":{"sessionRefreshedOn":"2026-07-27 10:13:17","sessionExtendedCount":1,
            "response_code":"0000","response_message":"Successful"},
            "body":{"result":"successful"}}
            """

        /// The **captured** anonymous answer. `0021` here is the ordinary
        /// reply, not an expiry.
        fileprivate static let anonymousCheck = """
            {"headers":{"sessionRefreshedOn":null,"sessionExtendedCount":0,
            "response_code":"0021","response_message":"User not login"},"body":{}}
            """

        /// The residency notice on every court, plus one the app has not
        /// accounted for — so the strip shows exactly one line.
        fileprivate static let warningPayload = availability(
            resources: spread(
                bearBranch3: ordinaryStatuses,
                shadowbend2: otherStatuses,
                meadowlake1: ordinaryStatuses,
                extraWarningOnShadowbend1: true))
    }

#endif
