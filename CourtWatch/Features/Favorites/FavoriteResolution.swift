//
//  FavoriteResolution.swift
//  CourtWatch
//
//  Reconciles what the user saved against what a response actually mentions,
//  and returns both halves.
//
//  An unmatched name is a place the user chose that this particular response
//  did not list. The app cannot tell which of two things happened: the
//  Township renamed it, or the response was incomplete. Neither is
//  distinguishable from here, and the two possible responses are not equally
//  costly. Deleting is irreversible and silent — the user is never told, and
//  the only way back is to notice the absence and pick again. Keeping the
//  string costs a few dead bytes and heals itself: if the name comes back, so
//  does the favorite, with nothing for the user to do.
//
//  So resolution returns a value and mutates nothing. Storage has no idea what
//  places exist and this has no idea where anything is stored, which is what
//  makes retention a property of the shapes involved rather than a rule
//  someone has to keep remembering.
//

import Foundation

/// What a saved selection came to, held against one response.
///
/// `unmatched` is deliberately unused by the interface in this phase. Telling
/// the user "one of the places you chose has disappeared" is error-state
/// design and belongs with the rest of it; what this phase promised is that
/// the name is *kept*, and it is. The value is here for that surface to pick
/// up when it is built.
nonisolated struct ResolvedFavorites: Sendable, Equatable {

    /// Favorited places this response listed, in the response's own order.
    let matched: [Facility]

    /// Favorited names this response did not list. Still saved, still on disk.
    let unmatched: [String]
}

nonisolated enum FavoriteResolution {

    /// Splits saved names into those a response accounts for and those it
    /// does not.
    ///
    /// Matching is exact. Search is forgiving because a human is typing into a
    /// box; this compares one derived string against another, and a fuzzy
    /// match here would silently resolve a favorite to the wrong place and
    /// show courts the user never asked for. The two operations look similar
    /// and are not.
    static func resolve(
        favorites: Set<String>, against facilities: [Facility]
    ) -> ResolvedFavorites {

        // Filtering the list rather than iterating the set is what preserves
        // order. A set has no order to preserve — iterating one would reshuffle
        // the sections on every launch, for the same reason a set cannot be
        // pinned on disk.
        let matched = facilities.filter { favorites.contains($0.id) }

        let listed = Set(facilities.map(\.id))

        // Sorted so the value is stable and comparable. Default `<`, matching
        // the storage order and independent of the device's locale.
        let unmatched = favorites.subtracting(listed).sorted()

        return ResolvedFavorites(matched: matched, unmatched: unmatched)
    }
}
