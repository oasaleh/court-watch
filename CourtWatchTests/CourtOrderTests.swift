//
//  CourtOrderTests.swift
//  CourtWatchTests
//
//  Courts must read the way people count them.
//
//  Phase 2 sorted courts lexically and said so in a comment: stable and
//  predictable, with presentation ordering left to the phase that draws them.
//  With eleven courts at Bear Branch that deferral has come due — lexically the
//  rows read 1, 10, 11, 2, and on a screen showing every court at once that is
//  the first thing a user sees.
//
//  The assertions with teeth here are the scrambled-input one and the
//  capture-wide invariant. Sorting an already-sorted list proves nothing: it
//  passes against a sort that does nothing at all. And a handful of named cases
//  would miss a regression at whichever facility nobody thought to write down.
//

import Foundation
import Testing

@testable import CourtWatch

/// Argument lists for parameterized tests live on a `nonisolated` type.
///
/// The `arguments:` collection is evaluated outside the enclosing actor, and
/// this module's default isolation makes a plain file-scope `let`
/// main-actor-isolated — which cannot be used as `arguments:` at all.
nonisolated enum CourtNumberCases {

    /// A court name against the number the app should read off the end of it,
    /// or `nil` for "this name carries no court number".
    static let all: [(String, Int?)] = [
        // The ordinary shape, single and multi-digit.
        ("Bear Branch Tennis 1", 1),
        ("Bear Branch Tennis 9", 9),
        ("Bear Branch Tennis 10", 10),
        ("Bear Branch Tennis 11", 11),

        // The hash form. Timarron is the only facility that uses it and it
        // means exactly what a bare number means elsewhere.
        ("Timarron Tennis Court #1", 1),
        ("Timarron Tennis Court #2", 2),

        // Irregular names that are still ordinarily numbered.
        ("WendtwoodsTennis 4", 4),
        ("Harper's Landing Tennis Court 2", 2),

        // A hash with no digits behind it. The degenerate case: this must read
        // as unnumbered rather than as zero, and above all must not crash.
        ("Some Tennis #", nil),
        ("A #", nil),
        ("#", nil),

        // No trailing number at all.
        ("Shadowbend Tennis", nil),
        ("Avalon Tennis Court", nil),

        // A number that is not the last token is not a court number.
        ("Court 1 Tennis", nil),

        // A name that is only a court number still has one.
        ("7", 7),

        // Mixed tokens are not numbers. A partial parse here would order
        // "Tennis 1a" as court 1 and hide the fact that it is not one.
        ("Tennis 1a", nil),
        ("Tennis #12a", nil),
        ("Tennis a1", nil),

        // Nothing to read.
        ("", nil),
        ("   ", nil),
    ]
}

/// A court with only the fields ordering depends on.
///
/// Built by hand rather than loaded, because the degenerate names below appear
/// in no capture and could not otherwise be exercised at all.
///
/// `facility` is separate from the name on purpose. Grouping keys on the
/// derived facility name, and a name with no trailing number derives to itself
/// — so `Some Tennis Alpha` and `Some Tennis 2` would land in two different
/// facilities and never be compared with each other. Naming the facility
/// explicitly is what puts the degenerate cases in one list where the ordering
/// rule can be seen doing its work.
private func court(_ name: String, id: Int = 0, facility: String? = nil) -> Court {
    Court(
        id: id,
        name: name,
        facilityName: facility ?? FacilityName.derive(from: name),
        slots: [],
        warnings: []
    )
}

private func groupedFixture(_ fixture: String) throws -> [Facility] {
    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self, from: try Fixture.data(fixture))
    return Availability(envelope: envelope).facilities
}

private func courtNames(of facilityName: String, in facilities: [Facility]) throws -> [String] {
    try #require(
        facilities.first { $0.name == facilityName },
        "No facility named \(facilityName)"
    ).courts.map(\.name)
}

struct CourtOrderTests {

    @Test("A court number is read off the end of the name", arguments: CourtNumberCases.all)
    func parsesCourtNumber(name: String, expected: Int?) {
        #expect(CourtNumber.parse(from: name) == expected)
    }

