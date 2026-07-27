//
//  SessionProbeTests.swift
//  CourtWatchTests
//
//  **The assertion that carries this file is a count, not a state.**
//
//  The bug it exists to prevent is invisible from the outside: a probe that
//  reads the anonymous answer as an expiry still *reports* anonymous, quite
//  correctly, having thrown away a healthy session and re-handshaked to do it.
//  Every state assertion passes. What changes is the traffic — one extra GET
//  against someone else's WAF-fronted host every single time the app asks
//  itself a question it asks constantly.
//
//  So ten consecutive anonymous probes are required to produce exactly **one**
//  handshake between them, and the handshakes are counted by URL rather than
//  inferred. Its control sits beside it: a genuinely stale code that is not the
//  anonymous one must still re-handshake once and replay once, so the exclusion
//  is proven to be one code wide rather than a blanket opt-out.
//
//  Nothing here reaches a network, and nothing here has a password to send —
//  which is the property that makes this endpoint safe to hammer in a way the
//  sign-in endpoint never will be.
//

import Foundation
import Testing

@testable import CourtWatch

private nonisolated let firstToken = "370060c8-52de-4fc9-a95c-b5cfff762b53"
private nonisolated let refreshedToken = "a1b2c3d4-1111-2222-3333-444455556666"

private nonisolated func handshakePage(token: String) -> String {
    "<script>window.__csrfToken = \"\(token)\";</script>"
}

/// The signed-in capture, as recorded from the browser.
private nonisolated let signedInReply = """
    {"headers":{"sessionRefreshedOn":"2026-07-27 10:13:17","sessionExtendedCount":1,
    "response_code":"0000","response_message":"Successful"},"body":{"result":"successful"}}
    """

/// The anonymous capture, as recorded during research.
private nonisolated let anonymousReply = """
    {"headers":{"sessionRefreshedOn":null,"sessionExtendedCount":0,
    "response_code":"0021","response_message":"User not login"},"body":{}}
    """

private nonisolated func envelope(code: String, message: String) -> String {
    """
    {"headers":{"sessionRefreshedOn":null,"response_code":"\(code)",
    "response_message":"\(message)"},"body":{}}
    """
}

