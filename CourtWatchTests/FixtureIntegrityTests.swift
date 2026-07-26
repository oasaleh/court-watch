//
//  FixtureIntegrityTests.swift
//  CourtWatchTests
//
//  Asserts the captured payloads are present, whole, and shaped the way the
//  rest of the suite assumes.
//
//  Deliberately written against `JSONSerialization` rather than the app's own
//  types. A suite that checks fixtures through the decoder under test cannot
//  tell "the fixture is wrong" from "the decoder is wrong", and it stops being
//  a fixed reference the moment the domain types are refactored. These
//  assertions describe the captures themselves and should survive every later
//  phase untouched.
//

import Foundation
import Testing

private func root(_ fixture: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: try Fixture.data(fixture))
    return try #require(object as? [String: Any], "\(fixture) is not a JSON object")
}

private func availability(_ fixture: String) throws -> [String: Any] {
    let body = try #require(
        try root(fixture)["body"] as? [String: Any], "\(fixture) has no body")
    return try #require(
        body["availability"] as? [String: Any], "\(fixture) has no body.availability")
}

private func resources(_ fixture: String) throws -> [[String: Any]] {
    try #require(
        try availability(fixture)["resources"] as? [[String: Any]],
        "\(fixture) has no resource array")
}

/// The identity of a court as this app cares about it: who it is and what its
/// day looks like. Everything else in a resource is presentation or dead
/// metadata.
private struct CourtDigest: Hashable {
    let id: Int
    let name: String
    let warnings: [String]
    let statuses: [Int]
}

private func digests(_ fixture: String) throws -> [CourtDigest] {
    try resources(fixture).map { resource in
        CourtDigest(
            id: resource["resource_id"] as? Int ?? -1,
            name: resource["resource_name"] as? String ?? "",
            warnings: resource["warning_messages"] as? [String] ?? [],
            statuses: (resource["time_slot_details"] as? [[String: Any]] ?? [])
                .map { $0["status"] as? Int ?? -1 }
        )
    }
}

struct FixtureIntegrityTests {

    /// The first thing to prove, because every other test in the phase is
    /// vacuous if it fails: the JSON actually reached the built bundle. A
    /// truncated or empty resource would otherwise surface much later as a
    /// confusing decode failure.
    @Test("Both captures bundle and load whole", arguments: Fixture.bothCaptures)
    func capturesLoad(fixture: String) throws {
        let data = try Fixture.data(fixture)

        #expect(data.count > 50_000, "\(fixture) loaded only \(data.count) bytes")
    }

    /// The code is a *string* in the payload. Decoding it as a number would
    /// turn "0000" into 0 and destroy the leading zeros that the expiry codes
    /// are identified by.
    @Test("Both captures report a successful response code", arguments: Fixture.bothCaptures)
    func capturesAreSuccessful(fixture: String) throws {
        let headers = try #require(
            try root(fixture)["headers"] as? [String: Any], "\(fixture) has no headers")

        #expect(headers["response_code"] as? String == "0000")
        #expect(headers["response_message"] as? String == "Successful")
    }

    @Test("Both captures publish sixteen hourly slot times", arguments: Fixture.bothCaptures)
    func capturesPublishSixteenSlots(fixture: String) throws {
        let slots = try #require(
            try availability(fixture)["time_slots"] as? [String],
            "\(fixture) has no time_slots")

        #expect(slots.count == 16)
        #expect(slots.first == "07:00:00")
        #expect(slots.last == "22:00:00")
    }

    /// The positional pairing the whole grid rests on: every court publishes
    /// exactly as many slot details as there are slot times.
    @Test("Both captures carry eighty courts of sixteen slots", arguments: Fixture.bothCaptures)
    func capturesCarryEightyCourts(fixture: String) throws {
        let courts = try resources(fixture)
        let slotCount = (try availability(fixture)["time_slots"] as? [String])?.count

        #expect(courts.count == 80)
        #expect(slotCount == 16)

        let detailCounts = Set(
            courts.map { ($0["time_slot_details"] as? [[String: Any]] ?? []).count })

        #expect(detailCounts == [16], "slot detail counts were \(detailCounts.sorted())")
    }

    /// Pins the vocabulary of the status field. A third value appearing is the
    /// event that would otherwise silently widen the domain — and the decoder
    /// maps anything unrecognised to `unknown` precisely because this can
    /// happen.
    @Test("Only zero and one appear as slot statuses", arguments: Fixture.bothCaptures)
    func statusVocabularyIsClosed(fixture: String) throws {
        let statuses = try digests(fixture).flatMap(\.statuses)

        #expect(statuses.count == 1280)
        #expect(Set(statuses) == [0, 1])
        #expect(statuses.filter { $0 == 1 }.count == 104)
        #expect(statuses.filter { $0 == 0 }.count == 1176)
    }

    @Test("Every court carries the non-resident warning", arguments: Fixture.bothCaptures)
    func warningsSurvive(fixture: String) throws {
        let warnings = try digests(fixture).map(\.warnings)

        #expect(warnings.count == 80)
        #expect(
            warnings.allSatisfy {
                $0 == ["Non-residents cannot make reservations more than 2 day(s) in advance."]
            })
    }

    /// The measurement that justifies deferring sign-in to Phase 6.
    ///
    /// A logged-in capture and an anonymous one, taken on the same day two
    /// hours apart, describe the same 80 courts with the same ids, the same
    /// warnings and the same 1,280 statuses. Signing in buys the user nothing
    /// this app displays. If the Township ever changes that, this is the test
    /// that says so, and the anonymous-first design would need revisiting
    /// rather than merely extending.
    @Test("Signing in changes nothing this app displays")
    func capturesAreEquivalent() throws {
        let anonymous = try digests(Fixture.anonymous)
        let loggedIn = try digests(Fixture.loggedIn)

        #expect(anonymous.count == 80)
        #expect(anonymous == loggedIn)
    }

    /// The one field that does differ, asserted so the equivalence above reads
    /// as a measured result rather than a comparison of two copies of the same
    /// file.
    @Test("The captures are distinct documents despite describing the same day")
    func capturesAreNotTheSameDocument() throws {
        let anonymousRefresh = try root(Fixture.anonymous)["headers"] as? [String: Any]
        let loggedInRefresh = try root(Fixture.loggedIn)["headers"] as? [String: Any]

        #expect(anonymousRefresh?["sessionRefreshedOn"] is NSNull)
        #expect(loggedInRefresh?["sessionRefreshedOn"] as? String == "2026-07-26 07:48:50")
    }
}
