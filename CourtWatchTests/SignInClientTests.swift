//
//  SignInClientTests.swift
//  CourtWatchTests
//
//  Drives the real client against fabricated replies.
//
//  **No test in this project may submit a credential to the live endpoint**,
//  right or wrong. One wrong attempt arms a captcha on a real booking account,
//  and a fabricated reply tells you everything about how the app behaves for
//  nothing — which makes the live version not merely dangerous but pointless.
//
//  The assertion with the sharpest teeth here is the negative one: the password
//  appears in the POST body the transport recorded, and **in nothing else the
//  client produced** — no URL, no header, no error value.
//

import Foundation
import Testing

@testable import CourtWatch

private nonisolated let firstToken = "370060c8-52de-4fc9-a95c-b5cfff762b53"
private nonisolated let refreshedToken = "a1b2c3d4-1111-2222-3333-444455556666"

private nonisolated func handshakePage(token: String) -> String {
    "<script>window.__csrfToken = \"\(token)\";</script>"
}

/// Obviously fake, and never used against anything real.
private nonisolated let testCredentials = Credentials(
    username: "someone@example.invalid", password: "MARKER_PASSWORD_VALUE")

private nonisolated let signedInProbeReply = """
    {"headers":{"sessionRefreshedOn":"2026-07-27 10:13:17","response_code":"0000",
    "response_message":"Successful"},"body":{"result":"successful"}}
    """

private nonisolated let anonymousProbeReply = """
    {"headers":{"sessionRefreshedOn":null,"response_code":"0021",
    "response_message":"User not login"},"body":{}}
    """

private nonisolated func signInReply(_ result: String) -> String {
    """
    {"headers":{"response_code":"0000","response_message":"Successful",
    "sessionRefreshedOn":null},"body":{"result":\(result)}}
    """
}

private nonisolated func envelope(code: String, message: String) -> String {
    """
    {"headers":{"response_code":"\(code)","response_message":"\(message)",
    "sessionRefreshedOn":null},"body":{}}
    """
}

