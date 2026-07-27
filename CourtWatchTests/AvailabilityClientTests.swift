//
//  AvailabilityClientTests.swift
//  CourtWatchTests
//
//  Everything runs through a scripted transport that answers from a queue and
//  records every request, so "exactly one re-handshake" and "exactly two
//  attempts" are assertions about recorded counts rather than about timing.
//
//  The retry assertions check the *token carried by the replay*, not just the
//  number of requests. A client that re-handshakes and then re-sends the stale
//  token passes a count-only test while being completely broken, and that is
//  the bug worth catching here.
//

import Foundation
import Testing

@testable import CourtWatch

private let firstToken = "370060c8-52de-4fc9-a95c-b5cfff762b53"
private let refreshedToken = "a1b2c3d4-1111-2222-3333-444455556666"

private func handshakePage(token: String) -> String {
    "<script>window.__csrfToken = \"\(token)\";</script>"
}

private func envelope(code: String, message: String = "") -> String {
    """
    {"headers":{"response_code":"\(code)","response_message":"\(message)",
    "sessionRefreshedOn":null},"body":{"availability":{"time_slots":[],
    "resources":[],"time_increment":60}}}
    """
}

/// Answers a queued script and records every request it was given.
private nonisolated final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<Data, any Error>]
    private var recorded: [URLRequest] = []

    init(script: [Result<Data, any Error>]) {
        self.script = script
    }

    convenience init(bodies: [String]) {
        self.init(script: bodies.map { .success(Data($0.utf8)) })
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    var requestCount: Int {
        lock.withLock { recorded.count }
    }

    /// The requests that carried a body — the availability POSTs, as distinct
    /// from the handshake GETs.
    var posts: [URLRequest] {
        lock.withLock { recorded.filter { $0.httpMethod == "POST" } }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: Result<Data, any Error> = lock.withLock {
            recorded.append(request)
            return script.isEmpty ? .success(Data()) : script.removeFirst()
        }

        let body = try next.get()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        return (body, response)
    }
}

private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody, "request carried no body")
    let object = try JSONSerialization.jsonObject(with: body)
    return try #require(object as? [String: Any], "body was not a JSON object")
}

private func fixtureBody(_ name: String) throws -> String {
    String(decoding: try Fixture.data(name), as: UTF8.self)
}

/// A fixed Central day, so the encoded reserve_date is a stable expectation
/// rather than whatever today happens to be.
private func testDay() throws -> Date {
    try #require(
        CourtTime.calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
}

struct AvailabilityClientTests {

    @Test("The request body carries the anonymous-path fields")
    func encodesRequestBody() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        _ = try await client.fetch(on: try testDay())

        let body = try decodedBody(try #require(transport.posts.first))

        #expect(body["facility_group_id"] as? Int == 20)
        #expect(body["customer_id"] as? Int == 0)
        #expect(body["company_id"] as? Int == 0)
        #expect(body["resident"] as? Bool == false)
        #expect(body["reload"] as? Bool == false)
        #expect(body["reserve_date"] as? String == "2026-07-26")
    }

    /// Both keys must be present and null, matching the payload measured
    /// against the live endpoint, rather than omitted as Swift would by
    /// default.
    @Test("With no window both times encode as explicit nulls")
    func encodesNullWindow() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        _ = try await client.fetch(on: try testDay())

        let body = try decodedBody(try #require(transport.posts.first))

        #expect(body["change_time_range"] as? Bool == false)
        #expect(body.keys.contains("start_time"))
        #expect(body.keys.contains("end_time"))
        #expect(body["start_time"] is NSNull)
        #expect(body["end_time"] is NSNull)
    }

    @Test("A window sends HH:mm:ss bounds and flips the range flag")
    func encodesWindow() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        let window = AvailabilityClient.SlotWindow(
            start: try #require(SlotTime(apiString: "14:00:00")),
            end: try #require(SlotTime(apiString: "22:00:00"))
        )

        _ = try await client.fetch(on: try testDay(), window: window)

        let body = try decodedBody(try #require(transport.posts.first))

        #expect(body["start_time"] as? String == "14:00:00")
        #expect(body["end_time"] as? String == "22:00:00")
        #expect(body["change_time_range"] as? Bool == true)
    }

    @Test("The request carries the session's token and content type")
    func sendsTokenHeader() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        _ = try await client.fetch(on: try testDay())