    @Test("Bear Branch's eleven courts read one through eleven")
    func ordersBearBranchNumerically() throws {
        let names = try courtNames(of: "Bear Branch Tennis", in: try groupedFixture(Fixture.anonymous))

        #expect(names.count == 11)
        #expect(
            names == [
                "Bear Branch Tennis 1",
                "Bear Branch Tennis 2",
                "Bear Branch Tennis 3",
                "Bear Branch Tennis 4",
                "Bear Branch Tennis 5",
                "Bear Branch Tennis 6",
                "Bear Branch Tennis 7",
                "Bear Branch Tennis 8",
                "Bear Branch Tennis 9",
                "Bear Branch Tennis 10",
                "Bear Branch Tennis 11",
            ])
    }

    /// The assertion that proves the sort is doing work.
    ///
    /// Feeding sorted input to a sort and getting sorted output back is true of
    /// a function that returns its argument. The permutation is written out
    /// rather than randomised so that a failure is reproducible rather than
    /// something that shows up one run in eleven.
    @Test("The same eleven courts scrambled still come out in numeric order")
    func ordersFromAnyPermutation() {
        let scrambled = [11, 3, 7, 1, 10, 5, 2, 9, 4, 8, 6]
            .map { court("Bear Branch Tennis \($0)", id: $0) }

        let ordered = Facility.group(scrambled)

        #expect(ordered.count == 1)
        #expect(ordered.first?.courts.map(\.id) == Array(1...11))
    }

    /// The reverse permutation as well, because a sort that merely reversed its
    /// input would satisfy exactly one of these two.
    @Test("Reversed input comes out in numeric order too")
    func ordersFromReversedInput() {
        let reversed = (1...11).reversed().map { court("Bear Branch Tennis \($0)", id: $0) }

        #expect(Facility.group(reversed).first?.courts.map(\.id) == Array(1...11))
    }

    @Test("Timarron's hash-numbered pair keeps its order")
    func preservesTimarronOrder() throws {
        let names = try courtNames(
            of: "Timarron Tennis Court", in: try groupedFixture(Fixture.anonymous))

        #expect(names == ["Timarron Tennis Court #1", "Timarron Tennis Court #2"])
    }

    /// Numbered first, then unnumbered — and among the unnumbered, plain `<`.
    ///
    /// The alternative, treating an unnumbered name as court zero, would put it
    /// ahead of court 1 and make a malformed name the first row on screen.
    @Test("Unnumbered courts sort after numbered ones, and among themselves by name")
    func placesUnnumberedCourtsLast() {
        let mixed = [
            court("Some Tennis Zulu", facility: "Some Tennis"),
            court("Some Tennis 10", facility: "Some Tennis"),
            court("Some Tennis Alpha", facility: "Some Tennis"),
            court("Some Tennis 2", facility: "Some Tennis"),
            court("Some Tennis #", facility: "Some Tennis"),
        ]

        #expect(
            Facility.group(mixed).first?.courts.map(\.name) == [
                "Some Tennis 2",
                "Some Tennis 10",
                "Some Tennis #",
                "Some Tennis Alpha",
                "Some Tennis Zulu",
            ])
    }

    /// A court named only "7" has no facility to fall back to and keeps itself,
    /// which `FacilityName.derive` already guarantees. Ordering must not undo
    /// that by losing the name on the way through.
    @Test("A court whose whole name is a number keeps its name")
    func keepsNumberOnlyName() {
        let facilities = Facility.group([court("7", id: 7), court("3", id: 3)])

        #expect(facilities.map(\.name) == ["3", "7"])
        #expect(facilities.flatMap { $0.courts.map(\.name) } == ["3", "7"])
    }

    /// The invariant that covers the facilities no case above names.
    ///
    /// A per-facility list of expected orders would go stale the moment the
    /// Township added a court. This holds for every facility in the capture,
    /// including any added later.
    @Test("Every facility in the capture has courts in non-decreasing numeric order")
    func ordersEveryFacilityNumerically() throws {
        for facility in try groupedFixture(Fixture.anonymous) {
            let numbers = facility.courts.map { CourtNumber.parse(from: $0.name) }

            #expect(
                numbers.allSatisfy { $0 != nil },
                "\(facility.name) has a court with no readable number: \(facility.courts.map(\.name))"
            )

            let readable = numbers.compactMap { $0 }
            #expect(
                readable == readable.sorted(),
                "\(facility.name) is out of order: \(facility.courts.map(\.name))"
            )
        }
    }

    /// Facility-level ordering is untouched by this change. Asserted here as
    /// well as in the grouping suite because the two sorts sit in the same
    /// function and an edit to one can reach the other.
    @Test("Facilities are still ordered by name")
    func leavesFacilityOrderAlone() throws {
        let names = try groupedFixture(Fixture.anonymous).map(\.name)

        #expect(names == names.sorted())
    }

    @Test("Grouping still covers twenty-seven facilities and eighty courts")
    func leavesGroupingIntact() throws {
        let facilities = try groupedFixture(Fixture.anonymous)
        let courts = facilities.flatMap(\.courts)

        #expect(facilities.count == 27)
        #expect(courts.count == 80)
        #expect(Set(courts.map(\.id)).count == 80)
    }

    /// Both captures must order alike, or the two would compare unequal and the
    /// grouping suite's cross-capture assertion would start failing for a
    /// reason that has nothing to do with grouping.
    @Test("Both captures order identically")
    func ordersBothCapturesAlike() throws {
        let anonymous = try groupedFixture(Fixture.anonymous)
        let loggedIn = try groupedFixture(Fixture.loggedIn)

        #expect(anonymous.flatMap { $0.courts.map(\.name) } == loggedIn.flatMap { $0.courts.map(\.name) })
    }
}
