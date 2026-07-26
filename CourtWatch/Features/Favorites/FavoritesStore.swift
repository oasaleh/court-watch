//
//  FavoritesStore.swift
//  CourtWatch
//
//  The user's chosen facilities, saved as the derived names themselves.
//
//  Note what this type cannot do. It has no parameter, no property and no
//  import through which the current list of places could reach it, so there is
//  no code path in which it could compare what is saved against what exists
//  and drop the difference. That omission is deliberate and load-bearing.
//
//  The reason is that a saved name can stop matching for two reasons that look
//  identical from here: the Township renamed a place, or this particular
//  response was incomplete. Pruning on that evidence is unrecoverable — the
//  user is never told, and the only way back is to notice and re-pick.
//  Keeping the string costs a few dead bytes and heals itself the moment the
//  name comes back. Reconciliation therefore happens in FavoriteResolution,
//  which returns what matched and what did not, and mutates nothing.
//
//  Two implementation details are measured rather than assumed:
//
//    * A sorted array is persisted, not the in-memory set. Swift seeds its
//      hasher per process, so a set's encoded byte order changes on every
//      launch and cannot be pinned by a test. The sort is the default `<` —
//      Unicode scalar order, locale-independent. A localized comparison would
//      reorder on a device in another locale and break the pin there and only
//      there.
//    * The SwiftUI storage property wrapper is deliberately absent. It does
//      not trigger view updates from inside an @Observable class, and it fails
//      silently: favorites persist correctly and the interface simply never
//      refreshes until the next launch.
//    * The write is spelled out in `toggle` rather than driven by a `didSet`
//      observer on the selection. Measured: @Observable rewrites a stored
//      property into a computed one, so the assignment that loads the saved
//      value in `init` runs the setter — and a `didSet` there fires during
//      initialization, writing straight back what was just read. On a value
//      this version could not decode that write replaces it with an empty
//      array, destroying data a later version or a rollback might still have
//      read. Loading must stay a read. A test asserts that constructing a
//      store writes nothing at all.
//

import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {

    /// Changing this string strands every selection already written under the
    /// old one. A test pins it independently for that reason.
    private static let storageKey = "favoriteFacilityNames"

    private let defaults: UserDefaults

    /// Membership is the only question the interface asks, so a set is the
    /// right shape to hold. It is not the right shape to write down.
    ///
    /// Mutating this does not save it — `toggle` does, and `toggle` is the
    /// only thing that can, because the setter is private. See the header for
    /// why an observer on this property would be wrong.
    private(set) var facilityNames: Set<String>

    /// Takes its defaults rather than reaching for the shared instance, so a
    /// test can hand it a private suite and leave the real domain untouched.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.facilityNames = Self.load(from: defaults)
    }

    func contains(_ name: String) -> Bool {
        facilityNames.contains(name)
    }

    /// Adds the name if it is absent, removes it if it is present.
    ///
    /// There is no save step: the write happens before this returns, so a
    /// force-quit immediately after a tap cannot lose the change.
    func toggle(_ name: String) {
        if facilityNames.contains(name) {
            facilityNames.remove(name)
        } else {
            facilityNames.insert(name)
        }

        persist()
    }

    /// Reads the saved selection, treating every failure as "nothing saved".
    ///
    /// A missing key, bytes that are not JSON, and JSON of the wrong shape all
    /// land here. None of them may throw: this runs during initialization, and
    /// a store that can fail to build is a launch crash the user cannot
    /// recover from without deleting the app. Losing the selection is two taps
    /// to fix; losing the app is not.
    private static func load(from defaults: UserDefaults) -> Set<String> {
        guard
            let data = defaults.data(forKey: storageKey),
            let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(names)
    }

    private func persist() {
        // Sorted so the bytes are a function of the content alone. See the
        // header: an unsorted set encodes differently on every launch.
        guard let data = try? JSONEncoder().encode(facilityNames.sorted()) else { return }

        defaults.set(data, forKey: Self.storageKey)
    }
}
