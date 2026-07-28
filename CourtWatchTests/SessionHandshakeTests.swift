//
//  SessionHandshakeTests.swift
//  CourtWatchTests
//
//  The session's job is to keep a CSRF token and the cookie jar it was minted
//  against inseparable, and to issue no request nobody asked for.
//
//  The assertions here are mostly counts of recorded requests, because that is
//  what makes "reuses the cached token", "coalesces two concurrent callers"
//  and "issues nothing on its own" observable rather than a matter of reading
//  the implementation and believing it.
//

import Foundation
import Testing

@testable import CourtWatch

private let validToken = "370060c8-52de-4fc9-a95c-b5cfff762b53"
private let secondToken = "a1b2c3d4-1111-2222-3333-444455556666"

private func page(token: String, quote: String = "\"", spacing: String = " = ") -> String {
    """
    <html><head><script>
      window.__csrfToken\(spacing)\(quote)\(token)\(quote);
      window.__siteBaseName = "/wcscparksandrec";
    </script></head><body>The Woodlands Township</body></html>
    """
}

/// Records every request and answers from a queued script.
///
/// A `final class` behind a lock rather than an actor: the point is to observe
/// what a *concurrent* caller did, so the recorder must not serialize its
/// callers into a queue that hides the interleaving under test.
private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<String, any Error>]
    private var recorded: [URLRequest] = []

    /// Lets a test hold the first response open long enough for a second
    /// caller to arrive while the first is still suspended — which is the
    /// window a re-entrant actor leaves open.
    private let gate: (@Sendable () async -> Void)?

    init(
        responses: [Result<String, any Error>],
        gate: (@Sendable () async -> Void)? = nil
    ) {
        self.responses = responses
        self.gate = gate
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    var requestCount: Int {
        lock.withLock { recorded.count }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: Result<String, any Error> = lock.withLock {
            recorded.append(request)
            return responses.isEmpty ? .success("") : responses.removeFirst()
        }

        if let gate {
            await gate()
        }

        let body = try next.get()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        return (Data(body.utf8), response)
    }
}

struct SessionHandshakeTests {

    @Test("A handshake scrapes the token from the page")
    func scrapesToken() async throws {
        let transport = RecordingTransport(responses: [.success(page(token: validToken))])
        let session = CourtSession { transport }

        #expect(try await session.token() == validToken)
        #expect(transport.requestCount == 1)
    }

    @Test(
        "Quote style and whitespace around the assignment do not matter",
        arguments: [
            ("'", " = "),
            ("\"", "="),
            ("\"", "   =   "),
            ("'", "\t=\t"),
        ]
    )
    func scrapesAcrossFormatting(quote: String, spacing: String) throws {
        let html = page(token: validToken, quote: quote, spacing: spacing)

        #expect(try CourtSession.scrapeToken(from: html) == validToken)
    }

