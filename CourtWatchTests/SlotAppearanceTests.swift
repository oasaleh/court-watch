//
//  SlotAppearanceTests.swift
//  CourtWatchTests
//
//  The distinctness assertions are the point of this file.
//
//  Asserting that each state maps to *something* would pass against a mapping
//  that returned the same appearance three times — a grid where every cell
//  looked identical would be green. What must hold is that the three are
//  pairwise different, in every channel, and above all that an unrecognised
//  status shares nothing with the available one.
//
//  That last is T-04-01, the critical threat of this phase and the one wrong
//  answer this app must never give. It cannot be reached from any captured
//  data: the capture contains only statuses 0 and 1, so `unknown` is unreachable
//  from every fixture and the values below are built by hand. Nothing in the
//  real payload would ever reveal the bug this guards against.
//

import Foundation
import Testing

@testable import CourtWatch

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum SlotAppearanceCases {
    static let all: [SlotStatus] = [.available, .booked, .unknown(7)]
}

private func slot(_ apiString: String) throws -> SlotTime {
    try #require(SlotTime(apiString: apiString))
}

struct SlotAppearanceTests {

    @Test("Every state has an appearance and something to say", arguments: SlotAppearanceCases.all)
    func mapsEveryState(status: SlotStatus) {
        let appearance = SlotAppearance.of(status)

        #expect(appearance.spokenState.isEmpty == false)
        #expect(appearance.symbolName.isEmpty == false)
        #expect(appearance.inkWeight >= 0 && appearance.inkWeight <= 1)
    }

    @Test("Available is the solid, high-ink treatment")
    func mapsAvailable() {
        let appearance = SlotAppearance.of(.available)

        #expect(appearance.fill == .filled)
        #expect(appearance.symbolName == "checkmark")
        #expect(appearance.spokenState == "Available")
    }

    @Test("Booked is the empty, low-ink treatment")
    func mapsBooked() {
        let appearance = SlotAppearance.of(.booked)

        #expect(appearance.fill == .outline)
        #expect(appearance.symbolName == "xmark")
        #expect(appearance.spokenState == "Booked")
    }

    @Test("An unrecognised status is hatched and says so")
    func mapsUnknown() {
        let appearance = SlotAppearance.of(.unknown(42))

        #expect(appearance.fill == .hatched)
        #expect(appearance.symbolName == "questionmark")
        #expect(appearance.spokenState == "Availability unknown")
    }

    @Test("The three appearances are pairwise different")
    func distinguishesEveryState() {
        let available = SlotAppearance.of(.available)
        let booked = SlotAppearance.of(.booked)
        let unknown = SlotAppearance.of(.unknown(7))

        #expect(available != booked)
        #expect(available != unknown)
        #expect(booked != unknown)
    }

    /// D6 as an executable check. An unrecognised status must not look free —
    /// that sends someone on a wasted drive — and must not look booked either,
    /// which hides the thing they opened the app for. Every channel is asserted
    /// separately, because sharing even one would let the two read alike in
    /// whichever channel a given user actually perceives.
    @Test("An unrecognised status shares no channel with an available one")
    func neverLooksAvailable() {
        let available = SlotAppearance.of(.available)
        let unknown = SlotAppearance.of(.unknown(7))

        #expect(unknown.fill != available.fill)
        #expect(unknown.symbolName != available.symbolName)
        #expect(unknown.spokenState != available.spokenState)
        #expect(unknown.inkWeight != available.inkWeight)
    }

    @Test("An unrecognised status shares no channel with a booked one either")
    func neverLooksBooked() {
        let booked = SlotAppearance.of(.booked)
        let unknown = SlotAppearance.of(.unknown(7))

        #expect(unknown.fill != booked.fill)
        #expect(unknown.symbolName != booked.symbolName)
        #expect(unknown.spokenState != booked.spokenState)
        #expect(unknown.inkWeight != booked.inkWeight)
    }

    @Test("The three spoken words are pairwise different")
    func speaksThreeDistinctWords() {
        let spoken = SlotAppearanceCases.all.map { SlotAppearance.of($0).spokenState }

        #expect(Set(spoken).count == 3)
    }

    /// The raw number is diagnostic, not user-facing. Two unrecognised codes
    /// must be indistinguishable on screen rather than putting an unexplained
    /// integer in front of the user.
    @Test("Two different unrecognised values look identical")
    func collapsesUnknownRawValues() {
        #expect(SlotAppearance.of(.unknown(7)) == SlotAppearance.of(.unknown(99)))
        #expect(SlotAppearance.of(.unknown(-1)) == SlotAppearance.of(.unknown(1507)))
    }

    /// D2's central claim, checked rather than asserted in prose: the encoding
    /// is readable by density alone, so the three states must be strictly
    /// ordered by ink with no ties.
    @Test("Ink weight strictly orders available above unknown above booked")
    func ordersInkStrictly() {
        let available = SlotAppearance.of(.available).inkWeight
        let unknown = SlotAppearance.of(.unknown(7)).inkWeight
        let booked = SlotAppearance.of(.booked).inkWeight

        #expect(available > unknown)
        #expect(unknown > booked)
    }

    @Test("A cell reads as court, then time, then state")
    func buildsFullLabelInReadingOrder() throws {
        let label = SlotAppearance.fullLabel(
            court: "Bear Branch Tennis 3", slot: try slot("18:00:00"), status: .available)

        #expect(label == "Bear Branch Tennis 3, 6:00 PM, Available")
    }

    @Test("The label carries the court's own name and a twelve-hour time")
    func buildsLabelFromCourtAndTime() throws {
        #expect(
            SlotAppearance.label(court: "Timarron Tennis Court #1", slot: try slot("14:00:00"))
                == "Timarron Tennis Court #1, 2:00 PM")
        #expect(
            SlotAppearance.label(court: "Bear Branch Tennis 11", slot: try slot("07:00:00"))
                == "Bear Branch Tennis 11, 7:00 AM")
    }

    /// A VoiceOver user must be told the app does not know, in words, rather
    /// than hearing whatever the sighted fallback happens to be.
    @Test("An unrecognised cell says so out loud")
    func speaksUnknownStateInFullLabel() throws {
        let label = SlotAppearance.fullLabel(
            court: "Bear Branch Tennis 3", slot: try slot("18:00:00"), status: .unknown(7))

        #expect(label == "Bear Branch Tennis 3, 6:00 PM, Availability unknown")
        #expect(label.contains("Available,") == false)
    }
}
