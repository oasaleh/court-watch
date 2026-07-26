//
//  FavoriteResolutionTests.swift
//  CourtWatchTests
//
//  The orphan policy, asserted as a value rather than as the absence of a
//  mutation.
//
//  "The favorite is still saved but not shown" is close to untestable when it
//  is expressed as code that does not run. Returning `unmatched` turns it into
//  something a test can hold: the name is reported, it is not rendered, and it
//  is still exactly where it was. The self-healing pair below — unmatched
//  against one list, matched against the next — is the behavioural difference
//  between retaining a favorite and pruning it, and it is the reason this file
//  exists.
//

import Foundation
import Testing

@testable import CourtWatch

/// Hand-made facilities for the cases the capture cannot express.
///
/// On a `nonisolated` type rather than at file scope: a parameterized test
/// evaluates its `arguments:` outside the enclosing actor, and under this
/// module's default isolation a file-scope `let` is main-actor-isolated and
/// cannot be used there.
private nonisolated enum Sample {

    static func facility(_ name: String, courts: Int = 2) -> Facility {
        Facility(
            name: name,
            courts: (1...courts).map { number in
                Court(
                    id: number,
                    name: "\(name) \(number)",
                    facilityName: name,
                    slots: [],
                    warnings: [])
            })
    }

    static let shadowbend = facility("Shadowbend Tennis", courts: 5)
    static let bearBranch = facility("Bear Branch Tennis", courts: 11)
    static let harpers = facility("Harper's Landing Tennis Court")

    /// Strings that are *nearly* "Shadowbend Tennis" and must not resolve to
    /// it. Search is forgiving because a human is typing; resolution is not,
    /// because it compares a saved key against a derived one and a near miss
    /// would show the user courts they never chose.
    static let nearMisses = [
        "shadowbend tennis",
        "SHADOWBEND TENNIS",
        " Shadowbend Tennis ",
        "Shadowbend Tennis ",
        "Shadowbend",
        "Shadowbend Tennis 1",
        "ShadowbendTennis",
    ]
}

private func capturedFacilities() throws -> [Facility] {
    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self, from: try Fixture.data(Fixture.anonymous))
    return Availability(envelope: envelope).facilities
}

struct FavoriteResolutionTests {

    // MARK: - Matching

    @Test("Favorites the response mentions all resolve, with nothing left over")
    func everythingPresentResolves() {
        let facilities = [Sample.bearBranch, Sample.harpers, Sample.shadowbend]

        let resolved = FavoriteResolution.resolve(
            favorites: ["Shadowbend Tennis", "Bear Branch Tennis"],
            against: facilities)

        #expect(resolved.matched.map(\.id) == ["Bear Branch Tennis", "Shadowbend Tennis"])
        #expect(resolved.unmatched.isEmpty)
    }

    /// The order comes from the facility list, not from the favorites set.
    ///
    /// Iterating the set instead would produce a different order on every
    /// launch — the same randomized hashing that makes a `Set` impossible to
    /// pin on disk — and the sections would visibly reshuffle between runs.
    @Test("Matched facilities keep the order of the list they were matched against")
    func matchedFollowsTheFacilityListOrder() {
        let facilities = [
            Sample.facility("Zebra Tennis"),
            Sample.facility("Alpha Tennis"),
            Sample.facility("Middle Tennis"),
        ]

        let resolved = FavoriteResolution.resolve(
            favorites: ["Alpha Tennis", "Middle Tennis", "Zebra Tennis"],
            against: facilities)

        #expect(resolved.matched.map(\.id) == ["Zebra Tennis", "Alpha Tennis", "Middle Tennis"])
    }

    @Test("An empty favorites set resolves to nothing at all")
    func nothingChosenResolvesToNothing() {
        let resolved = FavoriteResolution.resolve(
            favorites: [], against: [Sample.shadowbend, Sample.bearBranch])

        #expect(resolved.matched.isEmpty)
        #expect(resolved.unmatched.isEmpty)
    }

    @Test("Resolving against no facilities leaves every favorite unmatched")
    func anEmptyResponseMatchesNothing() {
        let resolved = FavoriteResolution.resolve(
            favorites: ["Shadowbend Tennis", "Bear Branch Tennis"], against: [])

        #expect(resolved.matched.isEmpty)
        #expect(resolved.unmatched == ["Bear Branch Tennis", "Shadowbend Tennis"])
    }

    @Test("The real capture resolves three known favorites and nothing else")
    func theCaptureResolvesKnownFavorites() throws {
        let facilities = try capturedFacilities()
        #expect(facilities.count == 27)

        let resolved = FavoriteResolution.resolve(
            favorites: [
                "Shadowbend Tennis", "Bear Branch Tennis", "Harper's Landing Tennis Court",
            ],
            against: facilities)

        #expect(
            resolved.matched.map(\.id) == [
                "Bear Branch Tennis", "Harper's Landing Tennis Court", "Shadowbend Tennis",
            ])
        #expect(resolved.unmatched.isEmpty)

