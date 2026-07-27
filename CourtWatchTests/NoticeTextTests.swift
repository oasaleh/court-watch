//
//  NoticeTextTests.swift
//  CourtWatchTests
//
//  Three values were deliberately preserved by earlier phases and had nowhere
//  to be said: the favorites that no longer resolve (Phase 3), the courts whose
//  data was short or unreadable (Phase 2 and 5), and the per-court warnings
//  (Phase 3, dropped by Phase 4 as noise).
//
//  All three are silent in the captured data, which is the normal case and the
//  reason this is one small strip rather than a feature. So every case here is
//  hand-built, and the *empty* case is asserted first because it is the one the
//  user will actually live with.
//
//  The case worth being careful about is the negative one. The residency notice
//  every court repeats is suppressed by matching two stable fragments of it —
//  not by byte equality, because the day count inside it can change, and not by
//  one loose word, because over-matching would swallow a warning that mattered.
//  A closure notice quietly suppressed is the failure that costs the user
//  something, so both directions are asserted.
//

import Foundation
import Testing

@testable import CourtWatch

/// The exact warning all 80 courts carry, measured from both captures.
private let residencyNotice =
    "Non-residents cannot make reservations more than 2 day(s) in advance."

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum NoticeCases {

    /// The residency notice as the API might phrase it on any given day. The
    /// day count is a number that can change, so byte equality would let the
    /// notice through eighty times over the moment the Township edits it.
    static let residencyPhrasings = [
        "Non-residents cannot make reservations more than 2 day(s) in advance.",
        "Non-residents cannot make reservations more than 1 day(s) in advance.",
        "Non-residents cannot make reservations more than 14 day(s) in advance.",
        "Non-residents cannot make reservations more than 30 day(s) in advance.",
    ]

    /// Warnings a Township might plausibly send that must **not** be
    /// suppressed. Written as real sentences rather than nonsense strings,
    /// because the predicate has to survive real text.
    ///
    /// The first two are the dangerous ones: each shares one fragment with the
    /// residency notice, and a looser predicate would swallow both.
    static let mustSurvive = [
        "Non-residents must pay a surcharge at the gate.",
        "Please reserve in advance; walk-ups are not guaranteed.",
        "This facility is closed for maintenance today.",
        "Court 3 is resurfaced this week and unavailable.",
    ]
}

struct NoticeTextTests {

    // MARK: - The normal case

    /// The state both captures produce and the one the user lives with.
    @Test("With nothing wrong there are no notices at all")
    func saysNothingWhenThereIsNothingToSay() {
        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: [],
            unreadableCourts: 0,
            warnings: []
        )

