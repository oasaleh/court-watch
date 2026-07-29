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
//    * the spoken cell label                — `SlotAppearance.fullLabel(court:slot:status:)`
//    * the in-cell hour and the list tier   — `SlotTime.displayString`, asserted directly
//
//  The hour ruler used to be on that list. It is gone: the strip scrolls, so
//  every cell is wide enough to write its own hour and there is no sparse row of
//  labels above the grid to keep honest. The times it used to print are the same
//  `SlotTime.displayString` values now asserted per cell below.
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
        ("07:00:00", "7 AM"),
        ("11:00:00", "11 AM"),
        ("12:00:00", "12 PM"),  // noon is PM, and not "0:00"
        ("13:00:00", "1 PM"),
        ("18:00:00", "6 PM"),
        ("22:00:00", "10 PM"),
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

    @Test("The summary line names the count, the total and a twelve-hour time")
    func rendersSummaryLine() throws {
        let summary = FacilitySummary(
            slot: try slot("18:00:00"), freeCourts: 4, totalCourts: 5, startsLater: false)

        #expect(AvailabilitySummaryText.line(for: summary) == "4 of 5 free")
    }

    /// The reported bug, pinned. A user looking at 7 PM onwards read
    /// "4 of 4 free at 10 PM" as the filter having been ignored — the data was
    /// right and the sentence was not. When the opening is later than the hour
    /// on screen the line has to say so out loud rather than naming a time that
    /// looks like an answer to a question nobody asked.
    @Test("A later opening leads with the hour it is actually free")
    func rendersLaterSummaryLine() throws {
        let summary = FacilitySummary(
            slot: try slot("22:00:00"), freeCourts: 4, totalCourts: 4, startsLater: true)

        #expect(AvailabilitySummaryText.line(for: summary) == "Next free at 10 PM · 4 of 4")
    }

    @Test("A facility with nothing left says so instead of naming a time")
    func rendersEmptySummaryLine() {
        #expect(AvailabilitySummaryText.line(for: nil) == "Nothing free today")
    }

    /// Both numbers are written with plain interpolation because the numeric
    /// convenience call is matched by the date-handling guard. Asserting
    /// two-digit values keeps that honest — a grouped "1,000" would show up here.
    @Test("The summary counts are plain digits")
    func rendersSummaryCountPlainly() throws {
        let summary = FacilitySummary(
            slot: try slot("11:00:00"), freeCourts: 11, totalCourts: 11, startsLater: true)

        #expect(AvailabilitySummaryText.line(for: summary) == "Next free at 11 AM · 11 of 11")
    }

    /// Every court free reads as such rather than collapsing to a bare count.
    @Test("A wholly free facility still names the total")
    func rendersFullyFreeSummary() throws {
        let summary = FacilitySummary(
            slot: try slot("07:00:00"), freeCourts: 2, totalCourts: 2, startsLater: false)

        #expect(AvailabilitySummaryText.line(for: summary) == "2 of 2 free")
    }

    // MARK: - UI-06, the spoken cell label

    @Test("A spoken cell label carries a twelve-hour time")
    func rendersSpokenCellLabel() throws {
        let label = SlotAppearance.fullLabel(
            court: "Bear Branch Tennis 3", slot: try slot("18:00:00"), status: .available)

        #expect(label == "Bear Branch Tennis 3, 6 PM, Available")
    }

    /// A VoiceOver user on a 24-hour device must still hear "2 PM". This is
    /// the announcement, so it is the string that matters.
    @Test("Every state's spoken label keeps the twelve-hour time")
    func spokenLabelHoldsAcrossStates() throws {
        let time = try slot("14:00:00")

        for status in SlotAppearanceCases.all {
            let label = SlotAppearance.fullLabel(
                court: "Shadowbend Tennis 1", slot: time, status: status)

            #expect(label.hasPrefix("Shadowbend Tennis 1, 2 PM, "), "\(label)")
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

        #expect(rendered.first == "7 AM")
        #expect(rendered.last == "10 PM")
        #expect(rendered.allSatisfy { $0.hasSuffix(" AM") || $0.hasSuffix(" PM") })

        // No minutes on an hourly schedule. Those three characters are what
        // decide whether a cell can label itself, and ":00" says nothing.
        #expect(rendered.allSatisfy { $0.contains(":") == false })

        // The list tier joins them exactly this way.
        #expect(rendered.prefix(3).joined(separator: ", ") == "7 AM, 8 AM, 9 AM")
    }

    // MARK: - The start-time filter's choice labels

    /// New user-visible time strings, so they need asserting here for the same
    /// reason as everything above: the toolbar shows the active choice, and on a
    /// 24-hour device an unpinned label would read "From 18:00".
    @Test("A filter choice reads as a twelve-hour time")
    func rendersFilterChoiceLabel() throws {
        #expect(StartTimeFilter(start: try slot("18:00:00")).label == "From 6 PM")
        #expect(StartTimeFilter(start: try slot("09:00:00")).label == "From 9 AM")
        #expect(StartTimeFilter(start: try slot("12:00:00")).label == "From 12 PM")
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
                "From 7 AM", "From 8 AM", "From 9 AM", "From 10 AM",
                "From 11 AM", "From 12 PM", "From 1 PM", "From 2 PM",
                "From 3 PM", "From 4 PM", "From 5 PM", "From 6 PM",
                "From 7 PM", "From 8 PM", "From 9 PM", "From 10 PM",
            ])
    }

    // MARK: - The always-visible status line

    /// A composed string, so it needs asserting in its own right: neither half
    /// being correct proves the join is.
    @Test("The status line is just the refresh time when nothing is filtered")
    func rendersUnfilteredStatusLine() throws {
        #expect(
            try StatusLineText.line(fetchedAt: referenceInstant())
                == "Updated 2:00 PM")
    }

    /// The active filter is named in the toolbar control that sets it, not
    /// repeated here. Saying it in both places put the same sentence twice on
    /// one screen.
    ///
    /// Stated as "no filter's label appears in the line" rather than by passing
    /// a filter in, because the line no longer takes one. The old form looped
    /// over every choice asserting the same constant, which a signature that
    /// ignored the argument satisfied without doing anything.
    @Test("No filter label reaches the status line")
    func statusLineNamesNoFilter() throws {
        let reference = try referenceInstant()
        let slots = try publishedSlots.map { try slot($0) }
        let line = StatusLineText.line(fetchedAt: reference)

        #expect(line == "Updated 2:00 PM")

        for choice in StartTimeFilter.choices(for: slots) {
            #expect(line.contains(choice.label) == false, "\(choice.label)")
        }
    }

    // MARK: - The court's own open-hour count, at the largest text sizes

    /// The unit is named because the facility's line above counts something
    /// else in the same shape. Asserting the exact string is the assertion:
    /// "7 of 16 free" is what the collision looked like.
    @Test("A court's open-hour count names its unit")
    func rendersOpenHoursLine() {
        #expect(OpenHoursText.line(open: 7, total: 16) == "7 of 16 hours free")
    }

    /// A court with nothing left says so rather than counting to zero.
    @Test("A fully booked court says nothing is free")
    func rendersNoOpenHours() {
        #expect(OpenHoursText.line(open: 0, total: 16) == "Nothing free")
    }

    /// The two lines sit one above the other at accessibility text sizes, and
    /// this is the pair that used to be indistinguishable. Asserted together so
    /// that making one of them ambiguous again fails here rather than on a
    /// screen nobody visits.
    @Test("The court line and the facility line cannot be confused")
    func courtAndFacilityLinesReadDifferently() throws {
        let facility = AvailabilitySummaryText.line(
            for: FacilitySummary(
                slot: try slot("07:00:00"), freeCourts: 11, totalCourts: 11,
                startsLater: false))
        let court = OpenHoursText.line(open: 11, total: 11)

        // Same numbers on purpose: if the wording alone does not tell them
        // apart, nothing does.
        #expect(facility != court)
        #expect(court.contains("hours"))
        #expect(facility.contains("hours") == false)
    }

    // MARK: - A refresh that failed over data that is still usable
    /// The most likely regression in this area is a stray separator on a line
    /// that is on screen every second the app is open, so the no-failure case is
    /// asserted character for character against what it read before.
    @Test("With nothing wrong the status line is exactly what it was")
    func statusLineIsUnchangedWithoutAFailure() throws {
        let reference = try referenceInstant()

        #expect(
            StatusLineText.line(fetchedAt: reference, failure: nil)
                == "Updated 2:00 PM")
        #expect(
            StatusLineText.line(fetchedAt: reference, failure: nil)
                == StatusLineText.line(fetchedAt: reference))
    }

    /// The old signal that a refresh had not worked was a timestamp that did
    /// not move. Since the line withdraws a few seconds after each load that
    /// signal is gone, so the failure has to be said out loud — beside the
    /// unchanged time, which is the pair a user needs to judge whether to walk
    /// to a court.
    @Test("A failed refresh names the failure and keeps the original time")
    func statusLineNamesAFailedRefresh() throws {
        let line = try StatusLineText.line(
            fetchedAt: referenceInstant(),
            failure: .transport(.notConnectedToInternet))

        #expect(line.contains("Updated 2:00 PM"))
        #expect(line != "Updated 2:00 PM")
        #expect(line.hasPrefix("No Internet Connection"))
    }

    /// Asserting only that *a* failure appears would pass a version saying
    /// "couldn't update" for everything, which throws away the whole taxonomy.
    @Test("Two failure classes produce two different lines")
    func failureClassesReadDifferently() throws {
        let reference = try referenceInstant()

        let offline = StatusLineText.line(
            fetchedAt: reference, failure: .transport(.notConnectedToInternet))
        let farEnd = StatusLineText.line(
            fetchedAt: reference, failure: .transport(.timedOut))
        let refused = StatusLineText.line(
            fetchedAt: reference,
            failure: .service(code: "1507", message: "Invalid request"))

        #expect(offline != farEnd)
        #expect(offline != refused)
        #expect(farEnd != refused)

        // All three still carry the age of what is on screen.
        for line in [offline, farEnd, refused] {
            #expect(line.contains("Updated 2:00 PM"), "\(line)")
        }
    }

    /// One source of failure words. Writing a second short phrase for this line
    /// is exactly the drift that deleting the old copy property prevented.
    @Test("The failure words come from the same mapping as the failure screen")
    func failureWordsComeFromTheMapping() throws {
        let reference = try referenceInstant()

        for error in ErrorPresentationCases.all {
            let line = StatusLineText.line(fetchedAt: reference, failure: error)

            #expect(line.hasPrefix(ErrorPresentation.of(error).title), "\(line)")
        }
    }

    /// A 24-hour device must not turn this into "14:00", and the meridiem is
    /// the part that disappears first.
    @Test("A failed-refresh line is still a twelve-hour time")
    func failedRefreshLineIsTwelveHour() throws {
        let line = try StatusLineText.line(
            fetchedAt: referenceInstant(), failure: .transport(.timedOut))

        #expect(line.contains("2:00 PM"))
        #expect(line.contains("PM"))
        #expect(line.contains("14:00") == false)
        #expect(line.contains("pm") == false)
    }

    /// The filter is named in the toolbar control that sets it. A failure is a
    /// notice that appears only when something went wrong, not a second
    /// permanent field, so setting a filter changes nothing here.
    @Test("A failed-refresh line reads the same whether or not a filter is set")
    func failedRefreshLineIgnoresTheFilter() throws {
        let reference = try referenceInstant()
        let failure = APIError.transport(.notConnectedToInternet)

        let unfiltered = StatusLineText.line(
            fetchedAt: reference, failure: failure)
        let filtered = StatusLineText.line(
            fetchedAt: reference,
            failure: failure)

        #expect(unfiltered == filtered)
        #expect(filtered.contains("18:00") == false)
        #expect(filtered.contains("6 PM") == false)
    }

    /// VoiceOver reads this line as one announcement, so it has to be a
    /// sentence rather than two fragments jammed together.
    @Test("A failed-refresh line reads as a complete announcement")
    func failedRefreshLineIsOneSentence() throws {
        let reference = try referenceInstant()

        for error in ErrorPresentationCases.all {
            let line = StatusLineText.line(fetchedAt: reference, failure: error)

            // No doubled or dangling punctuation, and nothing left hanging at
            // either end.
            #expect(line.contains("  ") == false, "\(line)")
            #expect(line.contains("..") == false, "\(line)")
            #expect(line.hasPrefix(" ") == false, "\(line)")
            #expect(line.hasSuffix(" ") == false, "\(line)")
            #expect(line.hasSuffix("PM") || line.hasSuffix("AM"), "\(line)")
        }
    }

    /// Nothing technical may reach this line either — it is the same copy, so
    /// it inherits the same guarantee, and that is worth pinning where it is
    /// read rather than only where it is written.
    @Test("A failed-refresh line leaks no decoder text or response code")
    func failedRefreshLineLeaksNothing() throws {
        let reference = try referenceInstant()

        let lines = [
            StatusLineText.line(
            fetchedAt: reference,
                failure: .decoding("keyNotFound(CodingKeys(stringValue: \"response_code\"))")),
            StatusLineText.line(
            fetchedAt: reference,
                failure: .service(code: "1507", message: "Invalid request")),
            StatusLineText.line(
            fetchedAt: reference, failure: .sessionExpired(code: "0012")),
        ]

        for line in lines {
            for marker in ["keyNotFound", "CodingKeys", "response_code", "1507", "0012"] {
                #expect(line.contains(marker) == false, "\(marker) leaked into: \(line)")
            }
        }
    }
}
