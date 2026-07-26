import Foundation
import Testing

@testable import CourtWatch

/// The exact slot list the availability endpoint returns for a tennis court:
/// hourly from 7am to 10pm.
private let publishedSlots = [
    "07:00:00", "08:00:00", "09:00:00", "10:00:00",
    "11:00:00", "12:00:00", "13:00:00", "14:00:00",
    "15:00:00", "16:00:00", "17:00:00", "18:00:00",
    "19:00:00", "20:00:00", "21:00:00", "22:00:00",
]

private func central(
    year: Int = 2026, month: Int = 7, day: Int = 26, hour: Int, minute: Int = 0
) throws -> Date {
    try #require(
        CourtTime.calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute)
        ),
        "Could not build \(year)-\(month)-\(day) \(hour):\(minute) Central"
    )
}

struct SlotTimeTests {

    @Test("An afternoon slot parses to its wall-clock hour and minute")
    func parsesAfternoonSlot() throws {
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        #expect(slot.hour == 14)
        #expect(slot.minute == 0)
    }

    @Test("A morning slot displays without a leading zero")
    func displaysMorningSlot() throws {
        let slot = try #require(SlotTime(apiString: "07:00:00"))

        #expect(slot.displayString == "7:00 AM")
    }

    @Test("A late slot displays as an evening 12-hour time")
    func displaysLateSlot() throws {
        let slot = try #require(SlotTime(apiString: "22:00:00"))

        #expect(slot.displayString == "10:00 PM")
    }

    /// The endpoint is undocumented and unversioned, so a slot it stops
    /// publishing in the expected shape must not take the app down with it.
    @Test("A malformed slot string yields no slot rather than trapping")
    func rejectsMalformedSlot() {
        #expect(SlotTime(apiString: "garbage") == nil)
    }

    @Test("Every published slot parses, and they order by time of day")
    func parsesEveryPublishedSlot() throws {
        let slots = try publishedSlots.map {
            try #require(SlotTime(apiString: $0), "Failed to parse \($0)")
        }

        #expect(slots.count == 16)
        #expect(slots == slots.sorted())
        #expect(slots.first?.hour == 7)
        #expect(slots.last?.hour == 22)
    }

    /// Parsing a bare time lands on a reference day, not today, so anchoring is
    /// mandatory before a slot can be compared against the current moment.
    @Test("A slot anchors onto the given Central day at its own wall-clock time")
    func anchorsOntoDay() throws {
        let day = try central(hour: 0)
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        let anchored = slot.date(on: day)
        let parts = CourtTime.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: anchored)

        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 26)
        #expect(parts.hour == 14)
        #expect(parts.minute == 0)
        #expect(CourtTime.display.string(from: anchored) == "2:00 PM")
    }

    @Test("Only the slots still to come count as upcoming")
    func filtersSlotsAlreadyPast() throws {
        let clock = FixedClock(now: try central(hour: 13, minute: 20))
        let slots = try publishedSlots.map { try #require(SlotTime(apiString: $0)) }

        let upcoming = slots.filter { $0.isPast(now: clock.now) == false }

        #expect(clock.today == clock.now)
        #expect(upcoming.count == 9)
        #expect(upcoming.first?.displayString == "2:00 PM")
        #expect(upcoming.last?.displayString == "10:00 PM")
    }

    /// A court free right now is still worth showing, so the boundary includes
    /// the current moment rather than excluding it.
    @Test("A slot happening exactly now has not passed")
    func treatsBoundaryAsUpcoming() throws {
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        #expect(slot.isPast(now: try central(hour: 14)) == false)
        #expect(slot.isPast(now: try central(hour: 14, minute: 1)))
        #expect(slot.isPast(now: try central(hour: 13, minute: 59)) == false)
    }
}
