//
//  CourtTime.swift
//  CourtWatch
//
//  This file owns every date and time conversion in the app.
//
//  Nothing else may build its own formatter. Two device settings quietly
//  corrupt times otherwise, and both produce plausible-looking output rather
//  than an error:
//
//    * A device set to 24-hour time renders an afternoon slot as "14:00",
//      which is not what this app promises to show.
//    * A device set to a non-Gregorian calendar parses "2026-07-26" as a date
//      centuries away. Under a Buddhist calendar it lands in 1483.
//
//  Both are invisible on a developer's own machine. Pinning the locale, the
//  zone and the calendar on every formatter here removes the risk at the
//  source; Scripts/check-time-discipline.sh keeps it removed.
//

import Foundation

enum CourtTime {

    /// The Township is in US Central. Pinned explicitly so a travelling user
    /// still sees the times the courts actually operate on.
    static let zone = TimeZone(identifier: "America/Chicago")!

    /// The invariant locale. Immune to the user's 24-hour, region and calendar
    /// settings, and the reason the meridiem prints as an uppercase "PM"
    /// instead of "pm" or a localized equivalent.
    static let posix = Locale(identifier: "en_US_POSIX")

    /// Never `Calendar.current`: that is the setting that shifts parsed years
    /// by centuries.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = posix
        return calendar
    }()

    /// Parses the `"HH:mm:ss"` times the API returns for each slot.
    ///
    /// A bare time carries no day, so parsing yields an instant on a reference
    /// day rather than today. Anchor it with `SlotTime.date(on:)` before
    /// comparing it to anything.
    static let slotParser = makeFormatter(pattern: "HH:mm:ss")

    /// Parses the `"yyyy-MM-dd"` dates the API returns.
    static let dayParser = makeFormatter(pattern: "yyyy-MM-dd")

    /// Renders every time the user sees. 12-hour, uppercase meridiem, no
    /// leading zero on the hour.
    static let display = makeFormatter(pattern: "h:mm a")

    static func string(from date: Date) -> String {
        display.string(from: date)
    }

    /// Locale, zone and calendar are assigned before the pattern: setting the
    /// pattern first and the locale second can re-derive the pattern.
    ///
    /// One shared instance per pattern is deliberate. These are thread-safe
    /// and reusing them is faster than building one per call.
    private static func makeFormatter(pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.timeZone = zone
        formatter.calendar = calendar
        formatter.dateFormat = pattern
        return formatter
    }
}
