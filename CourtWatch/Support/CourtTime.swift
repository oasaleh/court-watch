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

//  Isolation: this type is `nonisolated` so that decoding, which runs off the
//  main actor, can parse slot times. The module builds with
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make every
//  member here main-actor-isolated and unreachable from the API layer.
//
//  The three formatters are `nonisolated(unsafe)` rather than wrapped. They are
//  configured once here and never mutated afterwards, and DateFormatter is
//  documented as safe for concurrent use under exactly that condition. The
//  annotation records an existing property of this code rather than granting a
//  new permission: sharing one instance per pattern was already the design, and
//  a mutation added later would be a bug with or without the annotation.

nonisolated enum CourtTime {

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

    /// The same, without the minutes.
    ///
    /// Slots are published on the hour, so "9:00 PM" spends three characters
    /// saying nothing — and those characters are the ones that decide whether a
    /// cell can carry its own time at all. Used only where the minutes are known
    /// to be zero; a timestamp keeps them, because there the minutes are the
    /// information.
    static let displayHour = makeFormatter(pattern: "h a")

    static func string(from date: Date) -> String {
        display.string(from: date)
    }

    /// Renders a day as `yyyy-MM-dd` in Central, the form the availability
    /// request's `reserve_date` takes.
    ///
    /// Here rather than at the call site because this is genuine date
    /// handling: the day depends on the time zone, and a request built from
    /// the device's zone would ask for tomorrow's courts late at night in
    /// Europe.
    static func dayString(from date: Date) -> String {
        dayParser.string(from: date)
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
