//
//  GridFormattingTests.swift
//  CourtWatchTests
//
//  This file is QA-03, and its job is subtle enough to be worth stating plainly.
//
//  `Scripts/test-24h.sh` forces the device into 24-hour time, proves the setting
//  really took with a negative control, and then runs the whole suite. But that
//  gate can only observe what a test observes: **a time string no test asserts
//  is not covered by it**, no matter how correctly a screen renders it. No test
//  observes a rendered body.
//
//  So every new user-visible time string this phase puts on screen is produced
//  by a function, and asserted here by calling that function:
//
//    * the last-refreshed line              — `LastRefreshedText.line(at:)`
//    * the facility summary line            — `AvailabilitySummaryText.line(for:)`
//    * the hour ruler's labels              — `HourRuler.labels(for:cellWidth:dynamicTypeSize:)`
//    * the spoken cell label                — `SlotAppearance.fullLabel(court:slot:status:)`
//    * the in-cell hour and the list tier   — `SlotTime.displayString`, asserted directly
//
//  Everything is anchored to the same 2026-07-26 14:00 Central instant the
//  existing time suite uses, and asserted as exact twelve-hour output with an
//  uppercase meridiem.
//

import Foundation
import SwiftUI
import Testing

@testable import CourtWatch

/// The reference instant: 2026-07-26 14:00 in America/Chicago.
private func referenceInstant() throws -> Date {
    try #require(
        CourtTime.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 14)
        ),
        "Could not build the 2026-07-26 14:00 Central reference instant"
    )
}

private func slot(_ apiString: String) throws -> SlotTime {
    try #require(SlotTime(apiString: apiString))
}

/// The published slot list, for the ruler.
private let publishedSlots = [
    "07:00:00", "08:00:00", "09:00:00", "10:00:00",
    "11:00:00", "12:00:00", "13:00:00", "14:00:00",
    "15:00:00", "16:00:00", "17:00:00", "18:00:00",
    "19:00:00", "20:00:00", "21:00:00", "22:00:00",
]

/// Argument lists live on a `nonisolated` type.
nonisolated enum GridFormattingCases {

    /// An API slot string against the twelve-hour form the user must see, on any
    /// device however it is configured.
    static let slotDisplays: [(String, String)] = [
        ("07:00:00", "7:00 AM"),
        ("11:00:00", "11:00 AM"),
        ("12:00:00", "12:00 PM"),  // noon is PM, and not "0:00"
        ("13:00:00", "1:00 PM"),
        ("18:00:00", "6:00 PM"),
        ("22:00:00", "10:00 PM"),
    ]
}

struct GridFormattingTests {

    // MARK: - UI-07, the last-refreshed line

    @Test("The last-refreshed line reads as a twelve-hour time")
    func rendersLastRefreshed() throws {
        #expect(try LastRefreshedText.line(at: referenceInstant()) == "Updated 2:00 PM")
    }

    /// A 24-hour device would render "14:00" here, and the meridiem is the part
    /// that disappears first, so both halves are asserted rather than only the
    /// whole string.
    @Test("The last-refreshed line keeps an uppercase meridiem")
    func lastRefreshedKeepsMeridiem() throws {
        let line = try LastRefreshedText.line(at: referenceInstant())

        #expect(line.contains("PM"))
        #expect(line.contains("pm") == false)
        #expect(line.contains("14:00") == false)
    }

