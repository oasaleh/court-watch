//
//  DefensiveDecodingTests.swift
//  CourtWatchTests
//
//  This file is DATA-09, and the assertion that carries it is not "a malformed
//  payload decodes" — it is **where the good statuses ended up**.
//
//  `time_slot_details` is positionally parallel to `time_slots`, and nothing in
//  the payload restates a slot's time inside its own detail. Position is the
//  only thing connecting a status to an hour. So the obvious tolerant decode —
//  skip the elements that fail — slides every later status one place earlier,
//  and a court free at 6 PM is advertised as free at 5 PM. That is a wrong
//  answer with no error, in the one direction this app must never be wrong.
//
//  A test that only counted survivors would pass that bug. Every assertion
//  about a corrupted row therefore names the exact statuses and the hours they
//  belong to, and the corruption is placed in the *middle* of the row, where a
//  shift is detectable — corrupting the last element would look identical under
//  both implementations.
//
//  Every payload here is built inline as a string rather than as a fixture.
//  Xcode flattens `Fixtures/` into the bundle root, so leaf names are a standing
//  collision trap; and these are one-line variations that read better beside
//  their assertions than in a file nobody opens. Both captures are uniformly
//  sixteen slots per court, so none of this can be reached from real data —
//  which is precisely why it is written out by hand.
//

import Foundation
import Testing

@testable import CourtWatch

// MARK: - Building payloads by hand

/// The four hours every row case below is written against.
private let fourSlots = ["07:00:00", "08:00:00", "09:00:00", "10:00:00"]

/// A whole envelope around a list of resource objects, given verbatim.
///
/// Taking the resources as raw JSON text is the point: these tests need to send
/// shapes no Swift type can express — a null status, a string where an integer
/// belongs, a missing key.
private func envelope(
    slots: [String] = fourSlots,
    resources: [String],
    responseCode: String? = "0000"
) -> String {
    let times = slots.map { "\"\($0)\"" }.joined(separator: ", ")
    let headers = responseCode.map { "{ \"response_code\": \"\($0)\" }" } ?? "{ }"

    return """
        {
          "headers": \(headers),
          "body": {
            "availability": {
              "time_slots": [\(times)],
              "resources": [\(resources.joined(separator: ",\n"))],
              "time_increment": 60
            }
          }
        }
        """
}

/// One resource, with its slot details given verbatim so they can be malformed.
private func resource(
    id: String = "1",
    name: String = "\"Some Tennis 1\"",
    details: [String],
    warnings: String = "[]"
) -> String {
    let body = details.map { "{\"status\": \($0)}" }.joined(separator: ", ")

    return """
        {
          "resource_id": \(id),
          "resource_name": \(name),
          "warning_messages": \(warnings),
          "time_slot_details": [\(body)]
        }
        """
}

/// A resource whose detail objects are given whole, for the missing-key case.
private func resourceWithRawDetails(
    id: String = "1", name: String = "\"Some Tennis 1\"", details: [String]
) -> String {
    """
    {
      "resource_id": \(id),
      "resource_name": \(name),
      "warning_messages": [],
      "time_slot_details": [\(details.joined(separator: ", "))]
    }
    """
}

private func decode(_ json: String) throws -> Availability {
    Availability(
        envelope: try JSONDecoder().decode(AvailabilityEnvelope.self, from: Data(json.utf8)))
}

private func capture(_ fixture: String) throws -> Availability {
    Availability(
        envelope: try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try Fixture.data(fixture)))
}

/// The statuses of one court, in published order.
private func statuses(of availability: Availability, id: Int) throws -> [SlotStatus] {
    let court = try #require(availability.courts.first { $0.id == id })
    return court.slots.map(\.status)
}

/// The hours one court published, in order — so a shift shows up as the wrong
/// hour rather than merely the wrong count.
private func hours(of availability: Availability, id: Int) throws -> [Int] {
    let court = try #require(availability.courts.first { $0.id == id })
    return court.slots.map(\.time.hour)
}

// MARK: - A scripted transport, for the two error paths that live in the client

