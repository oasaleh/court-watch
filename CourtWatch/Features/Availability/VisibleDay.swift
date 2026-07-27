//
//  VisibleDay.swift
//  CourtWatch
//
//  What is left of today, for every court at once.
//
//  Everything the grid draws is a function of three inputs: the fetched
//  availability, a moment, and an optional start-time filter. Putting that
//  function here — pure, with the moment passed in rather than read — is what
//  makes TIME-04 and TIME-07 provable at a pinned instant instead of dependent
//  on the hour the suite happens to run.
//
//  Elapsed-slot filtering is deliberately global rather than per facility. Every
//  court in every facility therefore receives the identical slot list, which
//  gives the whole screen one implicit column grid for free: no shared scroll
//  offset, no synchronisation between sections, nothing that can drift.
//

import Foundation

/// The answer to "what's open here, and when" for one facility.
///
/// A value rather than a sentence. The caller renders it, which is what lets a
/// test assert the count and the slot independently of the wording.
nonisolated struct FacilitySummary: Hashable, Sendable {

    /// The earliest visible slot at which any of the facility's courts is free.
    let slot: SlotTime

    /// How many of its courts are free at that slot. Always at least one — a
    /// facility with nothing free has no summary rather than a summary of zero.
    let freeCourts: Int

    /// How many courts the facility has in total.
    ///
    /// Carried so the header can say "2 of 5" rather than "2". Two free out of
    /// two is a quiet court and two out of eleven is a busy one, and the bare
    /// count cannot tell them apart.
    let totalCourts: Int
}

nonisolated struct VisibleDay: Sendable, Equatable {

    /// The slots still worth showing, after both filters.
    let slots: [SlotTime]

    /// True when every published slot has fully elapsed and the user has not
    /// asked to look at a particular hour — the whole schedule is behind us and
    /// TIME-07's done-for-today state is correct.
    ///
    /// Deliberately not "`slots` is empty". A start-time filter can empty the
    /// visible list on a day that is far from over, and a fully booked facility
    /// empties nothing at all. Telling a user at lunchtime to go home because
    /// they asked to see only evening slots, or because one place is busy,
    /// would be a lie in two different ways.
    ///
    /// Equally, a user who has explicitly asked for the morning is never told
    /// the day is over: they asked to see something specific and the app shows
    /// it. This flag answers one question — has the day itself ended, with
    /// nothing asked of it.
    let isFinished: Bool

    /// Court id to that court's statuses for exactly `slots`, in the same order.
    ///
    /// Keyed by id rather than stored as a parallel array so that a caller
    /// walking a facility's courts cannot pair a row with the wrong court.
    private let statusesByCourt: [Int: [SlotStatus]]

    /// A day with nothing in it and nothing to say about why.
    ///
    /// For the moment before any data has arrived, and for previews. Not
    /// finished — "nothing loaded yet" and "today is over" are different
    /// answers, and this value must not make a loading screen claim the second.
    static let empty = VisibleDay(slots: [], isFinished: false, statusesByCourt: [:])

    /// Resolves the day.
    ///
    /// `startingAt` has no default. Omitting a filter and forgetting one look
    /// identical at a call site, and while the safe direction — showing more —
    /// is the one a mistake would take here, saying `nil` out loud costs a word
    /// and removes the ambiguity.
    ///
    /// **A start time is an explicit instruction and overrides the hide-the-past
    /// rule.** With no filter the app shows only what is still to come, because
    /// a slot that has ended is noise. But a user who deliberately picks 9 AM at
    /// nine in the evening is asking to see the morning, and answering an
    /// explicit request with an empty screen is the app second-guessing them.
    /// TIME-04 governs the default; it does not govern a direct instruction.
    static func resolve(
        availability: Availability,
        now: Date,
        startingAt start: SlotTime?
    ) -> VisibleDay {

        // The slot length comes from the payload. Reimplementing the comparison
        // here instead of calling `isElapsed` is how the two copies would drift;
        // that boundary is owned and pinned in one place.
        let remaining = availability.slotTimes.filter {
            $0.isElapsed(now: now, slotMinutes: availability.slotMinutes) == false
        }

        // With a filter the day is taken whole and cut at the chosen hour, so an
        // earlier choice reaches back past now. Without one, only what is left.
        let visible =
            start.map { start in availability.slotTimes.filter { $0 >= start } } ?? remaining

        // Every court's row is built by looking each *visible slot* up in that
        // court's own slots, rather than by filtering the court's list down to
        // what survived. The difference is the whole of D6:
        //
        //   * the row has exactly one entry per visible slot by construction,
        //     so the view has no index-versus-count case left to render — and
        //     the blank, screen-reader-hidden cell that used to fill it is gone
        //     along with the branch;
        //   * an entry is found by its own slot time, so a court missing some
        //     hours cannot have a later status slide into an earlier column.
        //     Position is the only thing connecting a status to an hour, and a
        //     lookup preserves it where index arithmetic does not.
        //
        // A court that never published a given hour gets `.unpublished`, which
        // says so on screen and out loud instead of drawing nothing.
        var statuses: [Int: [SlotStatus]] = [:]
        statuses.reserveCapacity(availability.courts.count)

        for court in availability.courts {
            // The uniquing initializer, keeping the first value for a repeated
            // key. `Dictionary(uniqueKeysWithValues:)` traps on a duplicate,
            // and a payload that published the same slot time twice would then
            // take the whole app down — crashing on malformed input being the
            // exact opposite of what this decoding posture is for. A grep gate
            // keeps the trapping form out.
            let byTime = Dictionary(
                court.slots.map { ($0.time, $0.status) },
                uniquingKeysWith: { first, _ in first }
            )

            statuses[court.id] = visible.map { byTime[$0] ?? .unpublished }
        }

        return VisibleDay(
            slots: visible,
            isFinished: remaining.isEmpty && start == nil,
            statusesByCourt: statuses
        )
    }

    /// This court's statuses, aligned to `slots`.
    ///
    /// Exactly one entry per visible slot for any court this day was built
    /// from, whatever the payload published — see `resolve`. Empty for a court
    /// this day was not built from, which is the same answer as "nothing to
    /// draw" and keeps the caller from having to unwrap.
    func statuses(for court: Court) -> [SlotStatus] {
        statusesByCourt[court.id] ?? []
    }

    /// D9's line: the earliest visible slot anyone here is free, and how many
    /// are, or nothing when the facility has no availability left.
    ///
    /// Neither an unrecognised status nor an unpublished hour is counted as
    /// free. That is D6 reaching the summary as well as the cells — a header
    /// promising "3 free at 6 PM" on the strength of three hours the app knows
    /// nothing about would be the same wrong answer, phrased more confidently.
    func summary(for facility: Facility) -> FacilitySummary? {
        for (index, slot) in slots.enumerated() {
            var free = 0

            for court in facility.courts {
                let row = statuses(for: court)

                // Provably unnecessary now: `resolve` builds every row with one
                // entry per visible slot, so a row is never short. Kept anyway,
                // because it costs nothing and an out-of-range read here would
                // be a crash rather than a wrong pixel.
                //
                // Its presence is not an invitation to index blindly elsewhere:
                // rows are uniform, and anywhere that needs to rely on that
                // should say so rather than re-deriving a guard against a case
                // that can no longer arise.
                guard index < row.count else { continue }
                if row[index] == .available { free += 1 }
            }

            if free > 0 {
                return FacilitySummary(
                    slot: slot, freeCourts: free, totalCourts: facility.courts.count)
            }
        }

        return nil
    }
}