    @Test("A morning refresh reads as AM")
    func rendersMorningRefresh() throws {
        let morning = try #require(
            CourtTime.calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 26, hour: 7, minute: 5)))

        #expect(LastRefreshedText.line(at: morning) == "Updated 7:05 AM")
    }

    // MARK: - D9, the facility summary line

    @Test("The summary line names the count and a twelve-hour time")
    func rendersSummaryLine() throws {
        let summary = FacilitySummary(slot: try slot("18:00:00"), freeCourts: 4)

        #expect(AvailabilitySummaryText.line(for: summary) == "4 free at 6:00 PM")
    }

    @Test("A facility with nothing left says so instead of naming a time")
    func rendersEmptySummaryLine() {
        #expect(AvailabilitySummaryText.line(for: nil) == "Nothing free today")
    }

    /// The count is written with plain interpolation because the numeric
    /// convenience call is matched by the date-handling guard. Asserting a
    /// two-digit count keeps that honest — a grouped "1,000" would show up here.
    @Test("The summary count is plain digits")
    func rendersSummaryCountPlainly() throws {
        let summary = FacilitySummary(slot: try slot("11:00:00"), freeCourts: 11)

        #expect(AvailabilitySummaryText.line(for: summary) == "11 free at 11:00 AM")
    }

    // MARK: - The hour ruler

    @Test("Every ruler label is a twelve-hour time")
    func rendersRulerLabels() throws {
        let slots = try publishedSlots.map { try slot($0) }

        // The measured phone geometry: 16 slots in a list row of about 330pt.
        let cellWidth = StripLayout.cellWidth(availableWidth: 330, slotCount: slots.count)
        let labels = HourRuler.labels(
            for: slots, cellWidth: cellWidth, dynamicTypeSize: .large)

        #expect(labels.count == 16)

        // Every third hour at default sizes, computed rather than hardcoded.
        #expect(
            labels.compactMap { $0 } == [
                "7:00 AM", "10:00 AM", "1:00 PM", "4:00 PM", "7:00 PM", "10:00 PM",
            ])
    }

    /// The leading column is always now-or-next, so it is always labelled
    /// whatever the stride works out to.
    @Test("The first ruler column is always labelled")
    func alwaysLabelsTheFirstColumn() throws {
        let slots = try publishedSlots.map { try slot($0) }

        for width in [120.0, 330.0, 402.0, 960.0] {
            let cellWidth = StripLayout.cellWidth(availableWidth: width, slotCount: slots.count)
            let labels = HourRuler.labels(
                for: slots, cellWidth: cellWidth, dynamicTypeSize: .large)

            #expect((labels.first ?? nil) == "7:00 AM", "at \(width)pt")
        }
    }

    @Test("Raising the text size thins the ruler out rather than overlapping it")
    func thinsRulerAtLargerTextSizes() throws {
        let slots = try publishedSlots.map { try slot($0) }
        let cellWidth = StripLayout.cellWidth(availableWidth: 330, slotCount: slots.count)

        let normal = HourRuler.labels(
            for: slots, cellWidth: cellWidth, dynamicTypeSize: .large
        ).compactMap { $0 }
        let large = HourRuler.labels(
            for: slots, cellWidth: cellWidth, dynamicTypeSize: .xxxLarge
        ).compactMap { $0 }

        #expect(large.count < normal.count)
        #expect(large.allSatisfy { $0.contains("AM") || $0.contains("PM") })
    }

    @Test("A ruler over no slots produces no labels")
    func handlesEmptyRuler() {
        #expect(
            HourRuler.labels(for: [], cellWidth: 17, dynamicTypeSize: .large).isEmpty)
    }

    // MARK: - UI-06, the spoken cell label

    @Test("A spoken cell label carries a twelve-hour time")
    func rendersSpokenCellLabel() throws {
        let label = SlotAppearance.fullLabel(
            court: "Bear Branch Tennis 3", slot: try slot("18:00:00"), status: .available)

        #expect(label == "Bear Branch Tennis 3, 6:00 PM, Available")
    }

    /// A VoiceOver user on a 24-hour device must still hear "2:00 PM". This is
    /// the announcement, so it is the string that matters.
    @Test("Every state's spoken label keeps the twelve-hour time")
    func spokenLabelHoldsAcrossStates() throws {
        let time = try slot("14:00:00")

        for status in SlotAppearanceCases.all {
            let label = SlotAppearance.fullLabel(
                court: "Shadowbend Tennis 1", slot: time, status: status)

            #expect(label.hasPrefix("Shadowbend Tennis 1, 2:00 PM, "), "\(label)")
            #expect(label.contains("14:00") == false, "\(label)")
        }
    }

    // MARK: - The hour drawn inside a cell

    /// The in-cell hour and the accessibility-size list both render
    /// `SlotTime.displayString` directly, so that is what is pinned.
    @Test("A slot's own display string is twelve-hour", arguments: GridFormattingCases.slotDisplays)
    func rendersSlotDisplayString(apiString: String, expected: String) throws {
        #expect(try slot(apiString).displayString == expected)
    }

    /// The whole published day at once, which is what the labelled tier writes
    /// into sixteen cells and the list tier joins into a sentence.
    @Test("Every published slot renders as a twelve-hour time with an uppercase meridiem")
    func rendersEveryPublishedSlot() throws {
        let rendered = try publishedSlots.map { try slot($0).displayString }

        #expect(rendered.first == "7:00 AM")
        #expect(rendered.last == "10:00 PM")
        #expect(rendered.allSatisfy { $0.hasSuffix(" AM") || $0.hasSuffix(" PM") })
        #expect(rendered.contains { $0.contains(":") })

        // The list tier joins them exactly this way.
        #expect(rendered.prefix(3).joined(separator: ", ") == "7:00 AM, 8:00 AM, 9:00 AM")
    }

    // MARK: - The start-time filter's choice labels

    /// New user-visible time strings, so they need asserting here for the same
    /// reason as everything above: the toolbar shows the active choice, and on a
    /// 24-hour device an unpinned label would read "From 18:00".
    @Test("A filter choice reads as a twelve-hour time")
    func rendersFilterChoiceLabel() throws {
        #expect(StartTimeFilter(start: try slot("18:00:00")).label == "From 6:00 PM")
        #expect(StartTimeFilter(start: try slot("09:00:00")).label == "From 9:00 AM")
        #expect(StartTimeFilter(start: try slot("12:00:00")).label == "From 12:00 PM")
    }

    @Test("The unfiltered choice names no time at all")
    func rendersUnfilteredChoiceLabel() {
        #expect(StartTimeFilter.fromNow.label == "Now")
    }

    /// Every choice the control can offer, so adding one cannot slip past the
    /// twelve-hour gate unasserted.
    @Test("Every offered choice is twelve-hour and none shows a 24-hour time")
    func rendersEveryFilterChoice() throws {
        let slots = try publishedSlots.map { try slot($0) }
        let choices = StartTimeFilter.choices(for: slots)

        for choice in choices where choice.start != nil {
            #expect(choice.label.hasPrefix("From "), "\(choice.label)")
            #expect(
                choice.label.hasSuffix(" AM") || choice.label.hasSuffix(" PM"), "\(choice.label)")
        }

        // The whole offered set, written out, so a reordering or a new entry has
        // to be looked at rather than silently absorbed. Every published slot is
        // offered — a list that began later than the day did was the bug.
        #expect(
            choices.map(\.label) == [
                "Now",
                "From 7:00 AM", "From 8:00 AM", "From 9:00 AM", "From 10:00 AM",
                "From 11:00 AM", "From 12:00 PM", "From 1:00 PM", "From 2:00 PM",
                "From 3:00 PM", "From 4:00 PM", "From 5:00 PM", "From 6:00 PM",
                "From 7:00 PM", "From 8:00 PM", "From 9:00 PM", "From 10:00 PM",
            ])
    }

    // MARK: - The always-visible status line

    /// A composed string, so it needs asserting in its own right: neither half
    /// being correct proves the join is.
    @Test("The status line is just the refresh time when nothing is filtered")
    func rendersUnfilteredStatusLine() throws {
        #expect(
            try StatusLineText.line(filter: .fromNow, fetchedAt: referenceInstant())
                == "Updated 2:00 PM")
    }

    /// The active filter is named in the toolbar control that sets it, not
    /// repeated here. Saying it in both places put the same sentence twice on
    /// one screen.
    @Test("The status line is the refresh time whether or not a filter is set")
    func rendersFilteredStatusLine() throws {
        let line = try StatusLineText.line(
            filter: StartTimeFilter(start: try slot("18:00:00")),
            fetchedAt: referenceInstant())

        #expect(line == "Updated 2:00 PM")
        #expect(line.contains("18:00") == false)
        #expect(line.contains("14:00") == false)
    }

    /// Whatever the filter, the line stays twelve-hour and says only how old the
    /// data is — the one thing that cannot be read anywhere else on screen.
    @Test("Every offered filter leaves the status line reading only the refresh time")
    func statusLineNamesEveryFilter() throws {
        let reference = try referenceInstant()
        let slots = try publishedSlots.map { try slot($0) }

        for choice in StartTimeFilter.choices(for: slots) {
            let line = StatusLineText.line(filter: choice, fetchedAt: reference)

            #expect(line == "Updated 2:00 PM", "\(choice.label) -> \(line)")
        }
    }
}