        // FAC-02, at the level this phase owns: every court, not a sample.
        #expect(resolved.matched.first { $0.id == "Shadowbend Tennis" }?.courts.count == 5)
        #expect(resolved.matched.first { $0.id == "Bear Branch Tennis" }?.courts.count == 11)
    }

    // MARK: - Exactness

    /// Resolution and search are deliberately different operations. This is the
    /// assertion that keeps them different.
    @Test("A near miss does not resolve", arguments: Sample.nearMisses)
    func matchingIsExact(nearMiss: String) {
        let resolved = FavoriteResolution.resolve(
            favorites: [nearMiss], against: [Sample.shadowbend])

        #expect(resolved.matched.isEmpty, "\"\(nearMiss)\" should not resolve to Shadowbend Tennis")
        #expect(resolved.unmatched == [nearMiss])
    }

    /// The same string the search fold is built to accept must still fail here.
    @Test("Search-style input does not resolve even though search would match it")
    func searchInputDoesNotResolve() throws {
        let facilities = try capturedFacilities()

        let resolved = FavoriteResolution.resolve(
            favorites: ["harpers landing tennis court"], against: facilities)

        #expect(resolved.matched.isEmpty)
        #expect(resolved.unmatched == ["harpers landing tennis court"])
    }

    @Test("Favorites match on the facility id, which is the derived name")
    func matchesOnFacilityID() throws {
        let facilities = try capturedFacilities()
        let harpers = try #require(facilities.first { $0.name.hasPrefix("Harper") })

        let resolved = FavoriteResolution.resolve(favorites: [harpers.id], against: facilities)

        #expect(resolved.matched.map(\.id) == [harpers.id])
    }

    // MARK: - Retention

    /// The central decision of the phase, stated as behavior.
    @Test("A favorite the response does not mention is reported, not dropped")
    func anAbsentFavoriteIsReportedUnmatched() {
        let resolved = FavoriteResolution.resolve(
            favorites: ["Shadowbend Tennis", "Renamed Away Tennis"],
            against: [Sample.shadowbend])

        #expect(resolved.matched.map(\.id) == ["Shadowbend Tennis"])
        #expect(resolved.unmatched == ["Renamed Away Tennis"])
    }

    /// Self-healing: the property that makes retention free rather than merely
    /// cautious. Pruning would make the second half of this test impossible.
    @Test("A favorite that stopped matching matches again when the name returns")
    func aRetainedFavoriteHealsItself() {
        let favorites: Set<String> = ["Shadowbend Tennis", "Sawmill Tennis"]

        let duringTheOutage = FavoriteResolution.resolve(
            favorites: favorites, against: [Sample.shadowbend])

        #expect(duringTheOutage.matched.map(\.id) == ["Shadowbend Tennis"])
        #expect(duringTheOutage.unmatched == ["Sawmill Tennis"])

        // The same favorites, unchanged, against a response that mentions it
        // again. No user action in between.
        let afterwards = FavoriteResolution.resolve(
            favorites: favorites,
            against: [Sample.facility("Sawmill Tennis", courts: 5), Sample.shadowbend])

        #expect(afterwards.matched.map(\.id) == ["Sawmill Tennis", "Shadowbend Tennis"])
        #expect(afterwards.unmatched.isEmpty)
    }

    @Test("Unmatched names come back in a stable order")
    func unmatchedIsSorted() {
        let resolved = FavoriteResolution.resolve(
            favorites: ["Zebra Tennis", "Alpha Tennis", "Middle Tennis"], against: [])

        #expect(resolved.unmatched == ["Alpha Tennis", "Middle Tennis", "Zebra Tennis"])
    }

    /// Resolution returns; it does not reach back into storage.
    ///
    /// The store has no facility list and so cannot prune. This is the mirror
    /// of that: resolving does not touch what is saved, so a response arriving
    /// mid-session cannot quietly edit the user's selection.
    @Test("Resolving leaves the saved selection exactly as it was")
    func resolvingChangesNothing() throws {
        let suiteName = "com.courtwatch.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FavoritesStore(defaults: defaults)
        store.toggle("Shadowbend Tennis")
        store.toggle("Renamed Away Tennis")

        let before = store.facilityNames

        let resolved = FavoriteResolution.resolve(
            favorites: store.facilityNames, against: [Sample.shadowbend])

        #expect(resolved.unmatched == ["Renamed Away Tennis"])
        #expect(store.facilityNames == before)

        // And still on disk, which is the promise that matters after a
        // relaunch rather than during this session.
        #expect(
            FavoritesStore(defaults: defaults).contains("Renamed Away Tennis"),
            "The unmatched favorite was dropped from storage")
    }
}
