//
//  FacilitySearchTests.swift
//  CourtWatchTests
//
//  The apostrophe is the whole reason this file exists.
//
//  `localizedStandardContains` is the API Apple recommends for user-facing
//  search, and measured against this data it returns **false** for the
//  apostrophe the iOS keyboard actually inserts. Smart punctuation substitutes
//  U+2019 RIGHT SINGLE QUOTATION MARK when the user types `'`; the stored name
//  contains U+0027 APOSTROPHE. A user typing "Harper's" gets an empty list for
//  a place visible one scroll away, with no error and nothing to suggest the
//  app is not simply missing it.
//
//  All 27 names in the capture are pure ASCII, so the hazard is entirely on the
//  input side. The U+2019 case below is therefore written as an explicit
//  `\u{2019}` escape rather than a pasted character — an editor that
//  normalizes quotes would otherwise silently turn the failing case into the
//  passing one, and the test would go on reporting success while covering
//  nothing.
//
//  The negative cases are not padding. A fold that matched everything would
//  pass every positive assertion in this file.
//

import Foundation
import Testing

@testable import CourtWatch

/// Query cases, on a `nonisolated` type so they can feed `arguments:`, which
/// is evaluated outside the enclosing actor.
private nonisolated enum SearchCase {

    static let harpers = "Harper's Landing Tennis Court"
    static let grogans = "Grogan's Point Tennis"
    static let shadowbend = "Shadowbend Tennis"
    static let bearBranch = "Bear Branch Tennis"
    static let wendtwoods = "WendtwoodsTennis"

    /// query, name, whether it should match.
    static let cases: [(String, String, Bool)] = [
        // Ordinary substring matching.
        ("shadow", shadowbend, true),
        ("SHADOW", shadowbend, true),
        ("Shadowbend Tennis", shadowbend, true),
        ("  bear  ", bearBranch, true),
        ("branch", bearBranch, true),

        // No internal space in the stored name.
        ("wendtwoods", wendtwoods, true),
        ("wendtwoodstennis", wendtwoods, true),

        // The apostrophe, in all three forms a person can produce.
        // U+2019 is what the software keyboard inserts.
        ("Harper\u{2019}s", harpers, true),
        ("harper\u{2019}s landing", harpers, true),
        ("harper\u{0027}s", harpers, true),
        ("HARPER\u{0027}S", harpers, true),
        ("harpers", harpers, true),
        ("harpers landing", harpers, true),

        // The second apostrophe facility. One test covering only Harper's
        // would miss half the class.
        ("grogans", grogans, true),
        ("grogan\u{2019}s", grogans, true),
        ("grogan\u{0027}s point", grogans, true),

        // Other apostrophe variants keyboards and paste buffers produce.
        ("harper\u{2018}s", harpers, true),
        ("harper\u{02BC}s", harpers, true),
        ("harper\u{FF07}s", harpers, true),
        ("harper\u{0060}s", harpers, true),

        // Negatives. Without these the positives mean nothing.
        ("zzz", shadowbend, false),
        ("zzz", harpers, false),
        ("harpers", grogans, false),
        ("grogans", harpers, false),
        ("shadow", bearBranch, false),
        ("landing", grogans, false),
    ]

    /// Whitespace-only queries. An empty search field must show everything,
    /// not nothing.
    static let emptyQueries = ["", " ", "   ", "\t", "\n", "  \t \n "]
}

private func capturedFacilityNames() throws -> [String] {
    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self, from: try Fixture.data(Fixture.anonymous))
    return Availability(envelope: envelope).facilities.map(\.name)
}

struct FacilitySearchTests {

