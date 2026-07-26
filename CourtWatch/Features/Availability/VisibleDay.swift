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
}

nonisolated struct VisibleDay: Sendable, Equatable {

    /// The slots still worth showing, after both filters.
    let slots: [SlotTime]

    /// True when every published slot has fully elapsed — the whole schedule is
    /// behind us and TIME-07's done-for-today state is correct.
    ///
    /// Deliberately not "`slots` is empty". A start-time filter can empty the
    /// visible list on a day that is far from over, and a fully booked facility
    /// empties nothing at all. Telling a user at lunchtime to go home because
    /// they asked to see only evening slots, or because one place is busy,
    /// would be a lie in two different ways. This flag answers one question:
    /// has the day itself ended.
    let isFinished: Bool

    /// Court id to that court's statuses for exactly `slots`, in the same order.
    ///
    /// Keyed by id rather than stored as a parallel array so that a caller
    /// walking a facility's courts cannot pair a row with the wrong court.
    private let statusesByCourt: [Int: [SlotStatus]]

    /// Resolves the day.
    ///
    /// `startingAt` has no default. Omitting a filter and forgetting one look
    /// identical at a call site, and while the safe direction — showing more —
    /// is the one a mistake would take here, saying `nil` out loud costs a word
    /// and removes the ambiguity.
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

        // A second, independent predicate applied after the first, so a filter
        // pointing into the past can only narrow and never resurrect.
        let visible = start.map { start in remaining.filter { $0 >= start } } ?? remaining

        // Selecting by slot rather than by index arithmetic. Index arithmetic is
        // what breaks on a court publishing fewer statuses than there are slots,
        // and Phase 2 recorded that such courts exist and are carried
        // deliberately: pairing by slot means a short court contributes fewer
        // entries rather than reading past its own end.
        let wanted = Set(visible)

        var statuses: [Int: [SlotStatus]] = [:]
        statuses.reserveCapacity(availability.courts.count)

        for court in availability.courts {
            statuses[court.id] = court.slots.filter { wanted.contains($0.time) }.map(\.status)
        }

        return VisibleDay(
            slots: visible,
            isFinished: remaining.isEmpty,
            statusesByCourt: statuses
        )
    }

    /// This court's statuses, aligned to `slots`.
    ///
    /// Empty for a court this day was not built from, which is the same answer
    /// as "nothing to draw" and keeps the caller from having to unwrap.
    func statuses(for court: Court) -> [SlotStatus] {
        statusesByCourt[court.id] ?? []
    }

    /// D9's line: the earliest visible slot anyone here is free, and how many
    /// are, or nothing when the facility has no availability left.
    ///
    /// An unrecognised status is not counted as free. That is D6 reaching the
    /// summary as well as the cells — a header promising "3 free at 6:00 PM" on
    /// the strength of three statuses the app does not understand would be the
    /// same wrong answer, phrased more confidently.
    func summary(for facility: Facility) -> FacilitySummary? {
        for (index, slot) in slots.enumerated() {
            var free = 0

            for court in facility.courts {
                let row = statuses(for: court)

                // A short court simply has no entry at this column.
                guard index < row.count else { continue }
                if row[index] == .available { free += 1 }
            }

            if free > 0 {
                return FacilitySummary(slot: slot, freeCourts: free)
            }
        }

        return nil
    }
}
