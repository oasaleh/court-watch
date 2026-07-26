//
//  FavoritesStoreTests.swift
//  CourtWatchTests
//
//  The user's saved selection is keyed by a string this app invents. Nothing
//  in the API issues a stable facility identifier, so a favorite is only as
//  durable as the derivation rule that produced its key and the storage format
//  that wrote it down. Both can be changed by an edit that looks harmless, and
//  both fail silently when they are: the favorite simply stops matching, with
//  no error and nothing on screen to say the selection was lost.
//
//  So the representation is pinned here, byte for byte, and the pinned names
//  are checked back against what `FacilityName.derive` produces from the real
//  capture. Between them, a change to either side has to walk past a failing
//  test.
//
//  Every test runs against its own `UserDefaults` suite, named from a fresh
//  UUID and removed when the test ends. Nothing here reads or writes the
//  defaults the app itself uses.
//

import Foundation
import Testing

@testable import CourtWatch

/// The storage key, written out here rather than read back from the store.
///
/// Asking the store for its own key would agree with any rename and prove
/// nothing. Naming it independently is what makes a rename fail: data written
/// under the old key is stranded on disk, and stranded data is exactly the
/// silent loss this file exists to catch.
private let storageKey = "favoriteFacilityNames"

/// The exact bytes three favorites occupy on disk.
///
/// Four separate promises are folded into this one literal, and any of them
/// breaking would otherwise be invisible:
///
///   * the container is a JSON **array**, not a set or a dictionary
///   * the elements are in ascending Unicode scalar order
///   * `Harper's` keeps its U+0027 apostrophe unescaped
///   * the strings themselves are what the derivation currently produces
///
/// A `Set` could not be pinned this way. Swift seeds its hasher per process,
/// so set iteration order — and therefore the encoded byte sequence — differs
/// on every launch. Measured across five launches, the same set produced five
/// different orderings while the sorted array produced one.
private let pinnedRepresentation =
    #"["Bear Branch Tennis","Harper's Landing Tennis Court","Shadowbend Tennis"]"#

/// A `UserDefaults` suite private to a single test.
///
/// `UserDefaults(suiteName:)` was measured to be genuinely isolated: writing
/// into a suite leaves the app's own domain untouched, and removing the
/// persistent domain clears it. That is the entire testing strategy for this
/// type, and it is why the store takes its defaults as an initializer
/// parameter instead of reaching for the shared one.
private struct IsolatedDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = "com.courtwatch.tests.\(UUID().uuidString)"
        suiteName = name
        defaults = try #require(
            UserDefaults(suiteName: name),
            "Could not open a private defaults suite named \(name)")
    }

    /// Removes the whole domain, so nothing survives into the next test.
    func discard() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The raw bytes currently stored under the favorites key, if any.
    var storedBytes: Data? {
        defaults.data(forKey: storageKey)
    }
}

struct FavoritesStoreTests {

    // MARK: - The basics

