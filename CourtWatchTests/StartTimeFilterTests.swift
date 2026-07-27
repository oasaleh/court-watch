//
//  StartTimeFilterTests.swift
//  CourtWatchTests
//
//  The fetch-or-not decision, and the wire format of a windowed request.
//
//  The cases with teeth are the two widening rows. The *same* widening — from
//  six o'clock back to three — must fetch after a windowed refresh and must not
//  after an unwindowed one. A test covering only one of them passes against an
//  implementation that ignores the held window entirely, which is precisely the
//  bug this design exists to prevent: after a windowed refresh the app no longer
//  holds the whole day, and filtering locally would show fewer slots than exist.
//  On screen that is indistinguishable from those courts being booked.
//
//  Every decision here is asserted as the function's return value rather than by
//  observing a request, so it holds with no network and no mock.
//

import Foundation
import Testing

@testable import CourtWatch

private let publishedSlots = [
    "07:00:00", "08:00:00", "09:00:00", "10:00:00",
    "11:00:00", "12:00:00", "13:00:00", "14:00:00",
    "15:00:00", "16:00:00", "17:00:00", "18:00:00",
    "19:00:00", "20:00:00", "21:00:00", "22:00:00",
]

private func central(hour: Int, minute: Int = 0) throws -> Date {
    try #require(
        CourtTime.calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: hour, minute: minute)),
        "Could not build 2026-07-26 \(hour):\(minute) Central"
    )
}

private func slot(_ apiString: String) throws -> SlotTime {
    try #require(SlotTime(apiString: apiString))
}

private func filter(_ apiString: String) throws -> StartTimeFilter {
    StartTimeFilter(start: try slot(apiString))
}

private func window(_ start: String, _ end: String) throws -> RequestedWindow {
    RequestedWindow(start: try slot(start), end: try slot(end))
}

/// A whole published day, every court free.
private func fullDay() throws -> Availability {
    let times = publishedSlots.map { "\"\($0)\"" }.joined(separator: ", ")
    let details = Array(repeating: "{\"status\": 0}", count: publishedSlots.count)
        .joined(separator: ", ")

    let json = """
        {
          "headers": { "response_code": "0000" },
          "body": {
            "availability": {
              "time_slots": [\(times)],
              "resources": [
                {
                  "resource_id": 1,
                  "resource_name": "Some Tennis 1",
                  "warning_messages": [],
                  "time_slot_details": [\(details)]
                }
              ],
              "time_increment": 60
            }
          }
        }
        """

    return Availability(
        envelope: try JSONDecoder().decode(AvailabilityEnvelope.self, from: Data(json.utf8)))
}

/// Argument lists live on a `nonisolated` type.
nonisolated enum CoverageCases {

    /// A short label, the held window, the requested window, and whether the
    /// data in hand can answer it without going back to the server.
    ///
    /// Written as api strings and resolved in the test, because `SlotTime` is
    /// failable and an argument list is no place to unwrap.
    static let all: [(String, String?, String?, Bool)] = [
        // Nothing has been narrowed yet: the whole day is held.
        ("narrow from any to 6pm", nil, "18:00:00", true),
        ("narrow from any to 3pm", nil, "15:00:00", true),
        ("stay at any", nil, nil, true),

        // Held a slice, asked for a smaller slice inside it.
        ("narrow from 3pm to 6pm", "15:00:00", "18:00:00", true),
        ("narrow from 6pm to 8pm", "18:00:00", "20:00:00", true),
        ("same window again", "18:00:00", "18:00:00", true),

        // Held a slice, asked for something starting earlier. The subset bug.
        ("widen from 6pm to 3pm", "18:00:00", "15:00:00", false),
        ("widen from 8pm to 6pm", "20:00:00", "18:00:00", false),

        // Held a slice, asked for the whole day.
        ("clear the filter", "18:00:00", nil, false),
    ]
}

struct StartTimeFilterTests {

    // MARK: - What the filter shows

    @Test("With no filter every remaining slot is visible")
    func showsEverythingWithoutAFilter() throws {
        let day = VisibleDay.resolve(
            availability: try fullDay(), now: try central(hour: 6),
            startingAt: StartTimeFilter.fromNow.start)

        #expect(day.slots.count == 16)
    }

    @Test("A six o'clock filter leaves only six and later")
    func narrowsToSixOClock() throws {
        let day = VisibleDay.resolve(
            availability: try fullDay(), now: try central(hour: 6),
            startingAt: try filter("18:00:00").start)

        #expect(day.slots.map(\.hour) == [18, 19, 20, 21, 22])
    }