/// Answers each of the three URLs separately and records everything.
private nonisolated final class SignInTransport: HTTPTransport, @unchecked Sendable {

    enum Kind { case handshake, signIn, probe }

    private let lock = NSLock()
    private let respond: @Sendable (Kind, Int) -> Result<Data, any Error>
    private var recorded: [URLRequest] = []
    private var signInsAnswered = 0

    init(respond: @escaping @Sendable (Kind, Int) -> Result<Data, any Error>) {
        self.respond = respond
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func count(of kind: Kind) -> Int {
        lock.withLock { recorded.filter { Self.kind(of: $0) == kind }.count }
    }

    var posts: [URLRequest] { lock.withLock { recorded.filter { $0.httpMethod == "POST" } } }

    static func kind(of request: URLRequest) -> Kind {
        let url = request.url?.absoluteString ?? ""

        if url.contains("logincheck") { return .probe }
        if url.contains("signin") { return .signIn }

        return .handshake
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result: Result<Data, any Error> = lock.withLock {
            recorded.append(request)

            let kind = Self.kind(of: request)
            let answer = respond(kind, kind == .signIn ? signInsAnswered : -1)

            if kind == .signIn { signInsAnswered += 1 }

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

/// The common arrangement: handshake fine, one sign-in reply, one probe reply.
private nonisolated func transport(
    signIn: String, probe: String = signedInProbeReply
) -> SignInTransport {
    SignInTransport { kind, _ in
        switch kind {
        case .handshake: return .success(Data(handshakePage(token: firstToken).utf8))
        case .signIn: return .success(Data(signIn.utf8))
        case .probe: return .success(Data(probe.utf8))
        }
    }
}

private nonisolated func client(_ transport: SignInTransport) -> SignInClient {
    SignInClient(session: CourtSession { transport })
}

struct SignInClientTests {

    // MARK: - The four outcomes, end to end

    @Test("A rejection carrying a 0000 envelope is reported as a rejection")
    func rejectionIsNotSuccess() async throws {
        let sent = transport(
            signIn: signInReply(
                #"{"success":false,"message":"Invalid login name or password","need_verify_recaptcha":true}"#
            ))

        #expect(try await client(sent).signIn(as: testCredentials) == .rejected)

        // A rejection is terminal: no replay, and nothing was confirmed.
        #expect(sent.count(of: .signIn) == 1)
        #expect(sent.count(of: .probe) == 0)
    }

    @Test("A captcha demand is its own outcome")
    func captchaIsDistinct() async throws {
        let sent = transport(
            signIn: signInReply(#"{"success":false,"message":null,"need_verify_recaptcha":true}"#))

        #expect(try await client(sent).signIn(as: testCredentials) == .captchaRequired)
    }

    @Test("A confirmed success yields the identity from the reply")
    func confirmedSuccessYieldsIdentity() async throws {
        let sent = transport(signIn: signInReply(#"{"success":true,"public_customer_id":4471056}"#))

        #expect(
            try await client(sent).signIn(as: testCredentials) == .signedIn(customerID: 4_471_056))
    }

    @Test("A success carrying no id leaves the app without one")
    func successWithoutIdentity() async throws {
        let sent = transport(
            signIn: signInReply(#"{"success":true,"public_customer_id":null}"#))

        #expect(try await client(sent).signIn(as: testCredentials) == .succeededWithoutIdentity)

        // Nothing to confirm, so nothing was asked.
        #expect(sent.count(of: .probe) == 0)
    }

    // MARK: - The confirmation

    /// **The app disbelieves a success the measured endpoint will not confirm.**
    ///
    /// The reply says it worked and carries an id. The session check says the
    /// jar is anonymous. The check is the one whose answers were measured in
    /// both directions, so it wins, and the app stays anonymous.
    @Test("A success the session check will not confirm leaves the app anonymous")
    func unconfirmedSuccessIsNotSignedIn() async throws {
        let sent = transport(
            signIn: signInReply(#"{"success":true,"public_customer_id":4471056}"#),
            probe: anonymousProbeReply)

        let outcome = try await client(sent).signIn(as: testCredentials)

        #expect(outcome == .succeededWithoutIdentity)
        #expect(outcome != .signedIn(customerID: 4_471_056))
        #expect(sent.count(of: .probe) == 1, "the reply was believed without being checked")
    }

    /// A confirmation that could not be reached is not a confirmation either.
    @Test("A success the session check cannot reach leaves the app anonymous")
    func unreachableConfirmationIsNotSignedIn() async throws {
        let sent = SignInTransport { kind, _ in
            switch kind {
            case .handshake: return .success(Data(handshakePage(token: firstToken).utf8))
            case .signIn:
                return .success(
                    Data(signInReply(#"{"success":true,"public_customer_id":4471056}"#).utf8))
            case .probe: return .failure(APIError.transport(.notConnectedToInternet))
            }
        }

        #expect(try await client(sent).signIn(as: testCredentials) == .succeededWithoutIdentity)
    }

    /// The confirmation costs exactly one request, on a path the user just
    /// deliberately triggered.
    @Test("Confirming a success costs one extra request and no more")
    func confirmationCostsOneRequest() async throws {
        let sent = transport(signIn: signInReply(#"{"success":true,"public_customer_id":4471056}"#))

        _ = try await client(sent).signIn(as: testCredentials)

        #expect(sent.count(of: .handshake) == 1)
        #expect(sent.count(of: .signIn) == 1)
        #expect(sent.count(of: .probe) == 1)
    }

    // MARK: - The credential goes exactly one place

    /// The password is in the POST body, and in nothing else the client
    /// produced — no URL, no header, nowhere.
    @Test("The password reaches the request body and nothing else")
    func passwordReachesOnlyTheBody() async throws {
        let sent = transport(signIn: signInReply(#"{"success":true,"public_customer_id":4471056}"#))

        _ = try await client(sent).signIn(as: testCredentials)

        let marker = "MARKER_PASSWORD_VALUE"
        var found = 0

        for request in sent.requests {
            #expect(
                (request.url?.absoluteString ?? "").contains(marker) == false,
                "the credential reached a URL")

            for (_, value) in request.allHTTPHeaderFields ?? [:] {
                #expect(value.contains(marker) == false, "the credential reached a header")
            }

            if let body = request.httpBody, String(decoding: body, as: UTF8.self).contains(marker) {
                found += 1
            }
        }

        #expect(found == 1, "the credential should appear in exactly one request body")
    }

    /// And it is not in the error the client throws, whatever went wrong.
    @Test("No failure the client throws mentions the credential")
    func failuresCarryNoCredential() async throws {
        let cases: [String] = [
            "<html><body>The requested URL was rejected.</body></html>",
            "{not json at all",
            #"{"headers":{"response_code":"1507","response_message":"Invalid request"},"body":{}}"#,
        ]

        for reply in cases {
            let sent = transport(signIn: reply)

            do {
                _ = try await client(sent).signIn(as: testCredentials)
            } catch {
                let text = String(describing: error)

                #expect(text.contains("MARKER_PASSWORD_VALUE") == false, "credential in \(text)")
                #expect(text.contains("example.invalid") == false, "username in \(text)")
            }
        }
    }

    /// The reply's own prose never leaves the client either.
    @Test("The reply's message is not carried into any outcome or error")
    func replyMessageDoesNotEscape() async throws {
        let sent = transport(
            signIn: signInReply(
                #"{"success":false,"message":"MARKER_SERVER_PROSE","need_verify_recaptcha":false}"#))

        let outcome = try await client(sent).signIn(as: testCredentials)

        #expect(outcome == .rejected)
        #expect(String(describing: outcome).contains("MARKER_SERVER_PROSE") == false)
    }

    // MARK: - The shared retry rules, not a second copy

    /// A stale token during sign-in re-handshakes once and replays once,
    /// exactly as availability does — and the replay carries the refreshed
    /// token, which a count-only assertion would not notice.
    @Test(
        "A stale token re-handshakes once and replays once",
        arguments: ["0002", "0007", "0010", "0012", "0021"]
    )
    func staleTokenReplaysOnce(code: String) async throws {
        let sent = SignInTransport { kind, signInsAnswered in
            switch kind {
            case .handshake:
                return .success(
                    Data(
                        handshakePage(
                            token: signInsAnswered == -1 ? firstToken : firstToken
                        ).utf8))
            case .signIn:
                return signInsAnswered == 0
                    ? .success(Data(envelope(code: code, message: "stale").utf8))
                    : .success(
                        Data(signInReply(#"{"success":true,"public_customer_id":4471056}"#).utf8))
            case .probe:
                return .success(Data(signedInProbeReply.utf8))
            }
        }

        #expect(
            try await client(sent).signIn(as: testCredentials) == .signedIn(customerID: 4_471_056))

        #expect(sent.count(of: .signIn) == 2)
        #expect(sent.count(of: .handshake) == 2)
    }

    @Test("The replay carries the refreshed token, not the rejected one")
    func replayCarriesTheRefreshedToken() async throws {
        let sent = SignInTransport { kind, signInsAnswered in
            switch kind {
            case .handshake:
                return .success(Data(handshakePage(token: refreshedToken).utf8))
            case .signIn:
                return signInsAnswered == 0
                    ? .success(Data(envelope(code: "0012", message: "stale").utf8))
                    : .success(
                        Data(signInReply(#"{"success":true,"public_customer_id":4471056}"#).utf8))
            case .probe:
                return .success(Data(signedInProbeReply.utf8))
            }
        }

        _ = try await client(sent).signIn(as: testCredentials)

        let signIns = sent.requests.filter { SignInTransport.kind(of: $0) == .signIn }

        #expect(signIns.count == 2)
        #expect(signIns.last?.value(forHTTPHeaderField: "X-CSRF-Token") == refreshedToken)
    }

    /// Terminal after one replay, like everything else that talks to this host.
    @Test("A stale token twice gives up rather than looping")
    func staleTokenTwiceStops() async throws {
        let sent = transport(signIn: envelope(code: "0012", message: "Invalid CSRF token"))

        await #expect(throws: APIError.sessionExpired(code: "0012")) {
            try await client(sent).signIn(as: testCredentials)
        }

        #expect(sent.count(of: .signIn) == 2)
    }

    /// A service code is not a rejection and is not retried.
    @Test("A service code throws without a replay")
    func serviceCodeIsTerminal() async throws {
        let sent = transport(signIn: envelope(code: "1507", message: "Invalid request"))

        await #expect(throws: APIError.service(code: "1507", message: "Invalid request")) {
            try await client(sent).signIn(as: testCredentials)
        }

        #expect(sent.count(of: .signIn) == 1)
    }

    // MARK: - Unreadable replies are not rejections

    /// A block page and a schema change are two different failures, and
    /// **neither is a wrong password** — so neither may invite the user to try
    /// their credential again.
    @Test("A block page is not a rejection")
    func blockPageIsNotARejection() async throws {
        let sent = transport(signIn: "<html><body>The requested URL was rejected.</body></html>")

        await #expect(throws: APIError.notJSON) {
            try await client(sent).signIn(as: testCredentials)
        }
    }

    @Test("A reply of the wrong shape is a decoding failure, not a rejection")
    func wrongShapeIsNotARejection() async throws {
        let sent = transport(signIn: #"{"headers":{"response_code":"0000"},"body":{"other":1}}"#)

        do {
            _ = try await client(sent).signIn(as: testCredentials)
            Issue.record("expected a failure")
        } catch let error as APIError {
            if case .decoding = error {} else {
                Issue.record("expected .decoding, got \(error)")
            }
        }
    }

    @Test("Not JSON at all is distinct from a block page")
    func notJSONIsDistinctFromBlockPage() async throws {
        let blocked = transport(signIn: "<html><body>rejected</body></html>")
        let garbled = transport(signIn: #"{"headers":{"response_code":"0000"},"body":{"x":1}}"#)

        var blockedError: APIError?
        var garbledError: APIError?

        do { _ = try await client(blocked).signIn(as: testCredentials) } catch let e as APIError {
            blockedError = e
        }
        do { _ = try await client(garbled).signIn(as: testCredentials) } catch let e as APIError {
            garbledError = e
        }

        #expect(blockedError != nil)
        #expect(garbledError != nil)
        #expect(blockedError != garbledError)
    }

    // MARK: - What it sends

    @Test("The sign-in POST carries the session token and the JSON content type")
    func sendsTokenAndContentType() async throws {
        let sent = transport(signIn: signInReply(#"{"success":true,"public_customer_id":4471056}"#))

        _ = try await client(sent).signIn(as: testCredentials)

        let post = try #require(sent.requests.first { SignInTransport.kind(of: $0) == .signIn })

        #expect(post.httpMethod == "POST")
        #expect(post.value(forHTTPHeaderField: "X-CSRF-Token") == firstToken)
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(post.url?.host == "anc.apm.activecommunities.com")
    }

    // MARK: - The shape recorder

    /// **Value-blindness, enforced rather than intended.** Every string in this
    /// payload is a marker; none may appear in what the recorder writes.
    @Test("The shape recorder writes key names and types, never values")
    func recorderWritesNoValues() {
        let payload = """
            {"headers":{"response_code":"MARKER_CODE","response_message":"MARKER_MESSAGE",
            "sessionRefreshedOn":"MARKER_TIMESTAMP"},"body":{"result":{"success":true,
            "message":"MARKER_PROSE","public_customer_id":987654321,
            "access_token":"MARKER_ACCESS","refresh_token":"MARKER_REFRESH",
            "sign_in_token_id":"MARKER_SIGNIN","security_sign_token":"MARKER_SECURITY",
            "customer":{"first_name":"MARKER_FIRST","email":"MARKER_EMAIL"},
            "roles":["MARKER_ROLE_A","MARKER_ROLE_B"]}}}
            """

        let shape = SignInShapeRecorder.shape(of: Data(payload.utf8))

        for marker in [
            "MARKER_CODE", "MARKER_MESSAGE", "MARKER_TIMESTAMP", "MARKER_PROSE", "MARKER_ACCESS",
            "MARKER_REFRESH", "MARKER_SIGNIN", "MARKER_SECURITY", "MARKER_FIRST", "MARKER_EMAIL",
            "MARKER_ROLE_A", "MARKER_ROLE_B", "987654321",
        ] {
            #expect(shape.contains(marker) == false, "\(marker) leaked into the recorded shape")
        }

        // And it still answers the questions it exists to answer.
        #expect(shape.contains("public_customer_id: number"))
        #expect(shape.contains("access_token: string"))
        #expect(shape.contains("success: boolean"))
        #expect(shape.contains("customer: object"))
        #expect(shape.contains("first_name: string"))
    }

    /// A null field is reported as null rather than omitted — "the key was
    /// there and empty" is a different finding from "the key was absent", and
    /// both are things the one real sign-in has to answer.
    @Test("The recorder tells a null field apart from a missing one")
    func recorderReportsNullsDistinctly() {
        let shape = SignInShapeRecorder.shape(
            of: Data(#"{"body":{"result":{"public_customer_id":null,"success":true}}}"#.utf8))

        #expect(shape.contains("public_customer_id: null"))
        #expect(shape.contains("success: boolean"))
    }

    /// A boolean must not be reported as a number, or the recording answers
    /// the wrong question about every string-typed field this API has.
    @Test("The recorder tells booleans from numbers")
    func recorderDistinguishesBooleansFromNumbers() {
        let shape = SignInShapeRecorder.shape(
            of: Data(#"{"flag":true,"count":42,"text":"x","nothing":null}"#.utf8))

        #expect(shape.contains("flag: boolean"))
        #expect(shape.contains("count: number"))
        #expect(shape.contains("text: string"))
        #expect(shape.contains("nothing: null"))
        #expect(shape.contains("42") == false)
    }

    /// A reply that is not JSON is described without being quoted.
    @Test("The recorder does not quote a non-JSON reply")
    func recorderDoesNotQuoteNonJSON() {
        let shape = SignInShapeRecorder.shape(
            of: Data("<html><body>MARKER_BLOCK_PAGE</body></html>".utf8))

        #expect(shape.contains("MARKER_BLOCK_PAGE") == false)
        #expect(shape.contains("not JSON"))
    }
}
