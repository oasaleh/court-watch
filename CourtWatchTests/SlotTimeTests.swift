import Foundation
import Testing

@testable import CourtWatch

/// The exact slot list the availability endpoint returns for a tennis court:
/// hourly from 7am to 10pm.
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

/// Argument lists for parameterized tests live on a `nonisolated` type: the
/// `arguments:` collection is evaluated outside the enclosing actor.
nonisolated enum SlotLengthCases {

    /// What the API published against the length the app should use.
    static let all: [(Int?, Int)] = [
        // The field is optional on the wire and can simply be absent.
        (nil, 60),

        // Nonsense. Either would mark every slot elapsed the instant it began
        // and tell a user at noon that the day was over.
        (0, 60),
        (-30, 60),

        // Honoured as published. 30 is the case that matters: it is the change
        // the Township could plausibly make, and the one a hardcoded hour would
        // get wrong for half an hour at a time.
        (30, 30),
        (60, 60),
        (90, 90),
    ]
}

/// An availability built from a hand-made payload.
///
/// All three committed fixtures publish `time_increment: 60`, so the absent,
/// zero and negative cases cannot be reached from captured data at all. Going
/// through the real decoder rather than constructing the domain type directly
/// keeps the wire hop — which is where the value could be lost — inside what is
/// being tested.
private func availability(timeIncrement: Int?) throws -> Availability {
    let increment = timeIncrement.map { ", \"time_increment\": \($0)" } ?? ""

    let json = """
        {
          "headers": { "response_code": "0000" },
          "body": {
            "availability": {
              "time_slots": ["07:00:00", "08:00:00"],
              "resources": []\(increment)
            }
          }
        }
        """

    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self, from: Data(json.utf8))

    return Availability(envelope: envelope)
}

struct SlotTimeTests {

    @Test("An afternoon slot parses to its wall-clock hour and minute")
    func parsesAfternoonSlot() throws {
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        #expect(slot.hour == 14)
        #expect(slot.minute == 0)
    }

    @Test("A morning slot displays without a leading zero")
    func displaysMorningSlot() throws {
        let slot = try #require(SlotTime(apiString: "07:00:00"))

        #expect(slot.displayString == "7 AM")
    }

    @Test("A late slot displays as an evening 12-hour time")
    func displaysLateSlot() throws {
        let slot = try #require(SlotTime(apiString: "22:00:00"))

        #expect(slot.displayString == "10 PM")
    }

    /// The endpoint is undocumented and unversioned, so a slot it stops
    /// publishing in the expected shape must not take the app down with it.
    @Test("A malformed slot string yields no slot rather than trapping")
    func rejectsMalformedSlot() {
        #expect(SlotTime(apiString: "garbage") == nil)
    }

    @Test("Every published slot parses, and they order by time of day")
    func parsesEveryPublishedSlot() throws {
        let slots = try publishedSlots.map {
            try #require(SlotTime(apiString: $0), "Failed to parse \($0)")
        }

        #expect(slots.count == 16)
        #expect(slots == slots.sorted())
        #expect(slots.first?.hour == 7)
        #expect(slots.last?.hour == 22)
    }

    /// Parsing a bare time lands on a reference day, not today, so anchoring is
    /// mandatory before a slot can be compared against the current moment.
    @Test("A slot anchors onto the given Central day at its own wall-clock time")
    func anchorsOntoDay() throws {
        let day = try central(hour: 0)
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        let anchored = slot.date(on: day)
        let parts = CourtTime.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: anchored)

        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 26)
        #expect(parts.hour == 14)
        #expect(parts.minute == 0)
        #expect(CourtTime.display.string(from: anchored) == "2:00 PM")
    }

    /// The 13:20 case, recomputed under the ruled semantics.
    ///
    /// This assertion moved. It used to expect 9 slots beginning at 2 PM,
    /// because the 1 PM slot had started and was therefore "past". Under the
    /// rule a slot lives until its hour ends, so the 1 PM hour is still in
    /// progress at 1:20 and the answer is 10 slots beginning at 1 PM.
    ///
    /// Research §5 records the old figure of 9 as verified. It describes the
    /// superseded rule and is not a source of expected values here.
    @Test("Only the slots that have not yet ended count as upcoming")
    func filtersSlotsAlreadyElapsed() throws {
        let clock = FixedClock(now: try central(hour: 13, minute: 20))
        let slots = try publishedSlots.map { try #require(SlotTime(apiString: $0)) }

        let upcoming = slots.filter {
            $0.isElapsed(now: clock.now, slotMinutes: 60) == false
        }

        #expect(clock.today == clock.now)
        #expect(upcoming.count == 10)
        #expect(upcoming.first?.displayString == "1 PM")
        #expect(upcoming.last?.displayString == "10 PM")
    }

    /// The ruling itself, at the boundary it turns on.
    ///
    /// The middle assertion inverts what Phase 1 pinned. A slot one minute into
    /// its hour used to count as past; it now counts as live, because a court
    /// free until 3 PM is still usable at 2:01. The old doc comment — "a
    /// slot happening exactly now has not passed" — described the start
    /// boundary, which is no longer the boundary that decides anything.
    @Test("A slot in progress has not elapsed, and ends exactly on the hour")
    func treatsInProgressSlotAsLive() throws {
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        // Before it starts.
        #expect(slot.isElapsed(now: try central(hour: 13, minute: 59), slotMinutes: 60) == false)

        // Exactly as it starts.
        #expect(slot.isElapsed(now: try central(hour: 14), slotMinutes: 60) == false)

        // One minute in — this is the assertion that inverted.
        #expect(slot.isElapsed(now: try central(hour: 14, minute: 1), slotMinutes: 60) == false)

        // One minute before it ends.
        #expect(slot.isElapsed(now: try central(hour: 14, minute: 59), slotMinutes: 60) == false)

        // Exactly as it ends.
        #expect(slot.isElapsed(now: try central(hour: 15), slotMinutes: 60))

        // Well after.
        #expect(slot.isElapsed(now: try central(hour: 16), slotMinutes: 60))
    }

    /// The length is honoured, not assumed.
    ///
    /// Every fixture publishes 60, so a hardcoded hour would pass every other
    /// test in this file. This is the case that would fail if someone quietly
    /// reintroduced one.
    @Test("A thirty-minute slot ends at the half hour")
    func honoursNonDefaultSlotLength() throws {
        let slot = try #require(SlotTime(apiString: "14:00:00"))

        #expect(slot.isElapsed(now: try central(hour: 14, minute: 29), slotMinutes: 30) == false)
        #expect(slot.isElapsed(now: try central(hour: 14, minute: 30), slotMinutes: 30))

        // The same instant under a 60-minute length is still live, which is
        // what proves the parameter is doing the work rather than the clock.
        #expect(slot.isElapsed(now: try central(hour: 14, minute: 30), slotMinutes: 60) == false)
    }

    @Test("The published slot length reaches the domain type")
    func readsSlotLengthFromTheCapture() throws {
        let envelope = try JSONDecoder().decode(
            AvailabilityEnvelope.self, from: try Fixture.data(Fixture.anonymous))

        #expect(Availability(envelope: envelope).slotMinutes == 60)
    }

    /// Absent, zero and negative all degrade to the measured 60. No fixture can
    /// produce any of them — all three publish 60 — so these envelopes are
    /// built by hand.
    @Test("A missing or nonsensical increment falls back to sixty", arguments: SlotLengthCases.all)
    func guardsSlotLength(published: Int?, expected: Int) throws {
        #expect(try availability(timeIncrement: published).slotMinutes == expected)
    }
}
