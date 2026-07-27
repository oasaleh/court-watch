//
//  VisibleDayTests.swift
//  CourtWatchTests
//
//  This file is QA-04.
//
//  Everything the grid draws is a function of three inputs — the fetched
//  availability, a moment, and an optional start-time filter — so every
//  assertion here pins the moment rather than reading it. A suite that asked
//  the system what time it was would pass all morning and fail at eleven at
//  night, which is precisely the hour TIME-07 is about.
//
//  The mid-hour cases are the ones with teeth. Every other boundary in the
//  table below passes under both the old rule and the ruled one; 07:01, 14:15
//  and 22:59 are the three that would fail if anyone reverted the semantics.
//

import Foundation
import Testing

@testable import CourtWatch

/// The exact slot list the availability endpoint returns: hourly, 7am to 10pm.
private let publishedSlots = [
    "07:00:00", "08:00:00", "09:00:00", "10:00:00",
    "11:00:00", "12:00:00", "13:00:00", "14:00:00",
    "15:00:00", "16:00:00", "17:00:00", "18:00:00",
    "19:00:00", "20:00:00", "21:00:00", "22:00:00",
]

private func central(
    year: Int = 2026, month: Int = 7, day: Int = 26, hour: Int, minute: Int = 0
) throws -> Date {
    try #require(
        CourtTime.calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute)
        ),
        "Could not build \(year)-\(month)-\(day) \(hour):\(minute) Central"
    )
}

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum VisibleDayCases {

    /// hour, minute, how many slots survive, the first survivor's hour, finished.
    ///
    /// Computed by running the rule over the real 16-slot list rather than
    /// worked out by hand. Both sides of every boundary are present, because a
    /// one-sided assertion passes against an off-by-one comparison.
    static let boundaries: [(Int, Int, Int, Int?, Bool)] = [
        (6, 0, 16, 7, false),  // before the first slot
        (7, 0, 16, 7, false),  // exactly on the hour
        (7, 1, 16, 7, false),  // one minute in — the ruling
        (7, 59, 16, 7, false),  // one minute before it ends
        (8, 0, 15, 8, false),  // exactly at the hour's end
        (13, 20, 10, 13, false),  // research §5's worked case, recomputed
        (14, 0, 9, 14, false),
        (14, 15, 9, 14, false),  // mid-hour
        (21, 59, 2, 21, false),
        (22, 0, 1, 22, false),
        (22, 1, 1, 22, false),  // the day is NOT over — it used to be
        (22, 59, 1, 22, false),
        (23, 0, 0, nil, true),  // the last hour ends; the day is done
        (23, 30, 0, nil, true),
    ]
}

/// An availability assembled from a hand-made payload.
///
/// `init(envelope:)` is the only way to build one, which is deliberate — it
/// keeps the wire hop inside what is being tested. The empty day and the
/// short-status court below cannot be produced by any capture, so they are
/// written out here.
private func availability(
    slots: [String],
    courts: [(id: Int, name: String, statuses: [Int])],
    timeIncrement: Int? = 60
) throws -> Availability {
    let increment = timeIncrement.map { ", \"time_increment\": \($0)" } ?? ""

    let resources = courts.map { court in
        let details = court.statuses.map { "{\"status\": \($0)}" }.joined(separator: ", ")
        return """
            {
              "resource_id": \(court.id),
              "resource_name": "\(court.name)",
              "warning_messages": [],
              "time_slot_details": [\(details)]
            }
            """
    }.joined(separator: ",\n")

    let times = slots.map { "\"\($0)\"" }.joined(separator: ", ")

    let json = """
        {
          "headers": { "response_code": "0000" },
          "body": {
            "availability": {
              "time_slots": [\(times)],
              "resources": [\(resources)]\(increment)
            }
          }
        }
        """

    return Availability(
        envelope: try JSONDecoder().decode(AvailabilityEnvelope.self, from: Data(json.utf8)))
}

private func capturedAvailability(_ fixture: String) throws -> Availability {
    Availability(
        envelope: try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try Fixture.data(fixture)))
}

/// The whole published day, every court free, for cases that only care about
/// which slots survive.
private func fullDay() throws -> Availability {
    try availability(
        slots: publishedSlots,
        courts: [(id: 1, name: "Some Tennis 1", statuses: Array(repeating: 0, count: 16))]
    )
}

private func slot(_ apiString: String) throws -> SlotTime {
    try #require(SlotTime(apiString: apiString))
}

