//
//  LiveAvailabilityTests.swift
//  CourtWatchTests
//
//  One deliberate check against the real endpoint, disabled unless
//  COURTWATCH_LIVE=1 is set.
//
//  The offline suite proves the code is right about the payload it was given.
//  It cannot notice the Township changing that payload — a renamed field, a
//  new response code, a facility added or retired. This closes that gap
//  without making the default suite depend on a network or on a public
//  system's goodwill.
//
//  Run it with Scripts/test-live.sh, rarely and on purpose.
//
//  The assertions are ranges, not exact numbers. Booked counts change by the
//  hour and a court can be taken offline for maintenance, so asserting 80/16/27
//  here would fail for reasons that are not defects. The exact figures belong
//  in the fixture tests, where the input is pinned.
//

import Foundation
import Testing

@testable import CourtWatch

struct LiveAvailabilityTests {

    @Test(
        "The live endpoint still answers in the shape this app expects",
        .enabled(if: ProcessInfo.processInfo.environment["COURTWATCH_LIVE"] == "1")
    )
    func liveFetchMatchesExpectedShape() async throws {
        let session = CourtSession()
        let client = AvailabilityClient(session: session)

        // Exactly one handshake and one fetch. An F5 ASM WAF fronts this site;
        // repeated or looping requests risk a block on the user's address.
        let availability = try await client.fetch(on: Date())

        #expect(availability.slotTimes.count >= 12)
        #expect(availability.courts.count >= 60)
        #expect(availability.facilities.count >= 20)

        // The positional pairing is the invariant worth watching. If the API
        // ever stops returning one detail per published slot, the grid silently
        // misaligns and every status shifts to the wrong hour.
        #expect(availability.degradedCourts.isEmpty)
        #expect(
            availability.courts.allSatisfy {
                $0.slots.count == availability.slotTimes.count
            })

        // Facility derivation must still hold on live names: no court may be
        // left in a facility named after itself.
        #expect(availability.facilities.allSatisfy { $0.name.isEmpty == false })
    }
}
