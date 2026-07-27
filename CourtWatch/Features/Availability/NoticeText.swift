//
//  NoticeText.swift
//  CourtWatch
//
//  One sentence each for the things earlier phases kept and never said.
//
//  Three values arrive here, and they are all the same kind of thing: something
//  a previous phase deliberately preserved so it would not be silently lost,
//  and then had nowhere to mention. Favorites that no longer resolve (Phase 3),
//  courts whose data was short or unreadable (Phases 2 and 5), and the
//  per-court warnings (kept by Phase 3, dropped by Phase 4 as noise).
//
//  All of them are empty or silent in both captures, which is the normal case
//  and the reason this is one quiet strip rather than a feature. Nothing at all
//  is said when there is nothing to say.
//
//  Warnings are surfaced **by exception, not by repetition**. All 80 courts
//  carry one identical notice about reserving more than two days ahead —
//  irrelevant to an app that only ever shows today. Repeating it eighty times
//  is noise and dropping it entirely throws away the one thing that value was
//  preserving, so it is reduced to a distinct set, the notice the app has
//  already accounted for is subtracted, and whatever remains is shown once.
//  Today that renders nothing. If the Township ever sends "This facility is
//  closed for maintenance today", it appears — and that is the case worth
//  building for.
//

import Foundation

nonisolated enum NoticeText {

    /// The two stable fragments of the residency notice.
    ///
    /// Matched on fragments rather than on the whole string because the day
    /// count inside it is a number that can change, and byte equality would let
    /// the notice through eighty times over the moment the Township edits it.
    ///
    /// Matched on **two** fragments rather than one loose word because
    /// over-matching is the failure that costs the user something: a closure
    /// notice quietly swallowed is one they never learn about. Each fragment
    /// alone appears in plausible warnings that must survive — "Non-residents
    /// must pay a surcharge at the gate" and "Please reserve in advance" — so
    /// both are required, and both directions are asserted.
    private static let accountedForFragments = ["non-residents", "in advance"]

    /// Whether this is the notice the app has already accounted for by only
    /// ever showing today.
    private static func isAccountedFor(_ warning: String) -> Bool {
        let text = warning.lowercased()

        return accountedForFragments.allSatisfy { text.contains($0) }
    }

    /// One line per thing worth saying, in the order they concern the user:
    /// their own saved places first, then what is wrong with the data, then
    /// whatever the Township said.
    ///
    /// Every count is written with plain interpolation. The numeric convenience
    /// call is matched by the date-handling guard and fails the build — that is
    /// measured, not theoretical.
    static func lines(
        unmatchedFavorites: [String],
        degradedCourts: [String],
        unreadableCourts: Int,
        warnings: [String]
    ) -> [String] {
        var lines: [String] = []

        // Still saved, and said so. The Phase 3 promise this value exists to
        // keep is that the name is kept; a line implying it was lost would be
        // worse than silence.
        if unmatchedFavorites.isEmpty == false {
            let names = list(unmatchedFavorites)
            let verb = unmatchedFavorites.count == 1 ? "isn't" : "aren't"

            lines.append("\(names) \(verb) in today's listing, but \(stillSaved(unmatchedFavorites.count))")
        }

        // A court you can still see, with hours it said nothing about.
        if degradedCourts.isEmpty == false {
            lines.append(
                "\(courtCount(degradedCourts.count)) reported only part of today, so some "
                    + "hours show as unknown.")
        }

        // A court that is not on the screen at all. Deliberately a separate
        // sentence from the one above: merging them would tell the user the
        // wrong thing about what they are looking at.
        if unreadableCourts > 0 {
            lines.append(
                "\(courtCount(unreadableCourts)) couldn't be read at all and \(isAreNot(unreadableCourts)) shown.")
        }

        // Distinct, minus what the app has accounted for, in the order the
        // response listed them.
        var seen = Set<String>()

        for warning in warnings {
            let trimmed = warning.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed.isEmpty == false else { continue }
            guard isAccountedFor(trimmed) == false else { continue }
            guard seen.insert(trimmed).inserted else { continue }

            lines.append(trimmed)
        }

        return lines
    }

    /// "1 court" or "4 courts", as plain digits.
    private static func courtCount(_ count: Int) -> String {
        count == 1 ? "1 court" : "\(count) courts"
    }

    private static func isAreNot(_ count: Int) -> String {
        count == 1 ? "isn't" : "aren't"
    }

    private static func stillSaved(_ count: Int) -> String {
        count == 1 ? "it's still saved." : "they're still saved."
    }

    /// "A", "A and B", or "A, B and C".
    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return ""

        case 1:
            return names[0]

        case 2:
            return "\(names[0]) and \(names[1])"

        default:
            return "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
    }
}