struct VisibleDayTests {

    // MARK: - The boundary table

    @Test("What survives at each boundary", arguments: VisibleDayCases.boundaries)
    func resolvesBoundaries(
        hour: Int, minute: Int, expectedCount: Int, firstHour: Int?, finished: Bool
    ) throws {
        let clock = FixedClock(now: try central(hour: hour, minute: minute))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: nil)

        #expect(day.slots.count == expectedCount, "at \(hour):\(minute)")
        #expect(day.slots.first?.hour == firstHour, "at \(hour):\(minute)")
        #expect(day.isFinished == finished, "at \(hour):\(minute)")
    }

    // MARK: - The three assertions that fail under the old rule

    /// Written out rather than left to the table, because these three are the
    /// whole of the user's ruling and the only cases that discriminate between
    /// the two rules.
    @Test("The seven o'clock hour survives one minute into itself")
    func survivesAtSevenOhOne() throws {
        let clock = FixedClock(now: try central(hour: 7, minute: 1))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: nil)

        #expect(day.slots.count == 16)
        #expect(day.slots.first?.displayString == "7 AM")
    }

    @Test("At a quarter past two the two o'clock slot is still shown")
    func survivesAtQuarterPastTwo() throws {
        let clock = FixedClock(now: try central(hour: 14, minute: 15))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: nil)

        #expect(day.slots.count == 9)
        #expect(day.slots.first?.displayString == "2 PM")
        #expect(day.isFinished == false)
    }

    @Test("At one minute to eleven the last slot is still shown and the day is not over")
    func survivesAtTwentyTwoFiftyNine() throws {
        let clock = FixedClock(now: try central(hour: 22, minute: 59))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: nil)

        #expect(day.slots.count == 1)
        #expect(day.slots.first?.displayString == "10 PM")
        #expect(day.isFinished == false)
    }

    /// The done-for-today moment, which the ruling moved from 22:01 to 23:00.
    @Test("At eleven exactly the day is finished")
    func finishesAtElevenExactly() throws {
        let clock = FixedClock(now: try central(hour: 23))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: nil)

        #expect(day.slots.isEmpty)
        #expect(day.isFinished)
    }

    @Test("A day with no slots at all reports finished rather than crashing")
    func handlesEmptyDay() throws {
        let clock = FixedClock(now: try central(hour: 12))
        let empty = try availability(slots: [], courts: [(id: 1, name: "A 1", statuses: [])])

        let day = VisibleDay.resolve(availability: empty, now: clock.now, startingAt: nil)

        #expect(day.slots.isEmpty)
        #expect(day.isFinished)
    }

    // MARK: - An explicit start time overrides the hide-the-past rule

    /// Picking an hour is an instruction, not a preference.
    ///
    /// Without a filter the app hides what has ended, because an elapsed slot is
    /// noise. But a user who deliberately chooses 9 AM at nine in the evening is
    /// asking to see the morning, and returning an empty screen would be the app
    /// overruling a direct request.
    @Test("An earlier start time reaches back past the current hour")
    func explicitStartShowsElapsedSlots() throws {
        let clock = FixedClock(now: try central(hour: 21))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: try slot("09:00:00"))

        #expect(day.slots.first?.displayString == "9 AM")
        #expect(day.slots.count == 14, "9 AM through 10 PM inclusive")
        #expect(day.isFinished == false)
    }

    /// The default is unchanged: with nothing asked for, the past stays hidden.
    @Test("Without a filter the elapsed hours are still hidden")
    func defaultStillHidesThePast() throws {
        let clock = FixedClock(now: try central(hour: 21))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: nil)

        #expect(day.slots.first?.displayString == "9 PM")
    }

    /// A user looking at a specific hour is never told the day is over — they
    /// asked to see something and the app shows it.
    @Test("An explicit start time is never answered with done-for-today")
    func explicitStartIsNeverFinished() throws {
        let clock = FixedClock(now: try central(hour: 23))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: try slot("07:00:00"))

        #expect(day.isFinished == false)
        #expect(day.slots.count == 16, "the whole published day")
    }

    // MARK: - Rows

    /// Count-only would pass against a row holding the right number of the
    /// wrong entries, so the exact statuses are written out.
    @Test("A court's statuses line up with the slots that survived")
    func alignsStatusesPositionally() throws {
        let clock = FixedClock(now: try central(hour: 14))

        // Four slots, four deliberately distinct statuses.
        let data = try availability(
            slots: ["12:00:00", "13:00:00", "14:00:00", "15:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 1, 1, 0])]
        )
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.slots.map(\.hour) == [14, 15])
        #expect(day.statuses(for: court) == [.booked, .available])
    }

    /// Against the real capture, derived from `Court.slots` rather than from
    /// the day being tested — so the two could disagree.
    @Test("The captured statuses survive the filter unchanged")
    func alignsAgainstTheCapture() throws {
        let clock = FixedClock(now: try central(hour: 14))
        let data = try capturedAvailability(Fixture.anonymous)
        let court = try #require(data.courts.first { $0.name == "Bear Branch Tennis 1" })

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)
        let expected = court.slots.filter { $0.time.hour >= 14 }.map(\.status)

        #expect(day.slots.count == 9)
        #expect(day.statuses(for: court) == expected)
        #expect(day.statuses(for: court).count == 9)
    }

    /// **This test inverts a Phase 4 assertion, deliberately.**
    ///
    /// Phase 4 paired a court's statuses against the visible slots by filtering
    /// the court's own list, so a court publishing fewer statuses than there
    /// were slots simply contributed fewer cells — and the view drew a blank,
    /// screen-reader-hidden square for the columns it had run out of. Phase 5
    /// removes that situation rather than wording it: every row is built by
    /// looking up each visible slot in the court's own slots, so a row is always
    /// exactly as long as the day and an hour the court never published says so
    /// out loud.
    ///
    /// The old name and comment described truncation as the intended design.
    /// Both are rewritten rather than left, because a stale name is how the
    /// superseded rule gets argued back in as a simplification.
    ///
    /// `degradedCourts` is asserted unchanged: the domain still records that
    /// this court's data was short. Padding is a presentation decision and
    /// happens here, not in the decode.
    @Test("A court with fewer statuses than slots is padded, not truncated")
    func padsShortCourt() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00", "09:00:00", "10:00:00"],
            courts: [
                (id: 1, name: "Some Tennis 1", statuses: [0, 1]),
                (id: 2, name: "Some Tennis 2", statuses: [0, 1, 0, 1]),
            ]
        )
        let short = try #require(data.courts.first { $0.id == 1 })
        let full = try #require(data.courts.first { $0.id == 2 })

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.slots.count == 4)

        // Four entries, not two. The two the court published stay at their own
        // indices; the hours it said nothing about say so.
        #expect(
            day.statuses(for: short) == [.available, .booked, .unpublished, .unpublished])
        #expect(day.statuses(for: full) == [.available, .booked, .available, .booked])

        // The model still describes what the server actually sent.
        #expect(short.slots.count == 2, "the domain is not padded — only the resolved day is")
        #expect(data.degradedCourts == ["Some Tennis 1"])
    }

    /// A court that published nothing at all is still a court, and its row is
    /// still the length of the day. Cannot be produced by any capture.
    @Test("A court publishing no statuses gets a full row of unpublished hours")
    func padsCourtPublishingNothing() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00", "09:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [])]
        )
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.slots.count == 3)
        #expect(day.statuses(for: court) == [.unpublished, .unpublished, .unpublished])
    }

    /// The row is one entry per *visible* slot, never per published status. A
    /// court carrying more than the day shows only the day.
    @Test("A court publishing more statuses than there are visible slots is cut to the day")
    func keepsOneEntryPerVisibleSlot() throws {
        let clock = FixedClock(now: try central(hour: 14))
        let data = try availability(
            slots: ["12:00:00", "13:00:00", "14:00:00", "15:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 0, 1, 0])]
        )
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.slots.map(\.hour) == [14, 15])
        #expect(day.statuses(for: court) == [.booked, .available])
    }

    /// The assertion that discriminates a lookup by slot time from index
    /// arithmetic.
    ///
    /// A short court is missing its *last* hours, so filtering the day forward
    /// means the visible window starts partway into what the court published.
    /// An implementation that walked indices would hand back this court's first
    /// status for the 8 AM column — labelling a 7 AM answer as an 8 AM one.
    /// Looking each visible slot up by its own time cannot do that.
    @Test("A padded row is keyed by slot time, not by position in the court's own list")
    func alignsPaddedRowByTimeNotIndex() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00", "09:00:00", "10:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 1])]
        )
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(
            availability: data, now: clock.now, startingAt: try slot("08:00:00"))

        #expect(day.slots.map(\.hour) == [8, 9, 10])

        // 8 AM is the court's *second* published status, and it must appear
        // first here. Index arithmetic would produce `.available` — the 7 AM
        // answer, one hour out of place.
        #expect(day.statuses(for: court) == [.booked, .unpublished, .unpublished])
    }

    /// A payload that publishes the same slot time twice must not take the app
    /// down. No capture contains one, and the trapping dictionary initializer
    /// would crash on it — crashing on malformed input being the exact opposite
    /// of what the defensive decoding around this is for.
    @Test("A repeated slot time does not trap")
    func toleratesRepeatedSlotTime() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "07:00:00", "08:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 1, 1])]
        )
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        // Whatever the day comes out as, it comes out — and the row still has
        // one entry per visible slot.
        #expect(day.statuses(for: court).count == day.slots.count)

        // The first value published for a repeated time wins, rather than the
        // last. Either would be defensible; pinning one keeps it deliberate.
        #expect(day.statuses(for: court).first == .available)
    }

    /// A day built from nothing at all has no rows to hand back and does not
    /// crash reaching for one.
    @Test("A day resolved from an empty availability produces no rows")
    func resolvesEmptyAvailability() throws {
        let clock = FixedClock(now: try central(hour: 12))
        let empty = try availability(slots: [], courts: [])

        let day = VisibleDay.resolve(availability: empty, now: clock.now, startingAt: nil)

        #expect(day.slots.isEmpty)
        #expect(empty.courts.isEmpty)
    }

    /// Elapsed-slot filtering is global, so every court shares one slot list and
    /// the whole screen gets a column grid for free — no shared-scroll
    /// machinery, no per-facility filter.
    ///
    /// The row-length assertion below used to hold only *incidentally*: no court
    /// in either capture is short, so nothing would have been padded or
    /// truncated either way. Rows are now built by looking every visible slot up
    /// in the court's own list, so the same assertion is a guarantee about the
    /// construction rather than an observation about this particular capture.
    @Test("Every court in every facility gets the identical slot list")
    func sharesOneSlotListAcrossTheCapture() throws {
        let clock = FixedClock(now: try central(hour: 14, minute: 15))
        let data = try capturedAvailability(Fixture.anonymous)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.slots.count == 9)

        for facility in data.facilities {
            for court in facility.courts {
                #expect(
                    day.statuses(for: court).count == day.slots.count,
                    "\(court.name) has \(day.statuses(for: court).count) of \(day.slots.count)"
                )
            }
        }
    }

    /// The captured data publishes a readable status for all 1,280 of its
    /// slots, so nothing in it should reach the padding path at all. If this
    /// ever fails, either a capture was replaced or the lookup is dropping
    /// statuses it should have found.
    @Test("Nothing in the real capture is padded", arguments: Fixture.bothCaptures)
    func capturedRowsAreWhollyPublished(fixture: String) throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try capturedAvailability(fixture)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.slots.count == 16)
        #expect(data.degradedCourts.isEmpty)

        for court in data.courts {
            let row = day.statuses(for: court)

            #expect(row.count == 16, "\(court.name)")
            #expect(row.contains(.unpublished) == false, "\(court.name)")
        }
    }

    // MARK: - The start-time filter

    @Test("A start filter of six o'clock leaves only six and later")
    func appliesStartFilter() throws {
        let clock = FixedClock(now: try central(hour: 14))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: try slot("18:00:00"))

        #expect(day.slots.map(\.hour) == [18, 19, 20, 21, 22])
        #expect(day.isFinished == false)
    }

    /// The filter is applied to the whole published day rather than to what is
    /// left of it, so naming an earlier hour shows that hour. The elapsed rule
    /// governs the default view, not an explicit request.
    @Test("A start filter earlier than now reaches back to the hour it names")
    func reachesBackToTheNamedHour() throws {
        let clock = FixedClock(now: try central(hour: 14))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: try slot("07:00:00"))

        #expect(day.slots.count == 16)
        #expect(day.slots.first?.hour == 7)
    }

    /// An empty list because of a filter is not a day that has ended. Conflating
    /// them would tell a user who asked for evening slots at lunchtime to go
    /// home.
    @Test("A filter that leaves nothing does not report the day as finished")
    func distinguishesFilterFromEndOfDay() throws {
        let clock = FixedClock(now: try central(hour: 14))

        let day = VisibleDay.resolve(
            availability: try fullDay(), now: clock.now, startingAt: try slot("23:00:00"))

        #expect(day.slots.isEmpty)
        #expect(day.isFinished == false)
    }

    // MARK: - The facility summary

    /// D9's line, as a value rather than a sentence. Keeping it structured is
    /// what lets the count and the slot be asserted independently of wording.
    @Test("The summary names the earliest slot with any availability and how many")
    func summarisesEarliestAvailability() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00", "09:00:00"],
            courts: [
                (id: 1, name: "Some Tennis 1", statuses: [1, 0, 0]),
                (id: 2, name: "Some Tennis 2", statuses: [1, 1, 0]),
            ]
        )
        let facility = try #require(data.facilities.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)
        let summary = try #require(day.summary(for: facility))

        // 8:00 is the earliest slot anyone is free, and exactly one court is.
        #expect(summary.slot.displayString == "8 AM")
        #expect(summary.freeCourts == 1)
    }

    @Test("The summary counts every court free at that slot")
    func countsEveryFreeCourt() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00"],
            courts: [
                (id: 1, name: "Some Tennis 1", statuses: [0, 0]),
                (id: 2, name: "Some Tennis 2", statuses: [0, 1]),
                (id: 3, name: "Some Tennis 3", statuses: [1, 0]),
            ]
        )
        let facility = try #require(data.facilities.first)

        let summary = try #require(
            VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)
                .summary(for: facility))

        #expect(summary.slot.displayString == "7 AM")
        #expect(summary.freeCourts == 2)
    }

    @Test("A fully booked facility has no summary at all")
    func reportsNothingFreeWhenAllBooked() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00"],
            courts: [
                (id: 1, name: "Some Tennis 1", statuses: [1, 1]),
                (id: 2, name: "Some Tennis 2", statuses: [1, 1]),
            ]
        )
        let facility = try #require(data.facilities.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.summary(for: facility) == nil)

        // A fully booked facility is an ordinary day, not the end of one. The
        // screen must not tell the user to go home because one place is busy.
        #expect(day.isFinished == false)
    }

    /// An unrecognised status is not availability. A facility whose only
    /// non-booked entries are unknown has nothing to promise.
    @Test("An unrecognised status does not count as a free court")
    func doesNotCountUnknownAsFree() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [7])]
        )
        let facility = try #require(data.facilities.first)
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.statuses(for: court) == [.unknown(7)])
        #expect(day.summary(for: facility) == nil)
    }

    /// Nor is a padded hour. A header promising "1 of 1 free at 8 AM" on the
    /// strength of an hour the payload never mentioned would be the same wrong
    /// answer, phrased more confidently.
    @Test("A padded hour does not count as a free court")
    func doesNotCountUnpublishedAsFree() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [1])]
        )
        let facility = try #require(data.facilities.first)
        let court = try #require(data.courts.first)

        let day = VisibleDay.resolve(availability: data, now: clock.now, startingAt: nil)

        #expect(day.statuses(for: court) == [.booked, .unpublished])
        #expect(day.summary(for: facility) == nil)
    }

    /// The summary is a function of what is *visible*, so narrowing the filter
    /// past the earliest opening moves it rather than leaving it stale.
    @Test("The summary follows the start filter")
    func summaryRespectsTheFilter() throws {
        let clock = FixedClock(now: try central(hour: 6))
        let data = try availability(
            slots: ["07:00:00", "08:00:00", "09:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 0, 0])]
        )
        let facility = try #require(data.facilities.first)

        let day = VisibleDay.resolve(
            availability: data, now: clock.now, startingAt: try slot("09:00:00"))

        #expect(day.summary(for: facility)?.slot.displayString == "9 AM")
    }

    /// The slot length comes from the payload, not from this file. A 30-minute
    /// increment ends the 14:00 slot at 14:30, so at 14:45 it is gone while a
    /// 60-minute day would still be showing it.
    @Test("The published slot length decides what has elapsed")
    func honoursPublishedSlotLength() throws {
        let clock = FixedClock(now: try central(hour: 14, minute: 45))

        let hourly = try availability(
            slots: ["14:00:00", "15:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 0])],
            timeIncrement: 60
        )
        let halfHourly = try availability(
            slots: ["14:00:00", "15:00:00"],
            courts: [(id: 1, name: "Some Tennis 1", statuses: [0, 0])],
            timeIncrement: 30
        )

        #expect(
            VisibleDay.resolve(availability: hourly, now: clock.now, startingAt: nil)
                .slots.count == 2)
        #expect(
            VisibleDay.resolve(availability: halfHourly, now: clock.now, startingAt: nil)
                .slots.count == 1)
    }
}