        let post = try #require(transport.posts.first)

        #expect(post.value(forHTTPHeaderField: "X-CSRF-Token") == firstToken)
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(post.url?.host == "anc.apm.activecommunities.com")
    }

    /// The token is only valid alongside the cookies from the page that minted
    /// it, so the POST must go through the same transport as the handshake.
    @Test("The POST goes through the transport that produced the token")
    func usesTheSessionTransport() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        _ = try await client.fetch(on: try testDay())

        #expect(transport.requestCount == 2)
        #expect(transport.requests.first?.httpMethod == "GET")
        #expect(transport.requests.last?.httpMethod == "POST")
    }

    @Test("A successful response decodes to the full grouped availability")
    func decodesSuccess() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        let availability = try await client.fetch(on: try testDay())

        #expect(availability.courts.count == 80)
        #expect(availability.facilities.count == 27)
        #expect(availability.slotTimes.count == 16)
    }

    @Test("A successful fetch issues no further requests")
    func stopsAfterSuccess() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        _ = try await client.fetch(on: try testDay())
        try await Task.sleep(for: .milliseconds(50))

        #expect(transport.requestCount == 2)
    }

    /// Every documented expiry code takes the retry path: one re-handshake,
    /// one replay, and the replay carries the refreshed token. Asserting the
    /// token is the point — a client that re-handshakes and re-sends the stale
    /// token passes a count-only test and fails against the real server.
    @Test(
        "Each expiry code triggers exactly one re-handshake and one retry",
        arguments: ["0002", "0007", "0010", "0012", "0021"]
    )
    func retriesOnceOnExpiry(code: String) async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            envelope(code: code, message: "expired"),
            handshakePage(token: refreshedToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        let availability = try await client.fetch(on: try testDay())

        #expect(availability.courts.count == 80)

        // Two handshakes, two POSTs — not one more of either.
        #expect(transport.requestCount == 4)
        #expect(transport.posts.count == 2)

        let tokens = transport.posts.map { $0.value(forHTTPHeaderField: "X-CSRF-Token") }
        #expect(tokens == [firstToken, refreshedToken])
    }

    /// Terminal after two attempts. Without this guard the client loops
    /// against a WAF-fronted public system, which is how an IP gets blocked.
    @Test("Two consecutive expiry codes stop after two attempts")
    func stopsAfterSecondExpiry() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            envelope(code: "0012", message: "Invalid CSRF token"),
            handshakePage(token: refreshedToken),
            envelope(code: "0012", message: "Invalid CSRF token"),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.sessionExpired(code: "0012")) {
            try await client.fetch(on: try testDay())
        }

        #expect(transport.posts.count == 2)
        #expect(transport.requestCount == 4)
    }

    /// 1507 means the request was wrong, not the session. Re-handshaking would
    /// repeat the same rejection.
    @Test("A service error throws without re-handshaking")
    func doesNotRetryServiceError() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            envelope(code: "1507", message: "Invalid request"),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.service(code: "1507", message: "Invalid request")) {
            try await client.fetch(on: try testDay())
        }

        #expect(transport.posts.count == 1)
        #expect(transport.requestCount == 2)
    }

    @Test("A transport failure throws without re-handshaking")
    func doesNotRetryTransportFailure() async throws {
        let transport = ScriptedTransport(script: [
            .success(Data(handshakePage(token: firstToken).utf8)),
            .failure(APIError.transport(.timedOut)),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.transport(.timedOut)) {
            try await client.fetch(on: try testDay())
        }

        #expect(transport.posts.count == 1)
        #expect(transport.requestCount == 2)
    }

    @Test("A malformed response is a decoding failure and is not retried")
    func doesNotRetryDecodingFailure() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            "{not json",
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.self) {
            try await client.fetch(on: try testDay())
        }

        #expect(transport.posts.count == 1)
    }

    /// A 0000 with nothing to show is not a success worth returning — it would
    /// render as an empty grid indistinguishable from "everything is booked".
    @Test("A success with no slot times is an error, not an empty grid")
    func rejectsEmptySlotTimes() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            envelope(code: "0000", message: "Successful"),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.slotTimesMissing) {
            try await client.fetch(on: try testDay())
        }
    }

    // MARK: - One session, reused

    /// The guarantee the app now depends on: a second fetch through the same
    /// session costs no second handshake.
    ///
    /// Asserted on the **token both POSTs carried**, not on the request count
    /// alone. A client that re-handshakes and happens to be handed the same
    /// value back passes a count-only test while sending an extra GET to
    /// someone else's server on every refresh — the same trap the expiry
    /// replay documented in Phase 2.
    @Test("Two fetches through one session handshake once and carry one token")
    func reusesTheSessionAcrossFetches() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
            try fixtureBody(Fixture.anonymous),
        ])
        let session = CourtSession { transport }
        let client = AvailabilityClient(session: session)

        _ = try await client.fetch(on: try testDay())
        _ = try await client.fetch(on: try testDay())

        // One GET and two POSTs. A second handshake would make it four.
        #expect(transport.requestCount == 3)
        #expect(transport.posts.count == 2)

        let tokens = transport.posts.map { $0.value(forHTTPHeaderField: "X-CSRF-Token") }
        #expect(tokens == [firstToken, firstToken])
    }

    /// Two clients built from one session share its pairing too, which is what
    /// makes signing in on one path and fetching on another possible at all.
    @Test("Two clients over one session still handshake only once")
    func twoClientsShareOneHandshake() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
            try fixtureBody(Fixture.anonymous),
        ])
        let session = CourtSession { transport }

        _ = try await AvailabilityClient(session: session).fetch(on: try testDay())
        _ = try await AvailabilityClient(session: session).fetch(on: try testDay())

        #expect(transport.requestCount == 3)

        let tokens = transport.posts.map { $0.value(forHTTPHeaderField: "X-CSRF-Token") }
        #expect(tokens == [firstToken, firstToken])
    }

    /// The behaviour most at risk from keeping the session: a fetch *after* an
    /// expiry must use the refreshed token, not the discarded one.
    ///
    /// With a session per load this could not be got wrong — the next load
    /// started from nothing. Now the session outlives the call, so what it
    /// holds afterwards is worth asserting.
    @Test("A fetch after an expiry carries the refreshed token, not the stale one")
    func laterFetchUsesTheRefreshedToken() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            envelope(code: "0012", message: "Invalid CSRF token"),
            handshakePage(token: refreshedToken),
            try fixtureBody(Fixture.anonymous),
            try fixtureBody(Fixture.anonymous),
        ])
        let session = CourtSession { transport }
        let client = AvailabilityClient(session: session)

        _ = try await client.fetch(on: try testDay())
        _ = try await client.fetch(on: try testDay())

        // Two handshakes in total — the one at the start and the one the
        // expiry forced — and no third.
        #expect(transport.requestCount == 5)

        let tokens = transport.posts.map { $0.value(forHTTPHeaderField: "X-CSRF-Token") }
        #expect(tokens == [firstToken, refreshedToken, refreshedToken])
    }

    /// The session can still be deliberately reset, which is what sign-out
    /// will need: invalidating between fetches produces a second handshake and
    /// a second jar.
    @Test("Invalidating between fetches mints a new token")
    func invalidatingForcesASecondHandshake() async throws {
        let transport = ScriptedTransport(bodies: [
            handshakePage(token: firstToken),
            try fixtureBody(Fixture.anonymous),
            handshakePage(token: refreshedToken),
            try fixtureBody(Fixture.anonymous),
        ])
        let session = CourtSession { transport }
        let client = AvailabilityClient(session: session)

        _ = try await client.fetch(on: try testDay())
        await session.invalidate()
        _ = try await client.fetch(on: try testDay())

        #expect(transport.requestCount == 4)

        let tokens = transport.posts.map { $0.value(forHTTPHeaderField: "X-CSRF-Token") }
        #expect(tokens == [firstToken, refreshedToken])
    }

    /// With no scenario configured the harness offers nothing and the app
    /// falls through to a real session.
    ///
    /// The configured branch cannot be driven from in-process: the harness
    /// reads the process environment once, at launch, and the test process was
    /// not launched with it set. That half is a checkpoint line — `show stale`
    /// is precisely the scenario that only means anything if the app really
    /// does keep one session across loads.
    @Test("With nothing simulated the app builds a real session")
    func harnessOffersNothingWhenUnconfigured() {
        #expect(FailureSimulation.makeSession() == nil)
    }
}
