//
//  StartTimeFilter.swift
//  CourtWatch
//
//  "Only show me from six o'clock" — and the question of whether answering that
//  costs a network request.
//
//  The initial fetch is unwindowed, so the whole day is in hand. Narrowing is
//  then a strict subset of data already held: instant, free, works offline, and
//  costs the WAF-fronted host nothing. Re-fetching to obtain a subset of what
//  you already have is a round trip that can only lose.
//
//  But a windowed *refresh* does reach the server, and that is where the hazard
//  this file exists to prevent begins. Once a windowed refresh has happened the
//  app no longer holds the whole day. If the user then **widens** the filter,
//  filtering locally would silently show fewer slots than exist — and on screen
//  that is indistinguishable from those courts being booked. A wrong answer,
//  with no error, in the one direction this app must never be wrong.
//
//  So "do I actually have this data?" is a named, tested function of the window
//  the held data came from against the window being asked for. It is computed,
//  not assumed.
//
//  The window is expressed with this file's own value type rather than the
//  client's nested one. That is the right seam — this file decides *what window
//  is wanted* and the root screen decides *how the client is asked for it* — and
//  it is also enforced: everything under Features/ is grep-gated against client
//  types.
//

import Foundation

/// A time window, in the terms of the layer that wants one.
nonisolated struct RequestedWindow: Hashable, Sendable {
    let start: SlotTime
    let end: SlotTime
}

nonisolated struct StartTimeFilter: Hashable, Sendable, Identifiable {

    /// The earliest slot the user wants to see, or nothing for the whole of
    /// what is left of today.
    let start: SlotTime?

    var id: String { start?.apiString ?? "now" }

    /// Show everything still to come, and nothing that has ended.
    ///
    /// Named for what it does rather than for the absence of a filter. It reads
    /// "Now" because that is literally the window — an earlier name of "any
    /// time" claimed the opposite of the truth, since this state is the one that
    /// hides the morning.
    static let fromNow = StartTimeFilter(start: nil)

    /// A start time for each slot the day actually publishes.
    ///
    /// Derived from the fetched day rather than hardcoded. A fixed list gets the
    /// first hour wrong the moment the Township changes its opening time, and a
    /// list that starts later than the first slot silently makes the earliest
    /// courts unreachable — which is exactly what a hardcoded 9 AM did on a day
    /// whose first slot is 7 AM.
    ///
    /// Spelled as a closure, never `map(StartTimeFilter.init)`: an unapplied
    /// reference to a main-actor-isolated initializer does not convert.
    static func choices(for slots: [SlotTime]) -> [StartTimeFilter] {
        [fromNow] + slots.map { hour in StartTimeFilter(start: hour) }
    }

    /// What the control says, and what a screen reader announces.
    ///
    /// "Now" rather than "Any time": with no start chosen the app shows what is
    /// still to come and hides what has ended, so naming it "any time" described
    /// the one thing it does not do.
    ///
    /// Built from `SlotTime.displayString` so it goes through `CourtTime` like
    /// every other time in the app — anything else would print a 24-hour time
    /// on a device set that way, and would fail the discipline guard first.
    var label: String {
        guard let start else { return "Now" }

        return "From \(start.displayString)"
    }

    /// The window this filter wants over a day's slots.
    ///
    /// Nothing when no filter is set: that is a request for the whole day, which
    /// is exactly what an unwindowed fetch already is.
    ///
    /// The end is the moment the day's **last slot ends**, not the moment it
    /// begins. `end_time` was measured to be exclusive — asking 12:00 to 22:00
    /// returns 12:00 through 21:00 and drops the 22:00 slot entirely. Naming the
    /// start of the last slot as the bound therefore loses that slot on every
    /// windowed refresh, and because the next window is computed from the
    /// shortened list it loses another, and another, until the day is empty and
    /// the app reports that today is over while courts are still free.
    ///
    /// `max` guards the degenerate case where a filter sits past the last slot —
    /// an end before its own start is not a window.
    func window(over slots: [SlotTime], slotMinutes: Int) -> RequestedWindow? {
        guard let start, let last = slots.last else { return nil }

        let bound = last.endingBoundary(slotMinutes: slotMinutes)

        return RequestedWindow(start: start, end: Swift.max(start, bound))
    }

    /// Whether data fetched under one window answers a request for another.
    ///
    /// The whole decision, deliberately a named function over two values rather
    /// than a condition inlined at the call site. It is the thing standing
    /// between the user and the silent-subset bug described in the file note, so
    /// it is worth being able to point at, and worth testing in both directions.
    ///
    /// It consults nothing but its two arguments — no client, no cache, no
    /// clock — which is what makes it answerable in a test without a network.
    static func covers(held: RequestedWindow?, requested: RequestedWindow?) -> Bool {
        // Unwindowed held data is the whole day, which covers every request.
        guard let held else { return true }

        // Holding a slice and being asked for the whole day. This is the case
        // that must fetch: local filtering here would show only the slice and
        // look exactly like a fully booked morning.
        guard let requested else { return false }

        // Holding a slice, asked for a slice: covered only if the request starts
        // no earlier than what is held. Narrowing is free; widening is not.
        return requested.start >= held.start
    }
}