/// Records every request so handshakes can be counted by URL rather than
/// guessed at from a total. Reaches no network: there is no `URLSession` here.
private nonisolated final class RecordingTransport: HTTPTransport, @unchecked Sendable {

    private let lock = NSLock()
    private let respond: @Sendable (URLRequest, Int) -> Result<Data, any Error>
    private var recorded: [URLRequest] = []
    private var probesAnswered = 0

    init(respond: @escaping @Sendable (URLRequest, Int) -> Result<Data, any Error>) {
        self.respond = respond
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    /// A probe is the GET at the session-check path; a handshake is the only
    /// other request this file can produce. Counted as the complement rather
    /// than by matching the tenant root, because `URL.path` normalises a
    /// trailing slash and a suffix match on it silently counts zero.
    var handshakeCount: Int {
        lock.withLock { recorded.count } - probeCount
    }

    var probeCount: Int {
        lock.withLock {
            recorded.filter { ($0.url?.absoluteString ?? "").contains("logincheck") }.count
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result: Result<Data, any Error> = lock.withLock {
            recorded.append(request)

            let isProbe = (request.url?.absoluteString ?? "").contains("logincheck")
            let answer = respond(request, isProbe ? probesAnswered : -1)

            if isProbe { probesAnswered += 1 }

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

/// Answers every handshake, and every probe with the same reply.
private nonisolated func alwaysAnswering(_ reply: String) -> RecordingTransport {
    RecordingTransport { request, _ in
        (request.url?.absoluteString ?? "").contains("logincheck")
            ? .success(Data(reply.utf8))
            : .success(Data(handshakePage(token: firstToken).utf8))
    }
}

struct SessionProbeTests {

    // MARK: - The two measured answers

    @Test("The signed-in envelope reports authenticated")
    func signedInReplyIsAuthenticated() async throws {
        let transport = alwaysAnswering(signedInReply)
        let probe = SessionProbe(session: CourtSession { transport })

        #expect(await probe.check() == .authenticated)
    }

    @Test("The anonymous envelope reports anonymous")
    func anonymousReplyIsAnonymous() async throws {
        let transport = alwaysAnswering(anonymousReply)
        let probe = SessionProbe(session: CourtSession { transport })

        #expect(await probe.check() == .anonymous)
    }

    /// The anonymous answer is an ordinary answer. One probe, one handshake,
    /// nothing replayed.
    @Test("The anonymous answer costs one request and no replay")
    func anonymousAnswerIsNotRetried() async throws {
        let transport = alwaysAnswering(anonymousReply)
        let probe = SessionProbe(session: CourtSession { transport })

        _ = await probe.check()

        #expect(transport.handshakeCount == 1)
        #expect(transport.probeCount == 1)
    }

    // MARK: - The assertion that carries this file

    /// **Ten anonymous probes, one handshake.**
    ///
    /// Counted rather than inferred. A probe that treated the anonymous code
    /// as an expiry would report `.anonymous` every time — correctly — while
    /// discarding the session and re-handshaking on each call. Only the count
    /// can see it.
    @Test("Ten consecutive anonymous probes perform exactly one handshake")
    func repeatedAnonymousProbesDoNotReHandshake() async throws {
        let transport = alwaysAnswering(anonymousReply)
        let probe = SessionProbe(session: CourtSession { transport })

        for _ in 1...10 {
            #expect(await probe.check() == .anonymous)
        }

        #expect(transport.probeCount == 10)
        #expect(transport.handshakeCount == 1, "the anonymous answer re-handshaked")
    }

    /// The same guarantee for a jar that *is* signed in: asking repeatedly
    /// must not cost anything either.
    @Test("Ten consecutive signed-in probes perform exactly one handshake")
    func repeatedAuthenticatedProbesDoNotReHandshake() async throws {
        let transport = alwaysAnswering(signedInReply)
        let probe = SessionProbe(session: CourtSession { transport })

        for _ in 1...10 {
            #expect(await probe.check() == .authenticated)
        }

        #expect(transport.probeCount == 10)
        #expect(transport.handshakeCount == 1)
    }

    // MARK: - The control: the exclusion is one code wide

    /// A genuinely stale code still re-handshakes once and replays once,
    /// exactly as everywhere else — so the carve-out is proven narrow rather
    /// than a blanket opt-out.
    @Test(
        "A genuine stale code still re-handshakes once and replays once",
        arguments: ["0002", "0007", "0010", "0012"]
    )
    func staleCodeReplaysOnce(code: String) async throws {
        let transport = RecordingTransport { request, probesAnswered in
            guard (request.url?.absoluteString ?? "").contains("logincheck") else {
                return .success(
                    Data(
                        handshakePage(token: probesAnswered == -1 ? firstToken : firstToken).utf8))
            }

            return probesAnswered == 0
                ? .success(Data(envelope(code: code, message: "stale").utf8))
                : .success(Data(signedInReply.utf8))
        }
        let probe = SessionProbe(session: CourtSession { transport })

        #expect(await probe.check() == .authenticated)

        // Two handshakes and two probes: the original pairing, the stale
        // answer, a renewed pairing, and the replay.
        #expect(transport.handshakeCount == 2)
        #expect(transport.probeCount == 2)
    }

    /// And it is terminal after that one replay.
    @Test("A stale code twice gives up rather than looping")
    func staleCodeTwiceStops() async throws {
        let transport = alwaysAnswering(envelope(code: "0012", message: "Invalid CSRF token"))
        let probe = SessionProbe(session: CourtSession { transport })

        #expect(await probe.check() == .unreadable(.sessionExpired(code: "0012")))

        #expect(transport.probeCount == 2)
        #expect(transport.handshakeCount == 2)
    }

    /// The shared expiry set still contains the anonymous code, because on the
    /// availability endpoint that classification is correct and tested. The
    /// difference is which endpoint is being asked, not which code arrived.
    @Test("The availability expiry set is untouched by this file's exception")
    func availabilityExpirySetIsUnchanged() {
        #expect(ResponseCode.expiry.contains(SessionProbe.anonymousCode))
        #expect(ResponseCode.expiry == ["0002", "0007", "0010", "0012", "0021"])
        #expect(SessionProbe.staleCodes == ["0002", "0007", "0010", "0012"])
        #expect(SessionProbe.staleCodes.contains(SessionProbe.anonymousCode) == false)
    }

    // MARK: - Unreadable is not anonymous

    /// A dead network has not established that anybody is signed out.
    @Test("A transport failure is unreadable, not anonymous")
    func transportFailureIsUnreadable() async throws {
        let transport = RecordingTransport { _, _ in
            .failure(APIError.transport(.notConnectedToInternet))
        }
        let probe = SessionProbe(session: CourtSession { transport })

        let outcome = await probe.check()

        #expect(outcome == .unreadable(.transport(.notConnectedToInternet)))
        #expect(outcome != .anonymous)
        #expect(outcome != .authenticated)
    }

    @Test("A block page is unreadable, and distinct from a schema change")
    func blockPageIsUnreadable() async throws {
        let transport = alwaysAnswering(
            "<html><body>The requested URL was rejected.</body></html>")
        let probe = SessionProbe(session: CourtSession { transport })

        let outcome = await probe.check()

        #expect(outcome == .unreadable(.notJSON))
        #expect(outcome != .anonymous)
    }

    @Test("A reply of the wrong shape is unreadable, and is not a block page")
    func wrongShapeIsUnreadable() async throws {
        let transport = alwaysAnswering(#"{"unexpected": true}"#)
        let probe = SessionProbe(session: CourtSession { transport })

        let outcome = await probe.check()

        guard case .unreadable(let error) = outcome else {
            Issue.record("expected unreadable, got \(outcome)")
            return
        }

        if case .decoding = error {} else {
            Issue.record("expected a decoding failure, got \(error)")
        }

        #expect(outcome != .unreadable(.notJSON))
        #expect(outcome != .anonymous)
    }

    /// A service code that is neither success, nor the anonymous answer, nor a
    /// stale handshake is its own kind of unreadable — and still not anonymous.
    @Test("An unrecognised service code is unreadable rather than anonymous")
    func serviceCodeIsUnreadable() async throws {
        let transport = alwaysAnswering(envelope(code: "1507", message: "Invalid request"))
        let probe = SessionProbe(session: CourtSession { transport })

        let outcome = await probe.check()

        #expect(outcome == .unreadable(.service(code: "1507", message: "Invalid request")))
        #expect(outcome != .anonymous)
        #expect(transport.probeCount == 1, "an unrecognised code must not be replayed")
    }

    // MARK: - What it sends

    /// The token travels with the jar that minted it, and the request is a GET
    /// with no body at all — there is nothing to put in one.
    @Test("The probe is a bodyless GET carrying the session's token")
    func sendsTokenAndNoBody() async throws {
        let transport = alwaysAnswering(anonymousReply)
        let probe = SessionProbe(session: CourtSession { transport })

        _ = await probe.check()

        let sent = try #require(
            transport.requests.first { ($0.url?.absoluteString ?? "").contains("logincheck") })

        #expect(sent.httpMethod == "GET")
        #expect(sent.httpBody == nil)
        #expect(sent.value(forHTTPHeaderField: "X-CSRF-Token") == firstToken)
        #expect(sent.url?.host == "anc.apm.activecommunities.com")
    }

    /// The cache-buster differs between calls, as the web UI's does.
    @Test("Each probe carries its own cache-busting value")
    func eachProbeIsItsOwnRequest() async throws {
        let transport = alwaysAnswering(anonymousReply)
        let probe = SessionProbe(session: CourtSession { transport })

        for _ in 1...8 { _ = await probe.check() }

        let urls = Set(
            transport.requests
                .filter { ($0.url?.absoluteString ?? "").contains("logincheck") }
                .compactMap { $0.url?.absoluteString })

        #expect(urls.count > 1, "every probe sent an identical URL")
    }

    /// The replay after a stale code carries the renewed token, not the one
    /// the server just rejected. A count-only assertion passes a client that
    /// re-handshakes and then re-sends the stale value.
    @Test("The replay carries the renewed token")
    func replayCarriesTheRenewedToken() async throws {
        let transport = RecordingTransport { request, probesAnswered in
            guard (request.url?.absoluteString ?? "").contains("logincheck") else {
                return .success(Data(handshakePage(token: refreshedToken).utf8))
            }

            return probesAnswered == 0
                ? .success(Data(envelope(code: "0012", message: "stale").utf8))
                : .success(Data(signedInReply.utf8))
        }

        // The first handshake answers the original token; every later one
        // answers the refreshed value.
        let session = CourtSession { transport }
        let probe = SessionProbe(session: session)

        #expect(await probe.check() == .authenticated)

        let probes = transport.requests.filter { ($0.url?.absoluteString ?? "").contains("logincheck") }

        #expect(probes.count == 2)
        #expect(probes.last?.value(forHTTPHeaderField: "X-CSRF-Token") == refreshedToken)
    }
}
