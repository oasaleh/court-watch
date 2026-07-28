//
//  CourtSession.swift
//  CourtWatch
//
//  Owns the CSRF token and the cookie jar it was minted against, as one
//  inseparable unit.
//
//  The API enforces a double-submit pattern: a token is only valid alongside
//  the cookies from the page that issued it. Token A with cookies B is
//  rejected `0012`, indistinguishable at the call site from an ordinary
//  expiry. That makes "never pair a token with a different jar" a rule someone
//  has to remember forever — so instead the token and the transport are
//  replaced together, and violating the rule is not expressible.
//
//  This is an `actor` despite research §1 advising against custom actors. That
//  advice is right about model types and about annotating sequential code; the
//  token/jar pair is the one piece of genuinely shared mutable state in the
//  app, which is the exception §1 itself carves out.
//
//  Nothing here schedules work. No timer, no polling, no proactive refresh.
//  The only path that issues a request is a caller asking for a token.
//

import Foundation

actor CourtSession {

    /// A token and the cookie jar it was minted against, which is the only
    /// unit either of them is meaningful in.
    ///
    /// A type rather than a tuple so that a call site cannot take one half and
    /// pair it with something else — the mistake this represents is exactly
    /// the one being designed out.
    nonisolated struct Pairing: Sendable {
        let token: String
        let transport: any HTTPTransport
    }

    /// Any tenant page carries the token. This one is what the app
    /// conceptually is.
    static let handshakeURL = URL(
        string: "https://anc.apm.activecommunities.com/wcscparksandrec/")!

    private let makeTransport: @Sendable () -> any HTTPTransport

    private var token: String?
    private var transport: any HTTPTransport

    /// The handshake currently in flight, if any.
    ///
    /// This — not the `actor` keyword — is what prevents a double handshake.
    /// Actors are re-entrant: two callers can both suspend inside the network
    /// call and both scrape a token, leaving one of them paired with a jar
    /// that is about to be discarded. Coalescing on a stored task means the
    /// second caller awaits the first one's result.
    private var handshakeInFlight: Task<String, any Error>?

    /// Which jar the session is on, counted up by every invalidation.
    ///
    /// Coalescing stops two callers handshaking at once; it does nothing about
    /// a handshake that is still suspended when the jar it belongs to is
    /// thrown away. That task resumes afterwards holding a token minted
    /// against cookies that no longer exist, and writes it in — pairing a
    /// token with a foreign jar, which is the one thing this file exists to
    /// make impossible. The server answers `0012`, which the retry path cannot
    /// tell from an ordinary expiry, so it re-handshakes against it for as
    /// long as the app runs.
    ///
    /// A counter read before suspending and compared after is enough to answer
    /// "is this result still mine". Cancellation is not: it is cooperative,
    /// and a handshake whose response has already arrived finishes regardless,
    /// because the scrape that follows is synchronous.
    private var generation = 0

    /// Takes a factory rather than a transport, because rotating the token has
    /// to produce a *new* jar. Handing in a single transport would make the
    /// pairing impossible to break correctly.
    init(makeTransport: @escaping @Sendable () -> any HTTPTransport = CourtSession.makeURLSession) {
        self.makeTransport = makeTransport
        self.transport = makeTransport()
    }

    /// An ephemeral session: its cookie storage is private to the session and
    /// held in memory only.
    ///
    /// `HTTPCookieStorage.shared` is process-wide and readable by a future web
    /// view, extension or widget; scoping the jar here keeps the session
    /// cookies reachable only by the client that owns them, and means they die
    /// with the process rather than persisting to disk.
    static func makeURLSession() -> any HTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        configuration.timeoutIntervalForRequest = 20

        // A manual refresh should fail fast and say so, not hang waiting for a
        // network that is not there.
        configuration.waitsForConnectivity = false

        // A cached availability grid is worse than no grid: it shows a court as
        // free that was taken an hour ago.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: configuration)
    }

    /// The current token, performing a handshake only if there is not one.
    func token() async throws -> String {
        if let token {
            return token
        }

        if let handshakeInFlight {
            // Guarded like the path below, and for the same reason. A caller
            // that joins a handshake already running is just as exposed to
            // that handshake's jar being retired while it waits.
            let mine = generation
            let joined = try await handshakeInFlight.value

            guard generation == mine else {
                throw APIError.transport(.cancelled)
            }

            return joined
        }

        let task = Task { [transport] in
            try await Self.handshake(using: transport)
        }
        handshakeInFlight = task

        // Read before suspending, compared after. Everything below happens on
        // the far side of an await, by which time `invalidate` may have run.
        let mine = generation

        do {
            let scraped = try await task.value

            // A result from a retired jar is dropped rather than installed,
            // and it must not touch the shared state either: clearing the
            // handle here would throw away the handshake that replaced it and
            // let a later caller start a third.
            guard generation == mine else {
                throw APIError.transport(.cancelled)
            }

            // Clear the handle before returning so the next miss starts a fresh
            // handshake rather than awaiting a completed task.
            handshakeInFlight = nil
            token = scraped
            return scraped
        } catch {
            // Clearing on the failure path too. Leaving a failed task in place
            // would poison the session for the lifetime of the process: every
            // later caller would await it and receive the same old error.
            //
            // Guarded by the same generation check, and for the same reason: a
            // failure belonging to a retired jar has no business clearing the
            // handle of the handshake that superseded it.
            if generation == mine {
                handshakeInFlight = nil
            }

            throw error
        }
    }

    /// Discards the token and the jar it belongs to, together.
    ///
    /// The new transport carries no cookies from the old one, which is the
    /// whole point: a rotated token is never sent alongside the session that
    /// preceded it.
    func invalidate() {
        token = nil
        handshakeInFlight?.cancel()
        handshakeInFlight = nil

        // Anything already suspended in `token()` belongs to the jar being
        // retired here, and will find its generation stale when it resumes.
        generation &+= 1

        let outgoing = transport
        transport = makeTransport()

        // Release the old session's resources rather than leaking it. Tasks
        // already in flight on it are allowed to finish.
        (outgoing as? URLSession)?.finishTasksAndInvalidate()
    }

    /// The transport the current token belongs to.
    ///
    /// Deliberately not paired with `token()` at the call sites any more.
    /// Asking for the two separately means two awaits, and an `invalidate` in
    /// the gap between them sends the token from one jar with the cookies of
    /// the next — the pairing this file says is not expressible. Use
    /// ``pairing()``; this remains for callers that need only the jar.
    func currentTransport() -> any HTTPTransport {
        transport
    }

    /// A token and the jar it belongs to, obtained as one step.
    ///
    /// The invariant this whole file is built around is that the two travel
    /// together, and the only way to keep it is to hand them over together.
    /// Two calls cannot do it however carefully they are written, because the
    /// actor is free to run anything else in the gap.
    ///
    /// The generation is checked across the suspension for the same reason
    /// `token()` checks it: a jar retired while this was waiting makes both
    /// halves stale, and returning them would be the mismatch under a
    /// different name.
    func pairing() async throws -> Pairing {
        let mine = generation
        let scraped = try await token()

        guard generation == mine else {
            throw APIError.transport(.cancelled)
        }

        return Pairing(token: scraped, transport: transport)
    }

    /// Rotates the pairing and mints a fresh one, as a single step.
    ///
    /// For a caller that has just been told its handshake is stale, "discard
    /// and get another" is one operation, not two — and spelling it as two
    /// leaves a suspension point in the middle where another caller can
    /// interleave and be handed the token that is about to be thrown away.
    ///
    /// It exists so a caller can obtain a renewed pairing **without being
    /// handed the ability to discard the session as a side effect**. That
    /// distinction is load-bearing for the session check next door: it must be
    /// able to replay a genuinely stale handshake, and it must never be able
    /// to throw a healthy jar away, because on that endpoint the commonest
    /// answer of all looks exactly like an expiry.
    func renewedToken() async throws -> String {
        invalidate()
        return try await token()
    }

    /// The same rotation, returning the jar alongside the token.
    func renewedPairing() async throws -> Pairing {
        invalidate()
        return try await pairing()
    }

    private static func handshake(using transport: any HTTPTransport) async throws -> String {
        var request = URLRequest(url: handshakeURL)
        request.httpMethod = "GET"

        // An honest identifier. The API was measured not to sniff the
        // user agent, so there is nothing to gain by impersonating a browser
        // against a system that belongs to someone else.
        request.setValue("court-watch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await transport.send(request)

        // Even the tenant's not-found page carries the token, so the body is
        // not judged by its status or its apparent content — only a missing
        // token assignment is fatal.
        //
        // The declared encoding is not guaranteed, so fall back rather than
        // throwing: ISO-Latin-1 cannot fail, and the token is ASCII either way.
        let html =
            String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        return try scrapeToken(from: html)
    }

    /// Matches `window.__csrfToken = "<uuid>"` with either quote style and
    /// flexible whitespace around the assignment.
    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"window\.__csrfToken\s*=\s*["']([0-9a-fA-F-]{36})["']"#)

    static func scrapeToken(from html: String) throws -> String {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        guard
            let match = tokenPattern.firstMatch(in: html, range: range),
            let captured = Range(match.range(at: 1), in: html)
        else {
            throw APIError.decoding(
                "No window.__csrfToken assignment found in the handshake page")
        }

        let token = String(html[captured])

        // Validate before accepting. An unvalidated scrape can pick up a
        // truncated or malformed value, which the server then rejects as
        // `0012` — indistinguishable from a genuine expiry, so the retry loop
        // would chase a scrape bug it can never fix.
        guard isWellFormedToken(token) else {
            throw APIError.decoding("Scraped CSRF token was not UUID-shaped")
        }

        return token
    }

    private static func isWellFormedToken(_ token: String) -> Bool {
        token.count == 36
            && token.allSatisfy { $0.isHexDigit || $0 == "-" }
            && token.contains("-")
    }
}
