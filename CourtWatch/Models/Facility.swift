//
//  Facility.swift
//  CourtWatch
//
//  Facilities do not exist in the API. It returns 80 court names and nothing
//  that says "Shadowbend" is a place, so the grouping the user actually thinks
//  in is inferred here by stripping a trailing court number.
//
//  Two things depend on the exact string this produces: Phase 3 persists
//  favorites keyed by it, and Phase 4 renders one section per facility. A
//  change to the rule silently orphans saved favorites rather than failing
//  visibly, which is why the derivation is pinned by a test against the real
//  capture rather than left to a regex that looks about right.
//

import Foundation

nonisolated enum FacilityName {

    /// Strips a trailing court number, leaving the facility.
    ///
    /// The last space-separated token is dropped when it is made only of digits
    /// and `#`, and contains at least one digit. Both conditions carry weight:
    ///
    ///   * Without the digit requirement, a name ending in a bare `#` would
    ///     lose its final token.
    ///   * Without tolerating `#`, `Timarron Tennis Court #1` and `#2` stay
    ///     separate and land in the facility picker as two entries reading
    ///     "#1" and "#2" — court numbers in a list that is supposed to show
    ///     facility names.
    ///
    /// Everything else in the capture is numbered conventionally, including the
    /// names that look irregular: `WendtwoodsTennis 1` is missing a space
    /// inside the name rather than before the number, and
    /// `Harper's Landing Tennis Court 2` is ordinary apart from the
    /// apostrophe. Several facilities legitimately end in `Tennis Court`, so
    /// only the number token may be removed — never a trailing word.
    static func derive(from resourceName: String) -> String {
        let trimmed = resourceName.trimmingCharacters(in: .whitespaces)

        var tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)

        guard let last = tokens.last else { return trimmed }

        let isCourtNumber =
            last.allSatisfy { $0.isNumber || $0 == "#" }
            && last.contains(where: \.isNumber)

        // A name that is nothing but a court number has no facility to fall
        // back to, so it keeps itself rather than becoming empty.
        guard isCourtNumber, tokens.count > 1 else { return trimmed }

        tokens.removeLast()
        return tokens.joined(separator: " ")
    }
}

/// The court number a human reads off the end of a court's name.
///
/// The API returns names and nothing that says which court is "first", so the
/// trailing number is the only ordering the user already has in their head.
/// With eleven courts at Bear Branch the difference between that order and a
/// lexical one is the first thing visible on screen: 1, 10, 11, 2 against
/// 1, 2, 3.
///
/// Narrow on purpose — the last space-separated token, one leading `#`
/// tolerated, and only when what remains is entirely digits. `Tennis 1a` reads
/// as unnumbered rather than as court 1, because a partial parse would order it
/// among the numbered courts while hiding that it is not one of them.
///
/// Returning `nil` rather than a sentinel keeps "no number here" a case the
/// caller has to decide about. Folding it to zero would sort a malformed name
/// ahead of court 1 and put it at the top of the screen.
nonisolated enum CourtNumber {

    static func parse(from courtName: String) -> Int? {
        let trimmed = courtName.trimmingCharacters(in: .whitespaces)

        guard let last = trimmed.split(separator: " ", omittingEmptySubsequences: true).last
        else { return nil }

        let digits = last.first == "#" ? last.dropFirst() : last

        // `isASCII` as well as `isNumber`: digits in other scripts satisfy
        // `isNumber` but do not convert, so checking both keeps the guard and
        // the conversion below from disagreeing about what a digit is.
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }

        // Still optional after all that: two hundred digits are all digits and
        // do not fit an `Int`. Such a name sorts as unnumbered rather than
        // trapping.
        return Int(digits)
    }
}

nonisolated struct Facility: Identifiable, Hashable, Sendable {

    /// The derived name is the identity. Phase 3 writes this string to disk.
    var id: String { name }

    let name: String
    let courts: [Court]

    /// Groups courts by derived facility name.
    ///
    /// Facilities sort by name so the picker and the tests see a stable order.
    /// Courts sort by the number a human reads off the end of the name, so Bear
    /// Branch's eleven read 1, 2, 3 … 10, 11 rather than the lexical
    /// 1, 10, 11, 2. Ordering is settled here rather than in the view because
    /// there should be one rule, not a second one wherever courts are drawn.
    ///
    /// Plain `<` on the fallback, never a localized comparison. Phase 3
    /// established this for the persisted favorites and the reasoning carries: a
    /// localized comparison reorders on a device set to another locale, which
    /// would make court order device-dependent and any test pinning it a flake.
    /// The names are ASCII, so scalar ordering is correct and stable everywhere.
    static func group(_ courts: [Court]) -> [Facility] {
        Dictionary(grouping: courts, by: \.facilityName)
            .map { name, courts in
                Facility(name: name, courts: courts.sorted(by: precedes))
            }
            .sorted { $0.name < $1.name }
    }

    /// Numbered courts first in numeric order, unnumbered after in name order.
    ///
    /// The name breaks the tie in every branch, so the sort is total: two courts
    /// that somehow share a number still come out in a stable, reproducible
    /// order rather than whichever order the payload happened to arrive in.
    private static func precedes(_ lhs: Court, _ rhs: Court) -> Bool {
        switch (CourtNumber.parse(from: lhs.name), CourtNumber.parse(from: rhs.name)) {
        case let (left?, right?):
            return left == right ? lhs.name < rhs.name : left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return lhs.name < rhs.name
        }
    }
}