    @Test("A query matches a facility name, or does not", arguments: SearchCase.cases)
    func matchesAsExpected(query: String, name: String, expected: Bool) {
        #expect(
            FacilitySearch.matches(facility: name, query: query) == expected,
            """
            "\(query)" against "\(name)" should be \(expected).
            Query key:  "\(FacilitySearch.key(query))"
            Name key:   "\(FacilitySearch.key(name))"
            """)
    }

    @Test("An empty or whitespace-only query matches everything", arguments: SearchCase.emptyQueries)
    func emptyQueryMatchesEverything(query: String) throws {
        for name in try capturedFacilityNames() {
            #expect(
                FacilitySearch.matches(facility: name, query: query),
                "\"\(query)\" should have matched \(name)")
        }
    }

    /// The measured failure, stated on its own so a regression names itself.
    @Test("The keyboard's own apostrophe matches the stored ASCII one")
    func theSmartQuoteMatches() {
        // U+2019 RIGHT SINGLE QUOTATION MARK — what iOS smart punctuation
        // inserts. U+0027 APOSTROPHE is what the capture contains.
        let typed = "Harper\u{2019}s"
        let stored = "Harper\u{0027}s Landing Tennis Court"

        #expect(typed.contains("\u{2019}"))
        #expect(stored.contains("\u{0027}"))

        // The idiomatic API, on its own, gets this wrong. That is not asserted
        // as a requirement — it is recorded so the next reader knows why this
        // module exists rather than a one-line call.
        #expect(stored.localizedStandardContains(typed) == false)

        // Through the fold, it is right.
        #expect(FacilitySearch.matches(facility: stored, query: typed))
    }

    /// The failure this design defends against is asymmetry — folding the
    /// query but not the name, which produces a search correct for 25 of 27
    /// facilities and convincing in review.
    @Test("The fold is applied to both sides")
    func theFoldIsSymmetric() {
        let stored = "Harper\u{2019}s Landing Tennis Court"

        #expect(FacilitySearch.matches(facility: stored, query: "harper\u{0027}s"))
        #expect(FacilitySearch.matches(facility: stored, query: "harpers"))
        #expect(FacilitySearch.key(stored) == FacilitySearch.key("Harper's Landing Tennis Court"))
    }

    /// Dropping apostrophes could in principle make two real places
    /// indistinguishable and let a search select the wrong one.
    @Test("The 27 real names fold to 27 distinct keys")
    func theFoldMergesNothing() throws {
        let names = try capturedFacilityNames()
        #expect(names.count == 27)

        let keys = names.map { FacilitySearch.key($0) }

        #expect(
            Set(keys).count == names.count,
            """
            The fold merged two facilities. Duplicated keys: \
            \(Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted())
            """)
    }

    /// A fold that returned a constant would satisfy every positive case in
    /// this file. This is what rules that out at the level of the real data.
    @Test("A query narrows the list rather than matching all of it")
    func searchActuallyNarrows() throws {
        let names = try capturedFacilityNames()

        let endingInTennisCourt = names.filter {
            FacilitySearch.matches(facility: $0, query: "tennis court")
        }

        #expect(endingInTennisCourt.count == 6)
        #expect(endingInTennisCourt.contains("Timarron Tennis Court"))
        #expect(endingInTennisCourt.contains("Harper's Landing Tennis Court"))
        #expect(endingInTennisCourt.contains("Shadowbend Tennis") == false)

        #expect(names.filter { FacilitySearch.matches(facility: $0, query: "zzz") }.isEmpty)
        #expect(names.filter { FacilitySearch.matches(facility: $0, query: "harper") }.count == 1)
    }

    /// Diacritic insensitivity is free with `localizedStandardContains` and no
    /// name in the capture exercises it. Asserted anyway, so that a future fold
    /// written by hand does not quietly lose it.
    @Test("Diacritics fold, though nothing in the real data has one")
    func diacriticsFold() {
        #expect(FacilitySearch.matches(facility: "Caf\u{00E9} Tennis", query: "cafe"))
        #expect(FacilitySearch.matches(facility: "Caf\u{00E9} Tennis", query: "caf\u{00E9}"))
    }

    @Test("Folding is idempotent")
    func foldingIsIdempotent() throws {
        for name in try capturedFacilityNames() {
            let once = FacilitySearch.key(name)
            #expect(FacilitySearch.key(once) == once)
        }
    }
}