    @Test("A store over an untouched suite has no favorites")
    func emptySuiteHasNoFavorites() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)

        #expect(store.facilityNames.isEmpty)
        #expect(store.contains("Shadowbend Tennis") == false)
    }

    /// FAC-04: the user can change their mind at any time, in both directions.
    @Test("Toggling a name on adds it and toggling it again removes it")
    func togglesBothWays() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)

        store.toggle("Shadowbend Tennis")
        #expect(store.contains("Shadowbend Tennis"))
        #expect(store.facilityNames == ["Shadowbend Tennis"])

        store.toggle("Shadowbend Tennis")
        #expect(store.contains("Shadowbend Tennis") == false)
        #expect(store.facilityNames.isEmpty)
    }

    /// FAC-03, as close as a unit test gets to it. A second instance reading
    /// the same suite is what a relaunch does; the checkpoint performs the
    /// real force-quit.
    @Test("A second store over the same suite sees the first one's choice")
    func aSecondStoreReadsWhatTheFirstWrote() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let first = FavoritesStore(defaults: suite.defaults)
        first.toggle("Bear Branch Tennis")
        first.toggle("Shadowbend Tennis")

        let second = FavoritesStore(defaults: suite.defaults)

        #expect(second.facilityNames == ["Bear Branch Tennis", "Shadowbend Tennis"])
    }

    /// FAC-04 again, at a finer grain: there is no save step to forget and no
    /// flush to wait for. If the write were deferred, a force-quit between the
    /// tap and the flush would lose it.
    @Test("The value is on disk by the time the toggle returns")
    func togglingWritesThroughImmediately() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)
        #expect(suite.storedBytes == nil)

        store.toggle("Sawmill Tennis")

        let bytes = try #require(suite.storedBytes, "Nothing was written by the toggle")
        let decoded = try JSONDecoder().decode([String].self, from: bytes)

        #expect(decoded == ["Sawmill Tennis"])
    }

    @Test("Removing the last favorite leaves an empty array rather than stale bytes")
    func removingWritesThroughToo() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)
        store.toggle("Sawmill Tennis")
        store.toggle("Sawmill Tennis")

        let bytes = try #require(suite.storedBytes)
        #expect(try JSONDecoder().decode([String].self, from: bytes) == [])
        #expect(FavoritesStore(defaults: suite.defaults).facilityNames.isEmpty)
    }

    // MARK: - The pinned representation

    @Test("Three favorites persist as exactly the pinned bytes")
    func persistedBytesMatchThePin() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)

        // Deliberately not in sorted order. The store is what sorts.
        store.toggle("Shadowbend Tennis")
        store.toggle("Harper's Landing Tennis Court")
        store.toggle("Bear Branch Tennis")

        let bytes = try #require(suite.storedBytes, "Nothing was written")
        let written = try #require(String(data: bytes, encoding: .utf8))

        #expect(
            written == pinnedRepresentation,
            """
            The persisted representation changed.

            expected: \(pinnedRepresentation)
                 got: \(written)

            Anything already on a user's device is written in the expected \
            form. If this change is intended it is a migration, not an edit.
            """)
    }

    /// The link the whole phase hangs on: the persisted string is a
    /// `Facility.id`, which is a `FacilityName.derive` output, which is
    /// computed from a court name the API happened to send.
    ///
    /// Without this assertion the pin above would keep passing while the
    /// derivation drifted underneath it, and every saved favorite on every
    /// device would quietly stop matching.
    @Test("Every pinned name is one the derivation produces from the real capture")
    func pinnedNamesTrackTheDerivation() throws {
        let envelope = try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try Fixture.data(Fixture.anonymous))

        let derived = Set(
            envelope.body.availability.resources.map {
                FacilityName.derive(from: $0.resourceName)
            })

        let pinned = try JSONDecoder().decode(
            [String].self, from: Data(pinnedRepresentation.utf8))

        #expect(pinned.count == 3)

        for name in pinned {
            #expect(
                derived.contains(name),
                """
                "\(name)" is pinned as a persisted favorite, but no court in \
                the capture derives to it. Either the capture changed or \
                FacilityName.derive did — and on a real device that means a \
                saved favorite has just stopped matching, with no error.
                """)
        }
    }

    /// The identity is spelled out rather than assumed: favorites are keyed by
    /// `Facility.id`, and `Facility.id` is the derived name.
    @Test("The persisted key is the facility id, not some other string")
    func favoritesAreKeyedByFacilityID() throws {
        let envelope = try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try Fixture.data(Fixture.anonymous))
        let facilities = Availability(envelope: envelope).facilities

        let shadowbend = try #require(
            facilities.first { $0.name == "Shadowbend Tennis" },
            "The capture no longer contains Shadowbend Tennis")

        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)
        store.toggle(shadowbend.id)

        #expect(FavoritesStore(defaults: suite.defaults).contains("Shadowbend Tennis"))
    }

    @Test("Favorites are stored in ascending scalar order whatever order they arrive in")
    func persistsInAscendingOrder() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let store = FavoritesStore(defaults: suite.defaults)

        for name in ["Windvale Tennis", "Alden Bridge Tennis", "Meadowlake Tennis"] {
            store.toggle(name)
        }

        let bytes = try #require(suite.storedBytes)
        let decoded = try JSONDecoder().decode([String].self, from: bytes)

        #expect(decoded == ["Alden Bridge Tennis", "Meadowlake Tennis", "Windvale Tennis"])
        #expect(decoded == decoded.sorted())
    }

    /// Both apostrophe facilities, because there are two and a test covering
    /// only one would miss half the class.
    @Test("An apostrophe survives the round trip intact")
    func apostropheRoundTrips() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let first = FavoritesStore(defaults: suite.defaults)
        first.toggle("Harper's Landing Tennis Court")
        first.toggle("Grogan's Point Tennis")

        let reread = FavoritesStore(defaults: suite.defaults)

        #expect(reread.contains("Harper's Landing Tennis Court"))
        #expect(reread.contains("Grogan's Point Tennis"))

        // U+0027 APOSTROPHE, the character the capture actually contains.
        let stored = try #require(reread.facilityNames.first { $0.hasPrefix("Harper") })
        #expect(stored.contains("\u{0027}"))
        #expect(stored.contains("\u{2019}") == false)
    }

    // MARK: - Surviving a bad read

    /// Constructing a store is a read, and a read must not write.
    ///
    /// This is not tidiness. Under `@Observable` a stored property becomes a
    /// computed one, so an observer on the selection fires while `init` is
    /// assigning the loaded value — turning every launch into a write. The
    /// test below shows what that would cost.
    @Test("Constructing a store writes nothing")
    func loadingDoesNotWrite() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        _ = FavoritesStore(defaults: suite.defaults)

        #expect(
            suite.storedBytes == nil,
            """
            Building a store wrote to disk. Loading is a read; if it also \
            writes, then a stored value this version cannot decode is replaced \
            on launch by whatever this version decided it meant.
            """)
    }

    /// The cost of a writing read, stated as a behavior.
    ///
    /// Bytes this version cannot decode may still be meaningful — written by a
    /// newer build the user downgraded from, or by a format a later migration
    /// would know how to read. Overwriting them yields exactly the silent,
    /// unrecoverable loss that keeping unmatched favorites is meant to avoid.
    @Test("An undecodable stored value is left alone rather than overwritten")
    func aBadReadDoesNotDestroyWhatItCouldNotRead() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        let unreadable = Data(#"{"version":2,"names":["Shadowbend Tennis"]}"#.utf8)
        suite.defaults.set(unreadable, forKey: storageKey)

        let store = FavoritesStore(defaults: suite.defaults)

        #expect(store.facilityNames.isEmpty)
        #expect(
            suite.storedBytes == unreadable,
            "The stored value was replaced by a read that failed to understand it")
    }

    /// A crash on launch is unrecoverable without deleting the app. Losing the
    /// selection is two taps. The store must always choose the second.
    @Test("Garbage bytes under the key yield no favorites rather than a crash")
    func garbageDecodesToEmpty() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        suite.defaults.set(Data([0xFF, 0x00, 0x11, 0xA0, 0x7B]), forKey: storageKey)

        #expect(FavoritesStore(defaults: suite.defaults).facilityNames.isEmpty)
    }

    @Test("A wrong-shaped stored value yields no favorites rather than a crash")
    func wrongShapeDecodesToEmpty() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        // Valid JSON, wrong container — what an older or newer format could
        // plausibly have written.
        suite.defaults.set(
            Data(#"{"Shadowbend Tennis": true}"#.utf8), forKey: storageKey)

        #expect(FavoritesStore(defaults: suite.defaults).facilityNames.isEmpty)
    }

    @Test("A value of the wrong type entirely yields no favorites")
    func wrongTypeDecodesToEmpty() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        // Not `Data` at all. `data(forKey:)` returns nil for this.
        suite.defaults.set("Shadowbend Tennis", forKey: storageKey)

        #expect(FavoritesStore(defaults: suite.defaults).facilityNames.isEmpty)
    }

    @Test("A bad read still allows a new favorite to be saved")
    func recoversFromABadRead() throws {
        let suite = try IsolatedDefaults()
        defer { suite.discard() }

        suite.defaults.set(Data([0xFF, 0x00]), forKey: storageKey)

        let store = FavoritesStore(defaults: suite.defaults)
        store.toggle("Cattail Tennis")

        #expect(FavoritesStore(defaults: suite.defaults).facilityNames == ["Cattail Tennis"])
    }

    // MARK: - Isolation

    @Test("Two suites do not see each other's favorites")
    func suitesAreIsolated() throws {
        let one = try IsolatedDefaults()
        defer { one.discard() }
        let other = try IsolatedDefaults()
        defer { other.discard() }

        FavoritesStore(defaults: one.defaults).toggle("Tupelo Tennis")

        #expect(FavoritesStore(defaults: other.defaults).facilityNames.isEmpty)
        #expect(other.storedBytes == nil)
    }
}
