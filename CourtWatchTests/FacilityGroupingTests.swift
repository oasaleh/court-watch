//
//  FacilityGroupingTests.swift
//  CourtWatchTests
//
//  The highest-value test in the phase.
//
//  The API returns only court names. "Shadowbend" as a place the user chooses
//  to play does not exist in the payload at all — it is inferred, here, by
//  stripping a trailing court number. That inference is load-bearing twice
//  over: Phase 3 persists favorites keyed by the derived string, so a change in
//  this rule silently orphans a user's saved favorites, and Phase 4 renders one
//  section per facility.
//
//  Note on the expected count: research §8 asserts 28 facilities. That number
//  comes from a rule that strips bare trailing digits only, which contradicts
//  the derivation function in research §4 of the same document and leaves
//  Timarron Tennis Court #1 and #2 as two single-court facilities. Measured
//  against the capture, §4's rule yields 27 and §8's yields 28. 27 is correct
//  for this app, and the Timarron case below records why.
//

import Foundation
import Testing

@testable import CourtWatch

/// The 27 facilities, written out rather than computed.
///
/// A test that derives its expectation from the same fixture it is checking
/// asserts only that the function is deterministic. This list was read off the
/// capture once, by hand, and is what the app claims The Woodlands has.
private let expectedFacilities: Set<String> = [
    "Alden Bridge Tennis",
    "Avalon Tennis Court",
    "Bear Branch Tennis",
    "Capstone Tennis",
    "Cattail Tennis",
    "Coppersage Tennis",
    "Cranebrook Tennis",
    "Creekwood Tennis",
    "Falconwing Tennis",
    "Forestgate Tennis Court",
    "Grogan's Point Tennis",
    "Harper's Landing Tennis Court",
    "Lakeside Tennis",
    "May Valley Tennis",
    "Meadowlake Tennis",
    "Mystic Forest Tennis Court",
    "Pepperdale Tennis",
    "Ridgewood Tennis",
    "Sawmill Tennis",
    "Shadowbend Tennis",
    "Sundance Tennis",
    "Tamarac Tennis Court",
    "Terramont Tennis",
    "Timarron Tennis Court",
    "Tupelo Tennis",
    "WendtwoodsTennis",
    "Windvale Tennis",
]

private func groupedFixture(_ fixture: String) throws -> [Facility] {
    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self, from: try Fixture.data(fixture))
    return Availability(envelope: envelope).facilities
}

