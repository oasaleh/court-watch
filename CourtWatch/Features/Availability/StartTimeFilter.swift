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

    var id: String { start?.apiString ?? "any" }

    /// Show everything still to come.
    static let anyTime = StartTimeFilter(start: nil)

    /// A short list of round hours rather than a free time picker.
    ///
    /// The app shows one day of hourly slots, so a picker able to express
    /// 5:47 PM would offer precision the data cannot use — and every value it
    /// could express that is not on the hour would behave identically to the
    /// hour before it.
    static let choices: [StartTimeFilter] = {
        let hours = ["09:00:00", "12:00:00", "15:00:00", "18:00:00", "20:00:00"]

        // Spelled as a closure, never `map(StartTimeFilter.init)`: an unapplied
        // reference to a main-actor-isolated initializer does not convert.
        return [anyTime] + hours.compactMap { apiString in
            SlotTime(apiString: apiString).map { hour in StartTimeFilter(start: hour) }
        }
    }()

    /// What the control says, and what a screen reader announces.
    ///
    /// Built from `SlotTime.displayString` so it goes through `CourtTime` like
    /// every other time in the app — anything else would print a 24-hour time
    /// on a device set that way, and would fail the discipline guard first.
    var label: String {
        guard let start else { return "Any time" }

        return "From \(start.displayString)"
    }

    /// The window this filter wants over a day's slots.
    ///
    /// Nothing when no filter is set: that is a request for the whole day, which
    /// is exactly what an unwindowed fetch already is.
    ///
    /// The end is the day's own last slot, so a windowed request asks for
    /// "this hour onwards" rather than for a fixed span the server would have to
    /// guess at. `max` guards the degenerate case where a filter sits past the
    /// last slot — an end before its own start is not a window, and would be a
    /// strange thing to put on the wire.
    func window(over slots: [SlotTime]) -> RequestedWindow? {
        guard let start, let last = slots.last else { return nil }

        return RequestedWindow(start: start, end: Swift.max(start, last))
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
