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

    /// Proves the device this suite is running on really is in 24-hour time.
    ///
    /// Without this, the gate below could pass on an ordinary 12-hour
    /// simulator and report success for a setting that was never applied. It
    /// runs only under Scripts/test-24h.sh, which is the only context where
    /// "the device shows 14:00" is a true statement.
    ///
    /// The hostility cannot be detected by inspecting the locale: the
    /// identifier stays "en_US" with the override in force. Only rendered
    /// output reveals it, so both spellings a developer might reach for are
    /// rendered here and required to come back in 24-hour form.
    @Test(
        "The device under test really is in 24-hour time",
        .enabled(if: ProcessInfo.processInfo.environment["COURTWATCH_EXPECT_24H"] == "1")
    )
    func confirmsDeviceIsForcedTo24Hour() throws {
        let reference = try referenceInstant()

        let deviceStyle = DateFormatter()
        deviceStyle.locale = .current
        deviceStyle.timeZone = CourtTime.zone
        deviceStyle.dateStyle = .none
        deviceStyle.timeStyle = .short

        let deviceFormatStyle = Date.FormatStyle(timeZone: CourtTime.zone)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)

        #expect(
            deviceStyle.string(from: reference) == "14:00",
            "The 24-hour setting was not applied, so this run proves nothing."
        )
        #expect(
            reference.formatted(deviceFormatStyle) == "14:00",
            "The modern formatting API stopped dropping the meridiem; this control is obsolete."
        )

        // The same instant, on the same device, through the app's own path.
        #expect(CourtTime.display.string(from: reference) == "2:00 PM")
    }

    /// The requirement itself: a court time reads the same way no matter how
    /// the device is configured.
    ///
    /// Each case builds its own comparison formatter from the locale under
    /// test, so the parameter does real work. The first control shows the
    /// hour cycle bending; the second shows that even the app's own pattern
    /// renders a different meridiem once the locale is not pinned. Japanese is
    /// the sharpest case: it localizes the meridiem itself, not just the hour.
    @Test(
        "A hostile device locale cannot change how a court time reads",
        arguments: [
            ("en_US@hours=h23", "2:00 PM"),
            ("en_US-u-hc-h23", "2:00 PM"),
            ("en_GB", "2:00 pm"),
            ("de_DE", "2:00 PM"),
            ("ja_JP", "2:00 午後"),
            ("th_TH", "2:00 PM"),
        ]
    )
    func holdsTwelveHourUnderHostileLocales(
        localeID: String, deviceMeridiem: String
    ) throws {
        let reference = try referenceInstant()
        let deviceLocale = Locale(identifier: localeID)

        // What the app would show if it trusted the device's own time style.
        let deviceStyle = DateFormatter()
        deviceStyle.locale = deviceLocale
        deviceStyle.timeZone = CourtTime.zone
        deviceStyle.dateStyle = .none
        deviceStyle.timeStyle = .short

        // The app's own pattern, with the locale pin removed.
        let devicePattern = DateFormatter()
        devicePattern.locale = deviceLocale
        devicePattern.timeZone = CourtTime.zone
        devicePattern.dateFormat = "h:mm a"

        #expect(
            deviceStyle.string(from: reference) != "2:00 PM",
            "\(localeID) no longer bends the hour cycle; this control is obsolete."
        )
        #expect(devicePattern.string(from: reference) == deviceMeridiem)

        #expect(CourtTime.display.string(from: reference) == "2:00 PM")
        #expect(SlotTime(apiString: "14:00:00")?.displayString == "2:00 PM")
    }
}