    @Test("A page with no token assignment is a decoding failure")
    func rejectsPageWithoutToken() {
        let html = "<html><body>Access Denied</body></html>"

        #expect(throws: APIError.self) {
            try CourtSession.scrapeToken(from: html)
        }
    }

    /// A truncated or malformed scrape must be caught here. Sent to the server
    /// it comes back as `0012`, which the retry path cannot tell apart from a
    /// genuine expiry — so it would re-handshake forever against a bug in the
    /// scrape.
    ///
    /// The last candidate is the one that earns the shape check its keep.
    /// The pattern already demands thirty-six characters of hex-or-dash, so
    /// everything above it is refused by the pattern and never reaches
    /// `isWellFormedToken` at all; the only thing that check adds is the
    /// requirement that a dash be present somewhere. Without a candidate that
    /// satisfies the pattern and fails that, the whole guard could be deleted
    /// with the suite still green — which is what was happening.
    @Test(
        "A token that is not UUID-shaped is rejected rather than sent",
        arguments: [
            "370060c8",
            "370060c852de4fc9a95cb5cfff762b53",
            "zzzzzzzz-52de-4fc9-a95c-b5cfff762b53",
            "",
            "370060c852de4fc9a95cb5cfff762b53abcd",
        ]
    )
    func rejectsMalformedToken(candidate: String) {
        let html = """
            <script>window.__csrfToken = "\(candidate)";</script>
            """

        #expect(throws: APIError.self) {
            try CourtSession.scrapeToken(from: html)
        }
    }

    /// The shape check on its own, stated so it cannot quietly stop being
    /// reached again.
    ///
    /// Thirty-six hex characters with no dash is a real failure mode rather
    /// than a contrivance: it is what a scrape returns if the page ever ships
    /// the token unhyphenated, and it is the one malformed shape the pattern
    /// happily hands through.
    @Test("Thirty-six hex characters with no dash is not a token")
    func rejectsUnhyphenatedToken() throws {
        let html = """
            <script>window.__csrfToken = "370060c852de4fc9a95cb5cfff762b53abcd";</script>
            """

        #expect(throws: APIError.self) {
            try CourtSession.scrapeToken(from: html)
        }

        // And the control: the same value with dashes in the usual places is
        // accepted, so the test above is failing for the shape and not because
        // every long string is refused.
        let valid = """
            <script>window.__csrfToken = "370060c8-52de-4fc9-a95c-b5cfff762b53";</script>
            """

        #expect(try CourtSession.scrapeToken(from: valid) == "370060c8-52de-4fc9-a95c-b5cfff762b53")
    }

    @Test("A second call reuses the cached token without a new request")
    func cachesToken() async throws {
        let transport = RecordingTransport(responses: [
            .success(page(token: validToken)),
            .success(page(token: secondToken)),
        ])
        let session = CourtSession { transport }

        let first = try await session.token()
        let second = try await session.token()

        #expect(first == validToken)
        #expect(second == validToken)
        #expect(transport.requestCount == 1)
    }

    /// The phase's most likely correctness bug.
    ///
    /// An `actor` does not prevent this: actors are re-entrant, so two callers
    /// can both find no cached token, both suspend inside the network call, and
    /// both scrape. One of them then holds a token paired with a jar that is
    /// about to be replaced. The gate below holds the first response open until
    /// a second caller has definitely arrived, which is precisely the window
    /// that a naive implementation leaves open — without it this test passes
    /// against the bug.
    @Test("Two concurrent first calls make exactly one request")
    func coalescesConcurrentHandshakes() async throws {
        let bothArrived = Gate()
        let transport = RecordingTransport(
            responses: [
                .success(page(token: validToken)),
                .success(page(token: secondToken)),
            ],
            gate: { await bothArrived.wait() }
        )
        let session = CourtSession { transport }

        async let first = session.token()
        async let second = session.token()

        // Let both callers reach the session and get as far as they can before
        // any response is delivered.
        try await Task.sleep(for: .milliseconds(50))
        await bothArrived.open()

        let tokens = try await [first, second]

        #expect(transport.requestCount == 1)
        #expect(tokens == [validToken, validToken])
    }

    /// The same window as the test above, but with an invalidation inside it
    /// rather than a second caller.
    ///
    /// A handshake that was in flight when the session was invalidated belongs
    /// to a jar that no longer exists. Its result must be discarded, because
    /// installing it pairs a token with the cookies of a different session —
    /// which the server refuses as `0012`, indistinguishable at the call site
    /// from an ordinary expiry, so the retry path re-handshakes against it
    /// forever. This file's own preamble says that pairing is "not
    /// expressible"; an actor being re-entrant is how it was expressible.
    @Test("A handshake that outlives its invalidation does not install a token")
    func lateHandshakeDoesNotInstallAStaleToken() async throws {
        let released = Gate()
        let transport = RecordingTransport(
            responses: [
                .success(page(token: validToken)),
                .success(page(token: secondToken)),
            ],
            gate: { await released.wait() }
        )
        let session = CourtSession { transport }

        // In flight, and held at the response.
        async let inFlight: String? = try? await session.token()
        try await Task.sleep(for: .milliseconds(50))

        // The jar this handshake belongs to is discarded while it is suspended.
        await session.invalidate()

        // Only now does the first response arrive, into a session that has
        // moved on.
        await released.open()
        _ = await inFlight

        // The token from the discarded jar must not be the session's token.
        // Asking for one has to produce a fresh handshake rather than handing
        // back something minted against a jar that is gone.
        let current = try await session.token()

        #expect(current == secondToken, "the token from the retired jar was installed")
        #expect(transport.requestCount == 2)
    }

    @Test("Invalidating discards the token and fetches a new one")
    func invalidateForcesNewHandshake() async throws {
        let transport = RecordingTransport(responses: [
            .success(page(token: validToken)),
            .success(page(token: secondToken)),
        ])
        let session = CourtSession { transport }

        #expect(try await session.token() == validToken)
        await session.invalidate()
        #expect(try await session.token() == secondToken)
        #expect(transport.requestCount == 2)
    }

    /// SESS-03 made structural. The token and the jar are replaced in one act,
    /// so cookies from the previous session cannot accompany the new token.
    @Test("Invalidating replaces the transport, not just the token")
    func invalidateReplacesTransport() async throws {
        let first = RecordingTransport(responses: [.success(page(token: validToken))])
        let second = RecordingTransport(responses: [.success(page(token: secondToken))])

        let transports = TransportQueue([first, second])
        let session = CourtSession { transports.next() }

        _ = try await session.token()
        let before = await session.currentTransport()

        await session.invalidate()

        _ = try await session.token()
        let after = await session.currentTransport()

        #expect(before as AnyObject === first)
        #expect(after as AnyObject === second)
        #expect(first.requestCount == 1)
        #expect(second.requestCount == 1)
    }

    /// A transport failure must not leave the in-flight handle set, or the
    /// first network blip poisons the session for the lifetime of the process
    /// and every later caller replays the same stale error.
    @Test("A failed handshake does not poison later attempts")
    func failureDoesNotPoisonSession() async throws {
        let transport = RecordingTransport(responses: [
            .failure(APIError.transport(.notConnectedToInternet)),
            .success(page(token: validToken)),
        ])
        let session = CourtSession { transport }

        await #expect(throws: APIError.self) {
            try await session.token()
        }

        #expect(try await session.token() == validToken)
        #expect(transport.requestCount == 2)
    }

    /// SESS-06. Constructing a session, and invalidating one, are not reasons
    /// to talk to a public system.
    @Test("The session issues no request until a caller asks for a token")
    func issuesNoUnrequestedRequest() async throws {
        let transport = RecordingTransport(responses: [.success(page(token: validToken))])
        let session = CourtSession { transport }

        try await Task.sleep(for: .milliseconds(50))
        #expect(transport.requestCount == 0)

        await session.invalidate()
        try await Task.sleep(for: .milliseconds(50))
        #expect(transport.requestCount == 0)

        _ = try await session.token()
        #expect(transport.requestCount == 1)
    }

    @Test("The handshake targets the tenant page over HTTPS")
    func handshakeTargetsTenantPage() async throws {
        let transport = RecordingTransport(responses: [.success(page(token: validToken))])
        let session = CourtSession { transport }

        _ = try await session.token()

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "anc.apm.activecommunities.com")
    }
}

/// A one-shot gate. Callers wait until it is opened.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        let resuming = waiting
        waiting = []
        for continuation in resuming { continuation.resume() }
    }
}

/// Hands out a prepared sequence of transports, so a test can tell which one a
/// request went through.
///
/// `nonisolated` because the session's transport factory is a nonisolated
/// `@Sendable` closure; without it this type picks up the module's main-actor
/// default and cannot be called from there.
private nonisolated final class TransportQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [any HTTPTransport]

    init(_ transports: [any HTTPTransport]) {
        self.transports = transports
    }

    func next() -> any HTTPTransport {
        lock.withLock {
            transports.isEmpty ? RecordingTransport(responses: []) : transports.removeFirst()
        }
    }
}
