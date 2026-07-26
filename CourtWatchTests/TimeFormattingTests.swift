import Foundation
import Testing

@testable import CourtWatch

/// The reference instant every time assertion is anchored to:
/// 2026-07-26 14:00 in America/Chicago.
private func referenceInstant() throws -> Date {
    try #require(
        CourtTime.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 14)
        ),
        "Could not build the 2026-07-26 14:00 Central reference instant"
    )
}

struct TimeFormattingTests {

    @Test("An afternoon instant displays as a 12-hour time with an uppercase meridiem")
    func displaysTwelveHourTime() throws {
        let reference = try referenceInstant()

        #expect(CourtTime.display.string(from: reference) == "2:00 PM")
        #expect(CourtTime.string(from: reference) == "2:00 PM")
    }

    @Test("An API slot string parses to its Central wall-clock time")
    func parsesSlotString() throws {
        let parsed = try #require(CourtTime.slotParser.date(from: "14:00:00"))

        #expect(CourtTime.calendar.component(.hour, from: parsed) == 14)
        #expect(CourtTime.calendar.component(.minute, from: parsed) == 0)
    }

    @Test("An API day string round-trips unchanged")
    func roundTripsDayString() throws {
        let parsed = try #require(CourtTime.dayParser.date(from: "2026-07-26"))

        #expect(CourtTime.dayParser.string(from: parsed) == "2026-07-26")
    }

    @Test("A malformed slot string returns nil rather than trapping")
    func rejectsMalformedSlotString() {
        #expect(CourtTime.slotParser.date(from: "not a time") == nil)
    }

    /// The pin that defeats both the 24-hour trap and the calendar trap. If a
    /// formatter ever loses it, the failure is silent on a developer's own
    /// machine, so assert it directly rather than only through rendered output.
    @Test("Every formatter is pinned to the invariant locale, zone and calendar")
    func pinsEveryFormatter() {
        for formatter in [CourtTime.slotParser, CourtTime.dayParser, CourtTime.display] {
            #expect(formatter.locale.identifier == "en_US_POSIX")
            #expect(formatter.timeZone.identifier == "America/Chicago")
            #expect(formatter.calendar.identifier == .gregorian)
        }
    }

    @Test("The shared calendar is Gregorian and anchored to Central")
    func pinsSharedCalendar() {
        #expect(CourtTime.calendar.identifier == .gregorian)
        #expect(CourtTime.calendar.timeZone.identifier == "America/Chicago")
        #expect(CourtTime.zone.identifier == "America/Chicago")
        #expect(CourtTime.posix.identifier == "en_US_POSIX")
    }
}