    /// The rule this replaced said a filter could only ever narrow. It now
    /// reaches back: asking for 7 AM at two in the afternoon shows the morning,
    /// because asking is an instruction rather than a preference.
    @Test("A filter earlier than now reaches back to the hour it names")
    func reachesBackToTheNamedHour() throws {
        let day = VisibleDay.resolve(
            availability: try fullDay(), now: try central(hour: 14),
            startingAt: try filter("07:00:00").start)

        #expect(day.slots.count == 16)
        #expect(day.slots.first?.hour == 7)
    }

    /// An empty screen caused by a filter is not a day that has ended, and the
    /// two must not be confused: one is answered by widening the filter, the
    /// other by coming back tomorrow.
    @Test("A filter past the last slot empties the day without ending it")
    func distinguishesFilterFromEndOfDay() throws {
        let day = VisibleDay.resolve(
            availability: try fullDay(), now: try central(hour: 14),
            startingAt: try slot("23:00:00"))

        #expect(day.slots.isEmpty)
        #expect(day.isFinished == false)
    }

    // MARK: - The window a filter asks for

    @Test("The window carries the filter's start and the end of the day's last slot")
    func buildsWindowFromFilterAndDay() throws {
        let slots = try publishedSlots.map { try slot($0) }
        let requested = try #require(try filter("18:00:00").window(over: slots, slotMinutes: 60))

        #expect(requested.start == (try slot("18:00:00")))
        // The end of the 22:00 slot, not its start: end_time is exclusive.
        #expect(requested.end == SlotTime(hour: 23, minute: 0))
    }

    @Test("No filter asks for no window")
    func buildsNoWindowWithoutAFilter() throws {
        let slots = try publishedSlots.map { try slot($0) }

        #expect(StartTimeFilter.fromNow.window(over: slots, slotMinutes: 60) == nil)
    }

    @Test("A filter over an empty day asks for no window")
    func buildsNoWindowOverAnEmptyDay() throws {
        #expect(try filter("18:00:00").window(over: [], slotMinutes: 60) == nil)
    }

    /// The degenerate case: a filter sitting past the last slot. An end before
    /// its own start is not a window and would be a strange thing to put on the
    /// wire, so it collapses rather than inverting.
    @Test("A window never ends before it starts")
    func neverBuildsAnInvertedWindow() throws {
        let slots = [try slot("07:00:00"), try slot("08:00:00")]
        let requested = try #require(try filter("18:00:00").window(over: slots, slotMinutes: 60))

        #expect(requested.start <= requested.end)
        #expect(requested.end == (try slot("18:00:00")))
    }

    // MARK: - Whether a fetch is needed

