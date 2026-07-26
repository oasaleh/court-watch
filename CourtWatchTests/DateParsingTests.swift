import Foundation
import Testing

@testable import CourtWatch

struct DateParsingTests {

    /// Documents that the danger is real on this toolchain.
    ///
    /// A device set to a Buddhist calendar reads the API's "2026-07-26" as a
    /// date 543 years earlier, and reports no error while doing it. If a
    /// future OS stops behaving this way, this test fails and says the control
    /// is obsolete, rather than leaving the suite quietly testing nothing.
    @Test("An unpinned parser misreads an API date by centuries")
    func reproducesCalendarTrap() throws {
        let unpinned = DateFormatter()
        unpinned.locale = Locale(identifier: "th_TH")
        unpinned.timeZone = CourtTime.zone
        unpinned.dateFormat = "yyyy-MM-dd"

        let parsed = try #require(unpinned.date(from: "2026-07-26"))

        #expect(
            CourtTime.dayParser.string(from: parsed) != "2026-07-26",
            "The unpinned parser no longer misreads the date; this control is obsolete."
        )
        #expect(CourtTime.calendar.component(.year, from: parsed) == 1483)
    }

    /// The requirement: the app's own parser reads the same date whatever the
    /// device is set to.
    ///
    /// Each case also parses through an unpinned formatter built from the
    /// locale under test and asserts the year it lands on, which records which
    /// settings corrupt a date and which leave it alone. The two harmless
    /// cases are deliberate: they show the fault is the calendar, not merely
    /// "a foreign locale".
    @Test(
        "The pinned parser reads year 2026 whatever the device calendar is",
        arguments: [
            ("th_TH", 1483),
            ("ja_JP@calendar=japanese", 4044),
            ("ar_SA@calendar=islamic", 2587),
            ("fa_IR", 2647),
            ("en_GB", 2026),
            ("de_DE", 2026),
        ]
    )
    func parsesInvariantlyUnderHostileCalendars(
        localeID: String, unpinnedYear: Int
    ) throws {
        let unpinned = DateFormatter()
        unpinned.locale = Locale(identifier: localeID)
        unpinned.timeZone = CourtTime.zone
        unpinned.dateFormat = "yyyy-MM-dd"

        let unpinnedDate = try #require(unpinned.date(from: "2026-07-26"))
        #expect(CourtTime.calendar.component(.year, from: unpinnedDate) == unpinnedYear)

        let pinned = try #require(CourtTime.dayParser.date(from: "2026-07-26"))
        #expect(CourtTime.dayParser.string(from: pinned) == "2026-07-26")
        #expect(CourtTime.calendar.component(.year, from: pinned) == 2026)
    }

    /// A time zone bug is invisible to a developer already sitting in Central,
    /// so proving the zone is pinned needs a second zone to compare against.
    @Test("A parsed day and slot resolve to a Central instant, not a local one")
    func anchorsToCentral() throws {
        #expect(CourtTime.zone.identifier == "America/Chicago")

        let day = try #require(CourtTime.dayParser.date(from: "2026-07-26"))
        let slot = try #require(SlotTime(apiString: "14:00:00"))
        let instant = slot.date(on: day)

        #expect(CourtTime.display.string(from: instant) == "2:00 PM")

        let tokyo = DateFormatter()
        tokyo.locale = CourtTime.posix
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        tokyo.calendar = CourtTime.calendar
        tokyo.dateFormat = "h:mm a"

        #expect(tokyo.string(from: instant) != CourtTime.display.string(from: instant))
        #expect(tokyo.string(from: instant) == "4:00 AM")
    }

    /// The endpoint is undocumented and unversioned. Input it never promised
    /// to send must degrade rather than crash.
    @Test("Malformed input returns nil instead of trapping")
    func rejectsMalformedInput() {
        #expect(CourtTime.slotParser.date(from: "") == nil)
        #expect(CourtTime.slotParser.date(from: "half past two") == nil)
        #expect(CourtTime.dayParser.date(from: "2026-13-45") == nil)
        #expect(CourtTime.dayParser.date(from: "") == nil)
        #expect(SlotTime(apiString: "") == nil)
    }
}