/// Strips a trailing court number independently of the production rule.
///
/// Deliberately a second implementation. The no-silent-merge check below
/// compares facility names against this, so calling `FacilityName.derive`
/// there would make the assertion compare the function with itself.
private func strippingTrailingNumber(_ name: String) -> String {
    name.replacing(/\ #?[0-9]+$/, with: "")
}

struct FacilityGroupingTests {

    @Test(
        "A trailing court number is stripped to leave the facility",
        arguments: [
            ("Shadowbend Tennis 3", "Shadowbend Tennis"),

            // Multi-digit, not merely single. A rule matching one digit would
            // split Bear Branch into "Bear Branch Tennis" and
            // "Bear Branch Tennis 1".
            ("Bear Branch Tennis 10", "Bear Branch Tennis"),
            ("Bear Branch Tennis 11", "Bear Branch Tennis"),

            // The one genuinely irregular name in the capture. "#1" reads as
            // "court #1 at Timarron Tennis Court" — the same meaning as
            // "Cattail Tennis 1", just punctuated differently. Leaving the two
            // split would put "Timarron Tennis Court #1" and "#2" in the
            // facility picker, which is court numbers in a list FAC-01 says
            // must show facility names only.
            ("Timarron Tennis Court #1", "Timarron Tennis Court"),
            ("Timarron Tennis Court #2", "Timarron Tennis Court"),

            // The missing space is inside the name, before the court number.
            // Not a hard case for a trailing-number rule; a hard case for any
            // rule that tries to find the word "Tennis" or split on a fixed
            // field count.
            ("WendtwoodsTennis 1", "WendtwoodsTennis"),
            ("WendtwoodsTennis 4", "WendtwoodsTennis"),

            // Apostrophes survive.
            ("Harper's Landing Tennis Court 2", "Harper's Landing Tennis Court"),
            ("Grogan's Point Tennis 1", "Grogan's Point Tennis"),

            // Several facilities end "Tennis Court" rather than "Tennis". The
            // suffix is part of the name and must not be stripped with the
            // number.
            ("Avalon Tennis Court 1", "Avalon Tennis Court"),
            ("Tamarac Tennis Court 2", "Tamarac Tennis Court"),
            ("Mystic Forest Tennis Court 1", "Mystic Forest Tennis Court"),
            ("Forestgate Tennis Court 2", "Forestgate Tennis Court"),
        ]
    )
    func derivesFacilityName(input: String, expected: String) {
        #expect(FacilityName.derive(from: input) == expected)
    }

    @Test("A name with no trailing number is left alone")
    func leavesUnnumberedNames() {
        #expect(FacilityName.derive(from: "Shadowbend Tennis") == "Shadowbend Tennis")
        #expect(FacilityName.derive(from: "Avalon Tennis Court") == "Avalon Tennis Court")
    }

    /// Both conditions in the rule are load-bearing. Without the digit
    /// requirement a name ending in a bare "#" would lose its last token;
    /// without the "#" tolerance Timarron splits in two.
    @Test("A trailing token with no digit is not a court number")
    func requiresADigit() {
        #expect(FacilityName.derive(from: "Some Tennis #") == "Some Tennis #")
        #expect(FacilityName.derive(from: "Court 1 Tennis") == "Court 1 Tennis")
    }

    @Test("An empty or whitespace name does not crash")
    func handlesEmptyName() {
        #expect(FacilityName.derive(from: "") == "")
        #expect(FacilityName.derive(from: "   ") == "")
        #expect(FacilityName.derive(from: "7") == "7")
    }

    @Test("The capture groups into exactly twenty-seven facilities")
    func groupsIntoTwentySeven() throws {
        #expect(try groupedFixture(Fixture.anonymous).count == 27)
    }

    /// Set equality both ways, reporting which names moved rather than only
    /// that a count changed — a Township rename should say what it renamed.
    @Test("The derived facilities are exactly the expected set")
    func matchesExpectedSet() throws {
        let derived = Set(try groupedFixture(Fixture.anonymous).map(\.name))

        #expect(
            derived == expectedFacilities,
            """
            unexpected: \(derived.subtracting(expectedFacilities).sorted())
            missing: \(expectedFacilities.subtracting(derived).sorted())
            """
        )
    }

    /// Asserted separately from the facility count on purpose. A rule that
    /// merged two facilities would still total 80 courts, and a rule that
    /// orphaned one would still produce 27 names, so neither assertion alone
    /// catches both failure modes.
    @Test("Every court lands in exactly one facility")
    func reconcilesToEightyCourts() throws {
        let facilities = try groupedFixture(Fixture.anonymous)
        let courts = facilities.flatMap(\.courts)

        #expect(courts.count == 80)
        #expect(Set(courts.map(\.id)).count == 80)
    }

    @Test("Court counts per facility match the capture")
    func matchesCourtDistribution() throws {
        let byName = Dictionary(
            uniqueKeysWithValues: try groupedFixture(Fixture.anonymous).map {
                ($0.name, $0.courts.count)
            })

        #expect(byName["Bear Branch Tennis"] == 11)
        #expect(byName["Sawmill Tennis"] == 5)
        #expect(byName["Shadowbend Tennis"] == 5)
        #expect(byName["Alden Bridge Tennis"] == 4)
        #expect(byName["WendtwoodsTennis"] == 4)
        #expect(byName["Creekwood Tennis"] == 3)
        #expect(byName["Timarron Tennis Court"] == 2)
        #expect(byName.values.reduce(0, +) == 80)
    }

    /// Catches a future rule that over-strips — one that also removed the word
    /// "Court", say, folding Avalon Tennis Court into Avalon Tennis and
    /// quietly merging two real places into one entry.
    @Test("No facility silently absorbs courts from another")
    func doesNotSilentlyMerge() throws {
        for facility in try groupedFixture(Fixture.anonymous) {
            for court in facility.courts {
                #expect(
                    strippingTrailingNumber(court.name) == facility.name,
                    "\(court.name) does not belong under \(facility.name)"
                )
            }
        }
    }

    @Test("Timarron's two hash-numbered courts form one facility")
    func groupsTimarronAsOne() throws {
        let timarron = try #require(
            try groupedFixture(Fixture.anonymous).first { $0.name == "Timarron Tennis Court" })

        #expect(timarron.courts.count == 2)
        #expect(
            timarron.courts.map(\.name) == [
                "Timarron Tennis Court #1", "Timarron Tennis Court #2",
            ])
    }

    /// Phase 3's picker and every test here need a stable order, so it is fixed
    /// at the grouping boundary rather than left to whatever order the payload
    /// happened to arrive in.
    @Test("Facilities are ordered by name")
    func ordersFacilitiesDeterministically() throws {
        let names = try groupedFixture(Fixture.anonymous).map(\.name)

        #expect(names == names.sorted())
    }

    @Test("A facility's id is the string Phase 3 will persist")
    func exposesNameAsIdentity() throws {
        let facilities = try groupedFixture(Fixture.anonymous)

        #expect(facilities.allSatisfy { $0.id == $0.name })
    }

    @Test("The logged-in capture groups identically")
    func groupsBothCapturesAlike() throws {
        let anonymous = try groupedFixture(Fixture.anonymous)
        let loggedIn = try groupedFixture(Fixture.loggedIn)

        #expect(anonymous.map(\.name) == loggedIn.map(\.name))
        #expect(anonymous == loggedIn)
    }

    @Test("Each court knows the facility it was grouped under")
    func courtsCarryTheirFacilityName() throws {
        for facility in try groupedFixture(Fixture.anonymous) {
            #expect(facility.courts.allSatisfy { $0.facilityName == facility.name })
        }
    }
}