    @Test("Coverage decides whether a filter change costs a request", arguments: CoverageCases.all)
    func decidesCoverage(name: String, held: String?, requested: String?, covered: Bool) throws {
        let heldWindow = try held.map { try window($0, "22:00:00") }
        let requestedWindow = try requested.map { try window($0, "22:00:00") }

        #expect(
            StartTimeFilter.covers(held: heldWindow, requested: requestedWindow) == covered,
            "\(name)")
    }

    /// The pair that matters, written out together so the difference between
    /// them is visible in one place: the *same* widening, decided differently by
    /// what the app is actually holding.
    @Test("The same widening fetches after a windowed fetch and not after an unwindowed one")
    func widensDifferentlyByWhatIsHeld() throws {
        let requested = try window("15:00:00", "22:00:00")

        // Whole day in hand: widening is free.
        #expect(StartTimeFilter.covers(held: nil, requested: requested))

        // Only the evening in hand: widening must go back to the server, or the
        // morning silently reads as booked.
        #expect(
            StartTimeFilter.covers(
                held: try window("18:00:00", "22:00:00"), requested: requested) == false)
    }

    @Test("Clearing the filter is free after an unwindowed fetch and costs one after a windowed one")
    func clearsDifferentlyByWhatIsHeld() throws {
        #expect(StartTimeFilter.covers(held: nil, requested: nil))
        #expect(
            StartTimeFilter.covers(held: try window("18:00:00", "22:00:00"), requested: nil)
                == false)
    }

    /// Narrowing is the common interaction and must never cost a round trip
    /// against the WAF-fronted host.
    @Test("Narrowing never needs a fetch")
    func narrowingIsAlwaysFree() throws {
        let slots = try publishedSlots.map { try slot($0) }

        for choice in StartTimeFilter.choices(for: slots) {
            #expect(
                StartTimeFilter.covers(held: nil, requested: choice.window(over: slots, slotMinutes: 60)),
                "\(choice.label) from an unwindowed fetch")
        }
    }

    // MARK: - TIME-06, the wire format

    /// Phase 2 pinned the unwindowed shape. This is the windowed one: both time
    /// keys present with the filter's own values, and the range flag set so the
    /// server actually trims.
    @Test("A windowed request encodes both time keys and the range flag")
    func encodesWindowedRequestBody() throws {
        let slots = try publishedSlots.map { try slot($0) }
        let requested = try #require(try filter("18:00:00").window(over: slots, slotMinutes: 60))

        let body = AvailabilityClient.makeBody(
            day: try central(hour: 12),
            window: AvailabilityClient.SlotWindow(start: requested.start, end: requested.end))

        let json = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(body))
                as? [String: Any])

        #expect(json["start_time"] as? String == "18:00:00")
        #expect(json["end_time"] as? String == "23:00:00")
        #expect(json["change_time_range"] as? Bool == true)
        #expect(json["reserve_date"] as? String == "2026-07-26")
    }

    /// The unwindowed shape must stay as Phase 2 measured it: both keys present
    /// and null, and the flag off. Swift's default would drop nil keys entirely,
    /// and this endpoint is not worth discovering that difference on.
    @Test("An unwindowed request still sends both time keys as null with the flag off")
    func encodesUnwindowedRequestBody() throws {
        let body = AvailabilityClient.makeBody(day: try central(hour: 12), window: nil)

        let json = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(body))
                as? [String: Any])

        #expect(json["change_time_range"] as? Bool == false)
        #expect(json.keys.contains("start_time"))
        #expect(json.keys.contains("end_time"))
        #expect(json["start_time"] is NSNull)
        #expect(json["end_time"] is NSNull)
    }

    // MARK: - The choices

    @Test("The choices begin with no filter and are otherwise in ascending order")
    func offersOrderedChoices() throws {
        let choices = StartTimeFilter.choices(for: try publishedSlots.map { try slot($0) })

        #expect(choices.first == StartTimeFilter.fromNow)
        #expect(choices.count > 1)

        let hours = choices.compactMap(\.start)
        #expect(hours == hours.sorted())
        #expect(hours.count == choices.count - 1)
    }

    @Test("Every choice is distinct")
    func offersDistinctChoices() throws {
        let choices = StartTimeFilter.choices(for: try publishedSlots.map { try slot($0) })

        #expect(Set(choices).count == choices.count)
        #expect(Set(choices.map(\.id)).count == choices.count)
    }

    /// The first slot of the day must be reachable.
    ///
    /// A hardcoded list beginning at 9 AM made the 7 and 8 o'clock courts
    /// unselectable on a day whose first slot is 7 AM — the user could see them
    /// but never filter to them. Deriving the list from the day removes the
    /// class of bug rather than correcting one instance of it.
    @Test("Every published slot is offered as a start time")
    func offersEveryPublishedSlot() throws {
        let slots = try publishedSlots.map { try slot($0) }
        let offered = StartTimeFilter.choices(for: slots).compactMap(\.start)

        #expect(offered == slots)
        #expect(offered.first == (try slot("07:00:00")))
        #expect(offered.last == (try slot("22:00:00")))
    }

    /// The bug this window arithmetic exists to prevent.
    ///
    /// `end_time` is exclusive: a request naming the last slot's *start* comes
    /// back without that slot. Because the next window is computed from the
    /// shortened list, the day then erodes an hour per refresh until it is empty
    /// and the app claims today is over while courts are still free.
    @Test("A windowed refresh does not shorten the day it asks for")
    func windowSurvivesRepeatedRefreshes() throws {
        var slots = try publishedSlots.map { try slot($0) }
        let chosen = try filter("18:00:00")

        for _ in 0..<3 {
            let requested = try #require(chosen.window(over: slots, slotMinutes: 60))

            // What the server returns for that window: every slot from the
            // start up to, but not including, the exclusive end.
            slots = slots.filter { $0 >= requested.start && $0 < requested.end }

            #expect(slots.last == (try slot("22:00:00")), "the last slot must survive")
        }
    }

    @Test("The ending boundary is the end of the slot, not its start")
    func endingBoundaryIsExclusiveUpperBound() throws {
        #expect(try slot("22:00:00").endingBoundary(slotMinutes: 60) == SlotTime(hour: 23, minute: 0))
        #expect(try slot("07:00:00").endingBoundary(slotMinutes: 30) == SlotTime(hour: 7, minute: 30))
    }

    /// A slot ending at midnight must not name hour 24, and must not wrap to
    /// 00:00 — a bound before its own start would come back empty.
    @Test("The ending boundary never rolls past the end of the day")
    func endingBoundaryClampsAtMidnight() throws {
        #expect(try slot("23:00:00").endingBoundary(slotMinutes: 60) == SlotTime(hour: 23, minute: 59))
        #expect(try slot("22:00:00").endingBoundary(slotMinutes: 180) == SlotTime(hour: 23, minute: 59))
    }
}
