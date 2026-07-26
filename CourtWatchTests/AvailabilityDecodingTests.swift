//
//  AvailabilityDecodingTests.swift
//  CourtWatchTests
//
//  Decoding the availability payload into the domain types Phases 3 and 4
//  build on.
//
//  The endpoint is undocumented, unversioned, and can change without notice,
//  so most of what is asserted here is defensive behaviour rather than happy
//  path: a short slot array degrades one court instead of the payload, an
//  unrecognised status stays unrecognised instead of becoming "available", and
//  a null field decodes rather than throwing.
//

import Foundation
import Testing

@testable import CourtWatch

private func decodeAvailability(_ fixture: String) throws -> Availability {
    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self, from: try Fixture.data(fixture))
    return Availability(envelope: envelope)
}

struct AvailabilityDecodingTests {

    @Test("The capture decodes to eighty courts and sixteen slot times")
    func decodesFullPayload() throws {
        let availability = try decodeAvailability(Fixture.anonymous)

        #expect(availability.courts.count == 80)
        #expect(availability.slotTimes.count == 16)
        #expect(availability.degradedCourts.isEmpty)
    }

    @Test("Slot times parse in published order")
    func parsesSlotTimes() throws {
        let times = try decodeAvailability(Fixture.anonymous).slotTimes

        #expect(times.first == SlotTime(apiString: "07:00:00"))
        #expect(times.last == SlotTime(apiString: "22:00:00"))
        #expect(times == times.sorted())
    }

    @Test("The first court carries its identity from the payload")
    func decodesFirstCourt() throws {
        let court = try #require(try decodeAvailability(Fixture.anonymous).courts.first)

        #expect(court.id == 9)
        #expect(court.name == "Alden Bridge Tennis 1")
    }

    /// The positional pairing the entire Phase 4 grid rests on. `time_slots`
    /// and `time_slot_details` are parallel arrays and nothing in the payload
    /// restates a slot's time inside its detail, so index alignment is the only
    /// thing that connects a status to an hour.
    @Test("Every court pairs each slot with its published time")
    func pairsSlotsPositionally() throws {
        let availability = try decodeAvailability(Fixture.anonymous)

        #expect(availability.courts.allSatisfy { $0.slots.count == 16 })

        for court in availability.courts {
            #expect(court.slots.map(\.time) == availability.slotTimes)
        }
    }

    @Test("Status zero reads as available and status one reads as booked")
    func mapsStatusVocabulary() throws {
        let slots = try decodeAvailability(Fixture.anonymous).courts.flatMap(\.slots)

        #expect(slots.count == 1280)
        #expect(slots.filter { $0.status == .available }.count == 1176)
        #expect(slots.filter { $0.status == .booked }.count == 104)
    }

    /// Showing a court as free when it is not is the one wrong answer this app
    /// must never give, so an unrecognised status is preserved as unknown
    /// rather than folded into either known case.
    @Test("An unrecognised status stays unknown rather than becoming available")
    func preservesUnknownStatus() throws {
        let payload = """
            {"headers":{"response_code":"0000"},"body":{"availability":{
            "time_slots":["07:00:00","08:00:00"],
            "resources":[{"resource_id":1,"resource_name":"Test Tennis 1",
            "time_slot_details":[{"status":7},{"status":1}]}]}}}
            """

        let envelope = try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try #require(payload.data(using: .utf8)))
        let court = try #require(Availability(envelope: envelope).courts.first)

        #expect(court.slots.map(\.status) == [.unknown(7), .booked])
        #expect(court.slots.contains { $0.status == .available } == false)
    }

    @Test("Every court carries its warning messages")
    func decodesWarnings() throws {
        let courts = try decodeAvailability(Fixture.anonymous).courts

        #expect(
            courts.allSatisfy {
                $0.warnings == [
                    "Non-residents cannot make reservations more than 2 day(s) in advance."
                ]
            })
    }

    /// `package_name` is null on all 80 resources. A non-optional String here
    /// would fail the entire payload on a field the app never reads.
    @Test("A null package name decodes without failing the payload")
    func decodesNullPackageName() throws {
        let payload = """
            {"headers":{"response_code":"0000"},"body":{"availability":{
            "time_slots":["07:00:00"],
            "resources":[{"resource_id":1,"resource_name":"Test Tennis 1",
            "package_name":null,"package_id":0,"type_name":"facility",
            "time_slot_details":[{"status":0,"selected":false}]}]}}}
            """

        let envelope = try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try #require(payload.data(using: .utf8)))

        #expect(Availability(envelope: envelope).courts.count == 1)
    }

    /// DATA-04 and DATA-09 together: one malformed resource must not cost the
    /// user the other courts. `zip` is the mechanism — it cannot over-index by
    /// construction — and the affected court is named so Phase 5 has something
    /// to surface.
    @Test("A short slot array degrades one court and leaves the rest intact")
    func degradesShortResource() throws {
        let availability = try decodeAvailability(Fixture.shortResource)

        #expect(availability.slotTimes.count == 16)
        #expect(availability.courts.count == 3)
        #expect(availability.degradedCourts == ["Alden Bridge Tennis 1"])

        let degraded = try #require(availability.courts.first { $0.name == "Alden Bridge Tennis 1" })
        #expect(degraded.slots.count == 3)
        #expect(degraded.slots.map(\.time) == Array(availability.slotTimes.prefix(3)))

        let intact = availability.courts.filter { $0.name != "Alden Bridge Tennis 1" }
        #expect(intact.count == 2)
        #expect(intact.allSatisfy { $0.slots.count == 16 })
    }

    @Test("A payload with no availability body throws rather than trapping")
    func throwsOnMissingAvailability() throws {
        let payload = """
            {"headers":{"response_code":"0000"},"body":{}}
            """
        let data = try #require(payload.data(using: .utf8))

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AvailabilityEnvelope.self, from: data)
        }
    }

    @Test("Both captures decode to the same courts and statuses")
    func capturesDecodeIdentically() throws {
        let anonymous = try decodeAvailability(Fixture.anonymous)
        let loggedIn = try decodeAvailability(Fixture.loggedIn)

        #expect(anonymous.slotTimes == loggedIn.slotTimes)
        #expect(anonymous.courts == loggedIn.courts)
    }

    /// The request side of the same wire format. Task 6 sends these strings
    /// back as `start_time` / `end_time`, so a slot must render exactly as the
    /// API published it.
    @Test("A parsed slot renders back to the string the API sent")
    func slotTimeRoundTripsToAPIForm() throws {
        let published = try #require(
            try JSONSerialization.jsonObject(with: try Fixture.data(Fixture.anonymous))
                as? [String: Any]
        )
        let body = try #require(published["body"] as? [String: Any])
        let availability = try #require(body["availability"] as? [String: Any])
        let strings = try #require(availability["time_slots"] as? [String])

        let parsed = strings.compactMap { SlotTime(apiString: $0) }

        #expect(parsed.count == 16)
        #expect(parsed.map(\.apiString) == strings)
    }

    /// Single-digit hours must keep their leading zero, which is the case a
    /// naive interpolation gets wrong.
    @Test("Morning slots pad to two digits")
    func slotTimePadsSingleDigits() throws {
        #expect(try #require(SlotTime(apiString: "07:00:00")).apiString == "07:00:00")
        #expect(try #require(SlotTime(apiString: "09:30:00")).apiString == "09:30:00")
        #expect(try #require(SlotTime(apiString: "22:00:00")).apiString == "22:00:00")
    }
}
