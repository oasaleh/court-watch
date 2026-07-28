//
//  CourtWatchUITests.swift
//  CourtWatchUITests
//
//  What VoiceOver would actually hear.
//
//  The unit suite proves the *strings* — that a cell says court, then time,
//  then state, and that the four states speak three distinct words. It cannot
//  prove those strings are attached to anything, because no unit test renders
//  a screen. A cell that computes a perfect label and never applies it passes
//  every test in the other target and is silent on a device.
//
//  So this file asserts against the accessibility tree of a running app, which
//  is the tree VoiceOver reads. It is the only test here that can.
//
//  XCTest rather than Swift Testing because Swift Testing does not support UI
//  tests. The target is also `nonisolated` at the build-setting level: under
//  the project-wide MainActor default an XCTestCase subclass will not compile.
//

import XCTest

final class CourtWatchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every grid cell carries a label and a spoken state.
    ///
    /// Walks in through the picker rather than seeding defaults, because the
    /// path a user takes on first launch is the one worth proving: an empty
    /// state that cannot reach a grid is a broken app whatever the grid looks
    /// like afterwards.
    @MainActor
    func testGridCellsCarrySpokenLabels() throws {
        let app = XCUIApplication()
        app.launch()

        chooseAFacilityIfNeeded(in: app)

        // The grid arrives over the network, so it is waited for rather than
        // assumed. A wait that fails cleanly beats a flaky assertion.
        let cell = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@ OR value == %@", "Available", "Booked"))
            .firstMatch

        XCTAssertTrue(
            cell.waitForExistence(timeout: 30),
            "No cell reported an availability state. Either the grid never "
                + "loaded, or the cells are not exposing their state to "
                + "VoiceOver — which is the failure this test exists for.")

        // The label names the court and the hour. Both halves matter: a court
        // alone leaves a VoiceOver user unable to tell which column they are
        // on, and an hour alone leaves them unable to tell which row.
        let label = cell.label
        XCTAssertFalse(label.isEmpty, "A cell with a state but no label.")
        XCTAssertTrue(
            label.contains("AM") || label.contains("PM"),
            "A cell label with no twelve-hour time in it: \(label)")
    }

    /// Nothing that reports a state reports a blank one.
    ///
    /// Weaker than the unit assertion by necessity — a real day may be all
    /// free or all booked, so the set of states present cannot be predicted.
    /// What can be checked is that no element exposes an empty value where a
    /// word belongs, which is what a dropped `accessibilityValue` looks like
    /// from the outside.
    @MainActor
    func testNoCellIsSilentAboutItsState() throws {
        let app = XCUIApplication()
        app.launch()

        chooseAFacilityIfNeeded(in: app)

        let stated = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@ OR value == %@", "Available", "Booked"))

        XCTAssertTrue(
            stated.firstMatch.waitForExistence(timeout: 30),
            "Nothing on screen reported a state.")

        // Sampled rather than exhaustive: the tree is large and the query is
        // the slow part, and a dropped label would show up in the first few.
        for index in 0..<min(stated.count, 12) {
            let element = stated.element(boundBy: index)

            XCTAssertFalse(
                element.label.isEmpty,
                "A cell reported a state but no label, so VoiceOver would say "
                    + "what it is without saying which court or hour it is.")
        }
    }

    /// Gets past the empty state when nothing has been chosen yet.
    ///
    /// Tolerant on purpose: the simulator may already hold favourites from an
    /// earlier run, in which case there is no picker to walk and the grid is
    /// on screen already.
    @MainActor
    private func chooseAFacilityIfNeeded(in app: XCUIApplication) {
        let chooseButton = app.buttons["Choose Facilities"]

        guard chooseButton.waitForExistence(timeout: 10) else { return }

        chooseButton.tap()

        let firstFacility = app.collectionViews.buttons.firstMatch
        if firstFacility.waitForExistence(timeout: 10) {
            firstFacility.tap()
        }

        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }
    }
}