private nonisolated final class ReplayTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Data]
    private var recorded: [URLRequest] = []

    init(bodies: [String]) {
        self.script = bodies.map { Data($0.utf8) }
    }

    var posts: [URLRequest] { lock.withLock { recorded.filter { $0.httpMethod == "POST" } } }
    var requestCount: Int { lock.withLock { recorded.count } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: Data = lock.withLock {
            recorded.append(request)
            return script.isEmpty ? Data() : script.removeFirst()
        }

        return (
            body,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

private let handshake = "<script>window.__csrfToken = \"370060c8-52de-4fc9-a95c-b5cfff762b53\";</script>"

private func testDay() throws -> Date {
    try #require(CourtTime.calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
}

// MARK: - Cases

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum MalformedStatusCases {

    /// Every way a single status can be unreadable, as raw JSON. All three
    /// currently fail the *whole document*, which is what this task exists to
    /// change.
    static let unreadable: [String] = ["null", "\"0\"", "\"available\"", "true", "{}", "[]"]
}

nonisolated enum UnreadableResourceCases {

    /// A resource that cannot be identified or named, as raw JSON fragments:
    /// the id, then the name.
    static let cases: [(String, String, String)] = [
        ("a null id", "null", "\"Some Tennis 2\""),
        ("a string id", "\"twelve\"", "\"Some Tennis 2\""),
        ("a null name", "2", "null"),
        ("a numeric name", "2", "12"),
    ]
}

struct DefensiveDecodingTests {

    // MARK: - A malformed status costs one slot, not the document

    /// The measured starting point: one null among 1,280 discarded all 80
    /// courts. Every one of these shapes must now decode.
    @Test(
        "A status that cannot be read costs its own slot and nothing else",
        arguments: MalformedStatusCases.unreadable
    )
    func unreadableStatusCostsOneSlot(bad: String) throws {
        let data = try decode(
            envelope(
                resources: [
                    resource(details: ["0", bad, "1", "0"]),
                    resource(id: "2", name: "\"Some Tennis 2\"", details: ["1", "1", "0", "0"]),
                ]))

        // Both courts survive. That is the whole point: one bad integer must
        // not cost the user the other seventy-nine.
        #expect(data.courts.count == 2)
        #expect(data.slotTimes.count == 4)

        #expect(
            try statuses(of: data, id: 1)
                == [.available, .unpublished, .booked, .available])
        #expect(
            try statuses(of: data, id: 2)
                == [.booked, .booked, .available, .available])
    }

    /// A detail object that simply has no `status` key at all.
    @Test("A detail object with no status key at all decodes as an unpublished hour")
    func missingStatusKeyCostsOneSlot() throws {
        let data = try decode(
            envelope(
                resources: [
                    resourceWithRawDetails(details: [
                        "{\"status\": 0}", "{\"selected\": false}", "{\"status\": 1}",
                        "{\"status\": 0}",
                    ])
                ]))

        #expect(data.courts.count == 1)
        #expect(
            try statuses(of: data, id: 1)
                == [.available, .unpublished, .booked, .available])
    }

    // MARK: - T-05-01: the placeholder holds its position

    /// **The assertion this whole task exists for.**
    ///
    /// A tolerant decoder that *skips* a malformed element would produce three
    /// details against four hours, and every status after the corruption would
    /// be paired with the hour before its own. Here that would read as
    /// `[available, booked, available, unpublished]` — a court shown free at 9 AM
    /// that is in fact free at 10, and booked at 8 when it is free.
    ///
    /// So the row is written with statuses chosen to make a shift unmistakable,
    /// the corruption is in the middle where a shift is visible, and both the
    /// statuses *and the hours they are paired with* are asserted.
    @Test("A malformed status keeps its position and relabels no later hour")
    func malformedStatusKeepsItsPosition() throws {
        let data = try decode(
            envelope(
                slots: ["07:00:00", "08:00:00", "09:00:00", "10:00:00", "11:00:00"],
                resources: [resource(details: ["1", "1", "null", "0", "0"])]))

        let court = try #require(data.courts.first)

        // Five hours in, five hours out. Nothing was deleted.
        #expect(court.slots.count == 5)
        #expect(try hours(of: data, id: 1) == [7, 8, 9, 10, 11])

        // The two free hours are 10 and 11 — where they were published — and
        // not 9 and 10, which is where a deletion would have put them.
        #expect(
            court.slots.map(\.status)
                == [.booked, .booked, .unpublished, .available, .available])

        let free = court.slots.filter { $0.status == .available }.map(\.time.hour)
        #expect(free == [10, 11], "a shifted row would report 9 and 10")

        // Said the other way round, because this is the sentence that matters:
        // the app must not claim the court is free at nine.
        let nine = try #require(court.slots.first { $0.time.hour == 9 })
        #expect(nine.status == .unpublished)
        #expect(nine.status != .available)
    }

    /// The same guarantee with the corruption at the front, where a shift would
    /// move every single remaining hour.
    @Test("A malformed first status does not pull the rest of the row forward")
    func malformedFirstStatusHoldsItsPlace() throws {
        let data = try decode(
            envelope(resources: [resource(details: ["null", "0", "1", "1"])]))

        let court = try #require(data.courts.first)

        #expect(
            court.slots.map(\.status)
                == [.unpublished, .available, .booked, .booked])

        let free = court.slots.filter { $0.status == .available }.map(\.time.hour)
        #expect(free == [8], "a shifted row would report 7")
    }

    /// Several corruptions in one row, each holding its own place.
    @Test("Several malformed statuses each cost only their own hour")
    func severalMalformedStatusesHoldTheirPlaces() throws {
        let data = try decode(
            envelope(
                slots: ["07:00:00", "08:00:00", "09:00:00", "10:00:00", "11:00:00", "12:00:00"],
                resources: [resource(details: ["0", "null", "1", "\"x\"", "0", "1"])]))

        let court = try #require(data.courts.first)

        #expect(try hours(of: data, id: 1) == [7, 8, 9, 10, 11, 12])
        #expect(
            court.slots.map(\.status)
                == [.available, .unpublished, .booked, .unpublished, .available, .booked])
    }

    // MARK: - The same guarantee on the other axis

    /// The mirror of the tests above, and the one the file's own preamble
    /// promises without ever having checked.
    ///
    /// Position is what connects a status to an hour, and the pairing can be
    /// broken from either side. Every test above corrupts a *status* and
    /// asserts the hours held. This corrupts an *hour* and asserts the statuses
    /// hold, because deleting an unreadable slot time and closing the gap
    /// slides every later status one hour earlier just as surely — with the
    /// difference that it does so for all eighty courts at once, since the
    /// slot-time list is shared.
    ///
    /// The corruption is in the middle, where a shift is visible, and the
    /// statuses either side of it are opposites so that a shift cannot be
    /// mistaken for a coincidence.
    @Test("An unreadable slot time costs its own hour and relabels no other")
    func unreadableSlotTimeKeepsTheRowAligned() throws {
        let data = try decode(
            envelope(
                slots: ["07:00:00", "08:00:00", "not a time", "10:00:00", "11:00:00"],
                resources: [resource(details: ["1", "1", "1", "0", "0"])]))

        let court = try #require(data.courts.first)

        // The unreadable hour takes itself out and nothing else with it.
        #expect(try hours(of: data, id: 1) == [7, 8, 10, 11])

        // 10 and 11 were published free and must still read free. A decoder
        // that closed the gap would pair 10 with the third status — booked —
        // and report the court taken at an hour it is open.
        let free = court.slots.filter { $0.status == .available }.map(\.time.hour)
        #expect(free == [10, 11], "a shifted row would report 8 and 10")

        #expect(court.slots.map(\.status) == [.booked, .booked, .available, .available])

        // The other direction, because this is the sentence that matters: the
        // app must not claim a court is taken when it is free.
        let ten = try #require(court.slots.first { $0.time.hour == 10 })
        #expect(ten.status == .available)
    }

    /// The same, corrupted at the front, where a shift moves every hour left.
    @Test("An unreadable first slot time does not pull the row forward")
    func unreadableFirstSlotTimeHoldsTheRest() throws {
        let data = try decode(
            envelope(
                slots: ["nonsense", "08:00:00", "09:00:00", "10:00:00"],
                resources: [resource(details: ["0", "1", "1", "0"])]))

        let court = try #require(data.courts.first)

        #expect(try hours(of: data, id: 1) == [8, 9, 10])
        #expect(court.slots.map(\.status) == [.booked, .booked, .available])

        let free = court.slots.filter { $0.status == .available }.map(\.time.hour)
        #expect(free == [10], "a shifted row would report 8")
    }

    /// A bad hour and a bad status in the same row, each costing only itself.
    @Test("A bad hour and a bad status do not compound")
    func unreadableTimeAndStatusTogether() throws {
        let data = try decode(
            envelope(
                slots: ["07:00:00", "bogus", "09:00:00", "10:00:00", "11:00:00"],
                resources: [resource(details: ["0", "1", "null", "1", "0"])]))

        let court = try #require(data.courts.first)

        #expect(try hours(of: data, id: 1) == [7, 9, 10, 11])
        #expect(
            court.slots.map(\.status) == [.available, .unpublished, .booked, .available])

        let free = court.slots.filter { $0.status == .available }.map(\.time.hour)
        #expect(free == [7, 11])
    }

    // MARK: - An unreadable resource is dropped, and counted

    /// Resources are independent of one another, so an unidentifiable one is
    /// safe to drop — it cannot be shown or grouped, and there is nothing to
    /// salvage. Details inside a resource are not independent, which is why
    /// they are padded instead. The asymmetry is the design.
    @Test(
        "A resource that cannot be identified is dropped, not fatal",
        arguments: UnreadableResourceCases.cases
    )
    func unreadableResourceIsDropped(label: String, id: String, name: String) throws {
        let data = try decode(
            envelope(
                resources: [
                    resource(details: ["0", "1", "0", "1"]),
                    resource(id: id, name: name, details: ["1", "1", "1", "1"]),
                    resource(id: "3", name: "\"Some Tennis 3\"", details: ["0", "0", "0", "0"]),
                ]))

        // The good courts are untouched, in order, with their own statuses.
        #expect(data.courts.count == 2, "\(label)")
        #expect(data.courts.map(\.id) == [1, 3], "\(label)")
        #expect(try statuses(of: data, id: 1) == [.available, .booked, .available, .booked])
        #expect(try statuses(of: data, id: 3) == [.available, .available, .available, .available])

        // Nothing vanishes without a trace.
        #expect(data.unreadableCourts == 1, "\(label)")
    }

    @Test("Several unreadable resources are all counted")
    func countsEveryDroppedResource() throws {
        let data = try decode(
            envelope(
                resources: [
                    resource(details: ["0", "0", "0", "0"]),
                    resource(id: "null", name: "\"Some Tennis 2\"", details: ["0"]),
                    resource(id: "3", name: "null", details: ["0"]),
                    resource(id: "4", name: "\"Some Tennis 4\"", details: ["1", "1", "1", "1"]),
                ]))

        #expect(data.courts.count == 2)
        #expect(data.unreadableCourts == 2)
    }

    /// A whole payload of unreadable resources is an empty grid rather than a
    /// thrown document — the slot times are still there, so the screen has
    /// something true to say.
    @Test("A payload of nothing but unreadable resources still decodes")
    func toleratesEveryResourceBeingUnreadable() throws {
        let data = try decode(
            envelope(
                resources: [
                    resource(id: "null", name: "null", details: ["0"]),
                    resource(id: "null", name: "null", details: ["0"]),
                ]))

        #expect(data.courts.isEmpty)
        #expect(data.unreadableCourts == 2)
        #expect(data.slotTimes.count == 4)
    }

    /// Short and unreadable are different conditions and both are reported.
    /// Folding them together would lose the distinction at the only place it is
    /// still visible: a short court is one you can still see, an unreadable one
    /// is not on the screen at all.
    @Test("A short resource is still named, separately from a dropped one")
    func shortResourceIsStillNamedSeparately() throws {
        let data = try decode(
            envelope(
                resources: [
                    resource(details: ["0", "1"]),
                    resource(id: "null", name: "\"Some Tennis 2\"", details: ["0", "1", "0", "1"]),
                    resource(id: "3", name: "\"Some Tennis 3\"", details: ["0", "1", "0", "1"]),
                ]))

        #expect(data.degradedCourts == ["Some Tennis 1"])
        #expect(data.unreadableCourts == 1)
        #expect(data.courts.count == 2)
    }

    /// A court with an unreadable status is neither short nor dropped — it
    /// published the right number of details and they were all readable objects.
    /// It shows up as one unpublished hour and nothing else.
    @Test("An unreadable status does not make a court short or dropped")
    func unreadableStatusIsNeitherShortNorDropped() throws {
        let data = try decode(
            envelope(resources: [resource(details: ["0", "null", "1", "0"])]))

        #expect(data.degradedCourts.isEmpty)
        #expect(data.unreadableCourts == 0)
        #expect(data.courts.count == 1)
    }

    // MARK: - The happy path is unchanged

    /// The tolerant path must not quietly change the ordinary one. Both
    /// captures are uniformly sixteen slots per court with readable ids and
    /// names throughout, so nothing in them may be padded, dropped or degraded.
    @Test("Both captures still decode whole", arguments: Fixture.bothCaptures)
    func capturesDecodeUnchanged(fixture: String) throws {
        let data = try capture(fixture)

        #expect(data.courts.count == 80)
        #expect(data.slotTimes.count == 16)
        #expect(data.facilities.count == 27)
        #expect(data.degradedCourts.isEmpty)
        #expect(data.unreadableCourts == 0)

        for court in data.courts {
            #expect(court.slots.count == 16, "\(court.name)")
            #expect(court.slots.contains { $0.status == .unpublished } == false, "\(court.name)")
        }
    }

    /// The committed short-resource fixture keeps behaving exactly as Phase 2
    /// pinned it: one court short, recorded by name, nothing dropped.
    @Test("The short-resource fixture is unchanged by tolerant decoding")
    func shortResourceFixtureIsUnchanged() throws {
        let data = try capture(Fixture.shortResource)

        #expect(data.degradedCourts.count == 1)
        #expect(data.unreadableCourts == 0)
    }

    // MARK: - T-05-03: a missing response code is never success

    /// Deliberately *not* made tolerant. A response with no readable code
    /// cannot be defaulted to success without rendering an error envelope as
    /// availability, and defaulting it to a failure would be indistinguishable
    /// from the decode failure it already produces.
    @Test("Headers with no response code still throw")
    func headersWithoutCodeStillThrow() {
        let json = envelope(resources: [resource(details: ["0"])], responseCode: nil)

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AvailabilityEnvelope.self, from: Data(json.utf8))
        }
    }

    /// The same fact stated as the thing that actually matters: it never
    /// reaches the user as data.
    @Test("A response with no code never reaches the screen as availability")
    func missingResponseCodeNeverReadsAsSuccess() async throws {
        let transport = ReplayTransport(bodies: [
            handshake,
            envelope(resources: [resource(details: ["0", "0", "0", "0"])], responseCode: nil),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.self) {
            try await client.fetch(on: try testDay())
        }

        // Terminal for the request: no re-handshake, no second POST.
        #expect(transport.posts.count == 1)
    }

    /// A null code is the same story — it is not a string, so it does not
    /// decode, and it must not become a success either.
    @Test("A null response code is not success")
    func nullResponseCodeIsNotSuccess() {
        let json = """
            {
              "headers": { "response_code": null },
              "body": { "availability": { "time_slots": [], "resources": [] } }
            }
            """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AvailabilityEnvelope.self, from: Data(json.utf8))
        }
    }

    // MARK: - T-05-08: a block page is not a schema change

    /// The HTTP status is deliberately never judged, because the API answers
    /// 200 for everything. The consequence is that a WAF interstitial or a
    /// captive-portal page arrives as a body that is not JSON — and "the court
    /// system changed and the app needs an update" is the wrong thing to tell
    /// someone who is merely being filtered.
    @Test("An HTML block page is not read as a schema change")
    func htmlBlockPageIsItsOwnError() async throws {
        let transport = ReplayTransport(bodies: [
            handshake,
            """
            <html><head><title>Request Rejected</title></head>
            <body>The requested URL was rejected. Please consult with your administrator.</body>
            </html>
            """,
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.notJSON) {
            try await client.fetch(on: try testDay())
        }

        #expect(transport.posts.count == 1, "a block page must not be retried")
        #expect(transport.requestCount == 2, "and must not re-handshake")
    }

    /// A captive-portal login page, which is the other common way a body that
    /// is not the API arrives.
    @Test("A leading-whitespace HTML page is still not JSON")
    func leadingWhitespaceHTMLIsNotJSON() async throws {
        let transport = ReplayTransport(bodies: [
            handshake, "\n\n   <!DOCTYPE html><html><body>Sign in to continue</body></html>",
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.notJSON) {
            try await client.fetch(on: try testDay())
        }
    }

    /// An empty body is not the API either.
    @Test("An empty body is not JSON")
    func emptyBodyIsNotJSON() async throws {
        let transport = ReplayTransport(bodies: [handshake, ""])
        let client = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.notJSON) {
            try await client.fetch(on: try testDay())
        }
    }

    /// The other half of the split, and the one that keeps it honest: valid
    /// JSON whose shape is wrong is still a schema change, and must **not** be
    /// reported as something sitting in the way.
    @Test("Valid JSON of the wrong shape is still a schema change")
    func wrongShapeIsStillADecodingError() async throws {
        let transport = ReplayTransport(bodies: [
            handshake, #"{"headers": {"response_code": "0000"}, "body": {"something_else": 1}}"#,
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        do {
            _ = try await client.fetch(on: try testDay())
            Issue.record("expected a decoding failure")
        } catch let error as APIError {
            // Specifically a decoding failure, not the not-the-API one.
            if case .decoding = error {} else {
                Issue.record("expected .decoding, got \(error)")
            }
        }

        #expect(transport.posts.count == 1)
    }

    /// A JSON array is a shape the API never sends, but it *is* JSON — so it
    /// is a schema change rather than a block page. The check is on the first
    /// byte and nothing more, deliberately.
    @Test("A JSON array is a schema change, not a block page")
    func jsonArrayIsADecodingError() async throws {
        let transport = ReplayTransport(bodies: [handshake, "[1, 2, 3]"])
        let client = AvailabilityClient(session: CourtSession { transport })

        do {
            _ = try await client.fetch(on: try testDay())
            Issue.record("expected a decoding failure")
        } catch let error as APIError {
            if case .decoding = error {} else {
                Issue.record("expected .decoding, got \(error)")
            }
        }
    }

    /// The two are different values, so the presentation layer can give them
    /// different sentences.
    @Test("The two failures are distinguishable as values")
    func notJSONIsNotDecoding() {
        #expect(APIError.notJSON != APIError.decoding("anything"))
    }

    /// Neither new path may cost the Township a second request.
    @Test("Neither a block page nor a schema change re-handshakes")
    func neitherPathRehandshakes() async throws {
        for body in ["<html>blocked</html>", #"{"headers": {}}"#] {
            let transport = ReplayTransport(bodies: [handshake, body])
            let client = AvailabilityClient(session: CourtSession { transport })

            await #expect(throws: APIError.self) {
                try await client.fetch(on: try testDay())
            }

            #expect(transport.posts.count == 1, "\(body)")
            #expect(transport.requestCount == 2, "\(body)")
        }
    }

    // MARK: - A malformed payload survives the whole client path

    /// End to end: the tolerant decode is reached through the real client, not
    /// only through `JSONDecoder` in a test.
    @Test("A malformed status survives the client and reaches the grid")
    func malformedStatusSurvivesTheClient() async throws {
        let transport = ReplayTransport(bodies: [
            handshake,
            envelope(
                resources: [
                    resource(details: ["0", "null", "1", "0"]),
                    resource(id: "2", name: "\"Some Tennis 2\"", details: ["0", "0", "0", "0"]),
                ]),
        ])
        let client = AvailabilityClient(session: CourtSession { transport })

        let data = try await client.fetch(on: try testDay())

        #expect(data.courts.count == 2)
        #expect(
            try statuses(of: data, id: 1)
                == [.available, .unpublished, .booked, .available])
    }
}
