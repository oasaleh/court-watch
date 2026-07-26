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

nonisolated struct Facility: Identifiable, Hashable, Sendable {

    /// The derived name is the identity. Phase 3 writes this string to disk.
    var id: String { name }

    let name: String
    let courts: [Court]

    /// Groups courts by derived facility name.
    ///
    /// Facilities sort by name so the picker and the tests see a stable order.
    /// Courts sort by name within a facility, which puts `10` before `2`
    /// lexically — ugly, but stable and predictable. Presentation ordering is
    /// Phase 4's problem; inventing a natural sort here would put a second,
    /// unpinned rule in the same place as the one that matters.
    static func group(_ courts: [Court]) -> [Facility] {
        Dictionary(grouping: courts, by: \.facilityName)
            .map { name, courts in
                Facility(name: name, courts: courts.sorted { $0.name < $1.name })
            }
            .sorted { $0.name < $1.name }
    }
}
