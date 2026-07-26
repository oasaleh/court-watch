//
//  SlotTime.swift
//  CourtWatch
//
//  A reservable time of day, as published by the availability endpoint.
//
//  The endpoint sends bare times such as "14:00:00" with no date attached, so
//  parsing one yields an instant on an arbitrary reference day rather than
//  today. Anchor it with `date(on:)` before comparing it to the current
//  moment, or every slot looks decades old.
//

import Foundation

/// `nonisolated` for the same reason `CourtTime` is: availability decoding runs
/// off the main actor, and under this module's default isolation an
/// initializer that is implicitly main-actor-isolated cannot be called — or
/// referenced — from there.
nonisolated struct SlotTime: Hashable, Sendable, Comparable {
    let hour: Int
    let minute: Int

    /// Returns nil for anything that is not a slot time. The endpoint is
    /// undocumented and unversioned, so unexpected input degrades instead of
    /// crashing.
    init?(apiString: String) {
        guard let parsed = CourtTime.slotParser.date(from: apiString) else { return nil }

        let parts = CourtTime.calendar.dateComponents([.hour, .minute], from: parsed)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }

        self.hour = hour
        self.minute = minute
    }

    /// Places this time of day onto a specific Central day.
    func date(on day: Date) -> Date {
        var parts = CourtTime.calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute

        // Slots run 07:00 to 22:00 and the daylight-saving gap falls at 02:00,
        // so no slot can land in a missing hour. The fallback covers the
        // theoretical case without a force-unwrap.
        return CourtTime.calendar.date(from: parts) ?? day
    }

    var displayString: String {
        CourtTime.display.string(from: date(on: Date()))
    }

    /// The `"HH:mm:ss"` form the API expects when a request narrows the time
    /// window.
    ///
    /// Built from the integer components with zero padding rather than through
    /// a formatter. This is not date handling — there is no locale, calendar or
    /// zone involved in printing two numbers — and routing it through a
    /// formatter would add exactly the device-settings exposure that
    /// `CourtTime` exists to prevent.
    var apiString: String {
        let paddedHour = hour < 10 ? "0\(hour)" : "\(hour)"
        let paddedMinute = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(paddedHour):\(paddedMinute):00"
    }

    /// Whether this slot's hour is over.
    ///
    /// A slot survives until it **ends**, not until it starts. At 2:15 PM a
    /// court free until 3:00 PM is still worth walking to, so the 2:00 PM slot
    /// is still shown; at exactly 3:00 PM it is not. The boundary is inclusive
    /// at the end and exclusive at the start.
    ///
    /// `slotMinutes` is required and deliberately has no default. A default
    /// would quietly hand 60 to every call site that forgot to pass one, which
    /// is a hardcoded constant with extra steps and the same failure mode: if
    /// the API moved to 30-minute slots, the app would go on showing a slot for
    /// half an hour after it ended — a court advertised as free that is not.
    /// Requiring the parameter means every caller has to say where the number
    /// came from, and `Availability.slotMinutes` is where it comes from.
    ///
    /// Seconds are added rather than calendar minutes, which is safe for the
    /// same reason the note on `date(on:)` gives: slots run 07:00 to 22:00 and
    /// the daylight-saving gap falls at 02:00, so no slot can span it. Plain
    /// arithmetic also keeps this total, with no optional to unwrap and no
    /// second code path to get wrong.
    func isElapsed(now: Date, slotMinutes: Int) -> Bool {
        date(on: now).addingTimeInterval(TimeInterval(slotMinutes) * 60) <= now
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}
