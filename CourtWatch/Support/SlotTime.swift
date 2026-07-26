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

struct SlotTime: Hashable, Sendable, Comparable {
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

    /// A slot starting exactly now has not passed: a court free this minute is
    /// still worth showing.
    func isPast(now: Date) -> Bool {
        date(on: now) < now
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}
