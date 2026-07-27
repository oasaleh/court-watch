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
        /// The transport is process-wide rather than per-session because
        /// `ContentView` builds a fresh `CourtSession` for every load, and
        /// `stale` — one good response, then failures — is a claim about the
        /// sequence of loads rather than about one of them.
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

        fileprivate static let goodPayload = availability(resources: [
            resource(id: "1", name: "\"Bear Branch Tennis 1\"", details: ordinaryStatuses),
            resource(id: "2", name: "\"Bear Branch Tennis 2\"", details: otherStatuses),
            resource(id: "3", name: "\"Bear Branch Tennis 3\"", details: ordinaryStatuses),
        ])

        /// Everything the tolerant decoding and the notices exist for, at once:
        /// a whole row, a row with unreadable statuses in the middle, a short
        /// row, and a resource that cannot be read at all.
        fileprivate static let degradedPayload = availability(resources: [
            resource(id: "1", name: "\"Bear Branch Tennis 1\"", details: ordinaryStatuses),

            // Unreadable statuses at 11 AM, noon and 1 PM. Each holds its own
            // place — the hours after them must still be their own.
            resource(
                id: "2", name: "\"Bear Branch Tennis 2\"",
                details: otherStatuses.enumerated().map { index, detail in
                    (4...6).contains(index) ? "{\"status\": null}" : detail
                }),

            // Ten details against sixteen slots: short, named, padded.
            resource(
                id: "3", name: "\"Bear Branch Tennis 3\"",
                details: Array(ordinaryStatuses.prefix(10))),

            // No readable id: dropped, and counted.
            resource(id: "null", name: "\"Bear Branch Tennis 4\"", details: ordinaryStatuses),
        ])

        /// The residency notice on every court, plus one the app has not
        /// accounted for — so the strip shows exactly one line.
        fileprivate static let warningPayload = availability(resources: [
            resource(id: "1", name: "\"Bear Branch Tennis 1\"", details: ordinaryStatuses),
            resource(
                id: "2", name: "\"Bear Branch Tennis 2\"", details: otherStatuses,
                warnings: [residencyNotice, "This facility is closed for maintenance today."]),
            resource(id: "3", name: "\"Bear Branch Tennis 3\"", details: ordinaryStatuses),
        ])
    }

#endif