        #expect(lines.isEmpty)
    }

    /// The captured data carries one warning on every court and nothing else
    /// wrong, and must still produce a silent strip.
    @Test("Eighty repetitions of the residency notice produce nothing")
    func capturedWarningsProduceNoNotices() {
        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: [],
            unreadableCourts: 0,
            warnings: Array(repeating: residencyNotice, count: 80)
        )

        #expect(lines.isEmpty)
    }

    // MARK: - Unmatched favorites

    /// The Phase 3 promise this value exists to keep is that the name is
    /// *kept*. A line implying it was lost would be worse than silence.
    @Test("A favorite the response never listed is named, and said to be still saved")
    func namesAnUnmatchedFavorite() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: ["Bear Branch Tennis"],
            degradedCourts: [],
            unreadableCourts: 0,
            warnings: []
        )

        let line = try #require(lines.first)

        #expect(lines.count == 1)
        #expect(line.contains("Bear Branch Tennis"))
        #expect(line.localizedCaseInsensitiveContains("saved"))
    }

    /// One line for the set, not one per name.
    @Test("Several unmatched favorites share one line")
    func joinsSeveralUnmatchedFavorites() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: ["Bear Branch Tennis", "Shadowbend Tennis", "Timarron Tennis"],
            degradedCourts: [],
            unreadableCourts: 0,
            warnings: []
        )

        #expect(lines.count == 1)

        let line = try #require(lines.first)

        #expect(line.contains("Bear Branch Tennis"))
        #expect(line.contains("Shadowbend Tennis"))
        #expect(line.contains("Timarron Tennis"))
    }

    // MARK: - Short and unreadable courts, kept apart

    @Test("One court reporting partial data reads as one court")
    func namesOneDegradedCourt() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: ["Bear Branch Tennis 3"],
            unreadableCourts: 0,
            warnings: []
        )

        let line = try #require(lines.first)

        #expect(lines.count == 1)
        #expect(line.contains("1 court "))
        #expect(line.contains("1 courts") == false)
    }

    @Test("Two courts reporting partial data read as two")
    func countsTwoDegradedCourts() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: ["Bear Branch Tennis 3", "Shadowbend Tennis 1"],
            unreadableCourts: 0,
            warnings: []
        )

        let line = try #require(lines.first)

        #expect(line.contains("2 courts"))
    }

    /// Partial data is a court you can still see; an unreadable one is not on
    /// the screen at all. Merging them would tell the user the wrong thing
    /// about what they are looking at.
    @Test("Unreadable courts are reported separately from short ones")
    func separatesUnreadableFromDegraded() {
        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: ["Bear Branch Tennis 3"],
            unreadableCourts: 2,
            warnings: []
        )

        #expect(lines.count == 2)
        #expect(Set(lines).count == 2, "the two lines must not read alike")
    }

    @Test("One unreadable court reads as one court")
    func countsOneUnreadableCourt() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 1, warnings: [])

        let line = try #require(lines.first)

        #expect(lines.count == 1)
        #expect(line.contains("1 court "))
        #expect(line.contains("1 courts") == false)
    }

    @Test("Several unreadable courts read as several")
    func countsSeveralUnreadableCourts() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 11, warnings: [])

        let line = try #require(lines.first)

        #expect(line.contains("11 courts"))
    }

    /// Counts are written with plain interpolation because the numeric
    /// convenience call is matched by the date-handling guard and fails the
    /// build. A grouped "1,000" would show up here.
    @Test("Counts are plain digits with no grouping")
    func writesCountsPlainly() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 1234, warnings: [])

        let line = try #require(lines.first)

        #expect(line.contains("1234"))
        #expect(line.contains("1,234") == false)
    }

    // MARK: - Warnings, by exception

    /// D7's positive direction.
    @Test("A warning the app has not accounted for is shown")
    func showsAnUnaccountedWarning() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0,
            warnings: ["This facility is closed for maintenance today."]
        )

        #expect(lines.count == 1)
        #expect(try #require(lines.first).contains("closed for maintenance"))
    }

    /// Reduced to a distinct set: eighty copies of one message are one line.
    @Test("A warning every court repeats appears once, never eighty times")
    func reducesRepeatedWarningsToOne() {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0,
            warnings: Array(repeating: "This facility is closed for maintenance today.", count: 80)
        )

        #expect(lines.count == 1)
    }

    @Test("Two different unaccounted warnings both appear")
    func showsTwoDistinctWarnings() {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0,
            warnings: [
                "This facility is closed for maintenance today.",
                "Court 3 is resurfaced this week and unavailable.",
                "This facility is closed for maintenance today.",
            ]
        )

        #expect(lines.count == 2)
    }

    /// The residency notice is suppressed whatever day count it names —
    /// matched on two stable fragments rather than on the whole string.
    @Test(
        "The residency notice is suppressed whatever number of days it names",
        arguments: NoticeCases.residencyPhrasings
    )
    func suppressesResidencyNoticeAtEveryDayCount(warning: String) {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0, warnings: [warning])

        #expect(lines.isEmpty, "\(warning) should have been suppressed")
    }

    /// **The direction that costs the user something.** Over-matching would
    /// swallow a real notice and they would never know it existed. The first
    /// two of these each share one fragment with the residency notice.
    @Test(
        "A warning that merely mentions residency, or advance booking, still gets through",
        arguments: NoticeCases.mustSurvive
    )
    func doesNotOverMatch(warning: String) throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0, warnings: [warning])

        #expect(lines.count == 1, "\(warning) was wrongly suppressed")
        #expect(try #require(lines.first).contains(warning))
    }

    /// The residency notice alongside a real one: the first goes, the second
    /// stays.
    @Test("A real warning survives beside the suppressed one")
    func keepsRealWarningBesideSuppressedOne() throws {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0,
            warnings: [residencyNotice, "This facility is closed for maintenance today."]
        )

        #expect(lines.count == 1)
        #expect(try #require(lines.first).contains("closed for maintenance"))
    }

    /// An empty or whitespace-only warning is not a sentence and must not
    /// become a blank line on screen.
    @Test("Empty warnings never become blank lines")
    func dropsEmptyWarnings() {
        let lines = NoticeText.lines(
            unmatchedFavorites: [], degradedCourts: [], unreadableCourts: 0,
            warnings: ["", "   ", "\n"]
        )

        #expect(lines.isEmpty)
    }

    // MARK: - Every line is presentable

    @Test("Every line is a complete non-empty sentence")
    func everyLineIsASentence() {
        let lines = NoticeText.lines(
            unmatchedFavorites: ["Bear Branch Tennis", "Shadowbend Tennis"],
            degradedCourts: ["Timarron Tennis Court #1"],
            unreadableCourts: 3,
            warnings: [residencyNotice, "This facility is closed for maintenance today."]
        )

        #expect(lines.count == 4)

        for line in lines {
            #expect(line.isEmpty == false)
            #expect(line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?"), "\(line)")
            #expect(line.hasPrefix(" ") == false, "\(line)")

            // A leading digit is correct here — counts are written as plain
            // digits, the same way the facility summary reads "2 of 5 free at
            // 7 PM".
            #expect(line.first.map { $0.isUppercase || $0.isNumber } == true, "\(line)")
        }
    }

    /// All four kinds at once, each said once.
    @Test("Every kind of notice appears exactly once when all are present")
    func saysEachThingOnce() {
        let lines = NoticeText.lines(
            unmatchedFavorites: ["Bear Branch Tennis"],
            degradedCourts: ["Timarron Tennis Court #1"],
            unreadableCourts: 1,
            warnings: ["This facility is closed for maintenance today."]
        )

        #expect(lines.count == 4)
        #expect(Set(lines).count == 4)
    }
}
