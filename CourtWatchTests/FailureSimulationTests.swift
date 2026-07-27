//
//  FailureSimulationTests.swift
//  CourtWatchTests
//
//  **This file is what makes the checkpoint trustworthy.**
//
//  Without it, a human approval could rest on a harness that produces something
//  other than what it claims — a screen approved as "the block page sentence"
//  while the transport was actually sending a schema change — and the whole
//  exercise would prove nothing. So every scenario is driven through a real
//  `AvailabilityClient` and asserted to produce exactly the error the table
//  promises.
//
//  The stale-token scenario additionally asserts the request counts, because
//  that is the assertion proving the harness exercises the client's real
//  re-handshake and its real one-shot retry rather than short-circuiting to the
//  outcome.
//
//  Every scenario is offline by construction: `SimulatedTransport` holds no
//  `URLSession` and answers from a closure. Nothing here can let a live request
//  into the default suite, which stays hermetic — the one test that reaches the
//  network stays behind `COURTWATCH_LIVE`.
//

import Foundation
import Testing

@testable import CourtWatch

private func testDay() throws -> Date {
    try #require(CourtTime.calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
}

private func client(for scenario: FailureSimulation.Scenario) -> (
    AvailabilityClient, SimulatedTransport
) {
    let transport = FailureSimulation.makeTransport(for: scenario)

    return (AvailabilityClient(session: CourtSession { transport }), transport)
}

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum FailureSimulationCases {

    /// Each failing scenario against the error it claims to produce.
    static let failures: [(FailureSimulation.Scenario, APIError)] = [
        (.offline, .transport(.notConnectedToInternet)),
        (.timeout, .transport(.timedOut)),
        (.blocked, .notJSON),
        (.refused, .service(code: "1507", message: "Invalid request")),
        (.expired, .sessionExpired(code: "0012")),
        (.empty, .slotTimesMissing),
    ]

    /// Values a person might type that are not scenarios.
    static let notScenarios = ["", "  ", "nonsense", "Offline", "OFFLINE", "time-out", "0", "true"]
}

struct FailureSimulationTests {

    // MARK: - Selection

    /// Unset means no simulation and a normal fetch.
    @Test("With the variable unset there is no simulation")
    func unsetMeansNoSimulation() {
        #expect(FailureSimulation.scenario(from: nil) == nil)
    }

    /// A typo at the checkpoint must not be mistaken for a broken app. The
    /// harness defaults to reality rather than failing closed.
    @Test(
        "An unrecognised value is no simulation rather than a crash",
        arguments: FailureSimulationCases.notScenarios
    )
    func unrecognisedValueMeansNoSimulation(value: String) {
        #expect(FailureSimulation.scenario(from: value) == nil)
    }

    @Test("Every scenario name resolves to itself")
    func everyScenarioResolves() {
        for scenario in FailureSimulation.Scenario.allCases {
            #expect(FailureSimulation.scenario(from: scenario.rawValue) == scenario)
        }
    }

    /// Ten scenarios, so a new one cannot be added without this file noticing.
    @Test("The scenario list is what the checkpoint expects")
    func scenarioListIsComplete() {
        #expect(
            Set(FailureSimulation.Scenario.allCases.map(\.rawValue)) == [
                "offline", "timeout", "blocked", "garbled", "refused",
                "expired", "empty", "degraded", "warning", "stale",
            ])
    }

    // MARK: - Each scenario produces exactly what it claims

    @Test(
        "Each failing scenario produces the error it claims",
        arguments: FailureSimulationCases.failures
    )
    func scenarioProducesItsError(scenario: FailureSimulation.Scenario, expected: APIError) async throws {
        let (client, _) = client(for: scenario)

        await #expect(throws: expected) {
            try await client.fetch(on: try testDay())
        }
    }

    /// `garbled` is asserted separately because the decoder's description is
    /// not predictable, so the case rather than the value is what matters —
    /// and what matters most is that it is **not** the same error as `blocked`.
    @Test("The garbled scenario is a schema change, distinct from a block page")
    func garbledIsADecodingFailure() async throws {
        let (client, _) = client(for: .garbled)

        do {
            _ = try await client.fetch(on: try testDay())
            Issue.record("expected a decoding failure")
        } catch let error as APIError {
            if case .decoding = error {} else {
                Issue.record("expected .decoding, got \(error)")
            }
        }
    }

    /// The two most easily confused screens must be driven by two different
    /// errors, or the checkpoint is comparing one sentence with itself.
    @Test("Blocked and garbled are genuinely different failures")
    func blockedAndGarbledDiffer() async throws {
        let (blockedClient, _) = client(for: .blocked)
        let (garbledClient, _) = client(for: .garbled)

        var blocked: APIError?
        var garbled: APIError?

        do { _ = try await blockedClient.fetch(on: try testDay()) } catch let e as APIError {
            blocked = e
        }
        do { _ = try await garbledClient.fetch(on: try testDay()) } catch let e as APIError {
            garbled = e
        }

        #expect(blocked != nil)
        #expect(garbled != nil)
        #expect(blocked != garbled)

        // And the sentences they produce differ, which is what the human is
        // actually being asked to judge.
        #expect(
            ErrorPresentation.of(try #require(blocked)).title
                != ErrorPresentation.of(try #require(garbled)).title)
    }

    /// Offline and timeout must not collapse into one screen either.
    @Test("Offline and timeout are different failures and different sentences")
    func offlineAndTimeoutDiffer() async throws {
        let offline = APIError.transport(.notConnectedToInternet)
        let timeout = APIError.transport(.timedOut)

        let (offlineClient, _) = client(for: .offline)
        let (timeoutClient, _) = client(for: .timeout)

        await #expect(throws: offline) { try await offlineClient.fetch(on: try testDay()) }
        await #expect(throws: timeout) { try await timeoutClient.fetch(on: try testDay()) }

        #expect(ErrorPresentation.of(offline).title != ErrorPresentation.of(timeout).title)
    }

    // MARK: - The one that runs the real retry

    /// **The assertion proving the harness drives the real thing.**
    ///
    /// Two handshakes and two POSTs, exactly as `AvailabilityClientTests` pins
    /// for the genuine client. A harness that short-circuited to
    /// `sessionExpired` would pass an error-type check and fail this.
    @Test("The stale-token scenario re-handshakes once, replays once, and stops")
    func expiredDrivesTheRealRetry() async throws {
        let (client, transport) = client(for: .expired)

        await #expect(throws: APIError.sessionExpired(code: "0012")) {
            try await client.fetch(on: try testDay())
        }

        #expect(transport.postCount == 2, "one replay, and only one")
        #expect(transport.requestCount == 4, "two handshakes and two POSTs")
    }

    /// The terminal guard holds: nothing further is issued after it gives up.
    @Test("The stale-token scenario issues nothing after it stops")
    func expiredStopsCompletely() async throws {
        let (client, transport) = client(for: .expired)

        await #expect(throws: APIError.self) { try await client.fetch(on: try testDay()) }
        try await Task.sleep(for: .milliseconds(50))

        #expect(transport.requestCount == 4)
    }

    // MARK: - The two that are not failures at all

    /// `degraded` must **decode** rather than throw — it is the tolerant path,
    /// not an error path — and must report both kinds of incompleteness.
    @Test("The degraded scenario decodes, and reports short and unreadable courts")
    func degradedDecodesAndReports() async throws {
        let (client, _) = client(for: .degraded)

        let availability = try await client.fetch(on: try testDay())

        // Seven courts survive; the eighth could not be read.
        #expect(availability.courts.count == 7)
        #expect(availability.unreadableCourts == 1)
        #expect(
            availability.degradedCourts == ["Bear Branch Tennis 3", "Meadowlake Tennis 1"])
        #expect(availability.slotTimes.count == 16)
    }

    /// The harness has to show a grid whatever the person running it has
    /// favorited. A payload naming one facility shows them the invitation
    /// screen instead of the thing they are trying to judge — which is how
    /// three of the ten scenarios became unverifiable in practice.
    @Test(
        "Every data-bearing scenario spans several real facilities",
        arguments: [
            FailureSimulation.Scenario.degraded, .warning, .stale,
        ]
    )
    func dataScenariosSpanFacilities(scenario: FailureSimulation.Scenario) async throws {
        let (client, _) = client(for: scenario)

        let availability = try await client.fetch(on: try testDay())
        let names = Set(availability.facilities.map(\.name))

        #expect(names.count >= 4, "\(scenario.rawValue) covered only \(names)")

        // Named from the real capture, so a favorite made against the live API
        // resolves against the simulation too.
        for expected in [
            "Bear Branch Tennis", "Shadowbend Tennis", "Meadowlake Tennis", "Falconwing Tennis",
        ] {
            #expect(names.contains(expected), "\(scenario.rawValue) is missing \(expected)")
        }
    }

    /// The unreadable statuses in the middle of Shadowbend's second court hold
    /// their positions — the same guarantee `DefensiveDecodingTests` pins,
    /// asserted here through the harness the human will actually be looking at.
    @Test("The degraded scenario's unreadable hours keep their own places")
    func degradedKeepsPositions() async throws {
        let (client, _) = client(for: .degraded)

        let availability = try await client.fetch(on: try testDay())
        let court = try #require(availability.courts.first { $0.name == "Shadowbend Tennis 2" })

        #expect(court.slots.count == 16)

        // 11 AM, noon and 1 PM are the unreadable ones, and nothing later moved.
        let unknownHours = court.slots.filter { $0.status == .unpublished }.map(\.time.hour)

        #expect(unknownHours == [11, 12, 13])

        // The 2 PM status is the one published for 2 PM, not the one before it.
        let twoPM = try #require(court.slots.first { $0.time.hour == 14 })
        #expect(twoPM.status == .booked)
    }

    /// The short court is padded to the full day rather than drawing blanks.
    @Test("The degraded scenario's short court is padded to the whole day")
    func degradedShortCourtIsPadded() async throws {
        let (client, _) = client(for: .degraded)

        let availability = try await client.fetch(on: try testDay())
        let clock = FixedClock(
            now: try #require(
                CourtTime.calendar.date(
                    from: DateComponents(year: 2026, month: 7, day: 26, hour: 6))))

        let day = VisibleDay.resolve(
            availability: availability, now: clock.now, startingAt: nil)
        let short = try #require(availability.courts.first { $0.name == "Bear Branch Tennis 3" })

        #expect(day.statuses(for: short).count == day.slots.count)
        #expect(day.statuses(for: short).suffix(6).allSatisfy { $0 == .unpublished })
    }

    /// `warning` produces exactly one notice: the residency one is suppressed,
    /// the unaccounted one is not.
    @Test("The warning scenario produces exactly one notice")
    func warningProducesOneNotice() async throws {
        let (client, _) = client(for: .warning)

        let availability = try await client.fetch(on: try testDay())

        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: availability.degradedCourts,
            unreadableCourts: availability.unreadableCourts,
            warnings: availability.courts.flatMap(\.warnings)
        )

        #expect(lines.count == 1)
        #expect(try #require(lines.first).contains("closed for maintenance"))
    }

    /// The degraded scenario produces exactly two notices — one for the short
    /// courts in the plural, one for the unreadable court in the singular —
    /// which is what makes both forms visible at the checkpoint.
    @Test("The degraded scenario produces both notice kinds, correctly numbered")
    func degradedProducesBothNoticeKinds() async throws {
        let (client, _) = client(for: .degraded)

        let availability = try await client.fetch(on: try testDay())

        let lines = NoticeText.lines(
            unmatchedFavorites: [],
            degradedCourts: availability.degradedCourts,
            unreadableCourts: availability.unreadableCourts,
            warnings: availability.courts.flatMap(\.warnings)
        )

        #expect(lines.count == 2)
        #expect(lines.contains { $0.contains("2 courts") })
        #expect(lines.contains { $0.contains("1 court ") })
    }

    /// The good payload underlying `stale` and `warning` produces no notices at
    /// all, which is the state a normal launch shows.
    @Test("The warning scenario's courts are otherwise entirely ordinary")
    func warningPayloadIsOtherwiseClean() async throws {
        let (client, _) = client(for: .warning)

        let availability = try await client.fetch(on: try testDay())

        #expect(availability.courts.count == 7)
        #expect(availability.degradedCourts.isEmpty)
        #expect(availability.unreadableCourts == 0)
    }

    // MARK: - One good response, then nothing

    /// `stale` is a claim about the *sequence* of loads, so it takes two
    /// fetches to assert: the first must succeed and the second must fail, or
    /// the failed-refresh line cannot be seen at the checkpoint at all.
    @Test("The stale scenario succeeds once and fails afterwards")
    func staleSucceedsThenFails() async throws {
        let transport = FailureSimulation.makeTransport(for: .stale)
        let client = AvailabilityClient(session: CourtSession { transport })

        let first = try await client.fetch(on: try testDay())

        #expect(first.courts.count == 7)
        #expect(first.slotTimes.count == 16)

        // Every later attempt, through a fresh session exactly as the app makes
        // one on each load.
        let refreshed = AvailabilityClient(session: CourtSession { transport })

        await #expect(throws: APIError.transport(.notConnectedToInternet)) {
            try await refreshed.fetch(on: try testDay())
        }
    }

    // MARK: - Hermetic by construction

    /// Nothing here may reach the internet. Asserted by driving every scenario
    /// to completion and requiring each to have answered from the closure — a
    /// `URLSession` would have to have been constructed to do otherwise, and
    /// there is none in the file.
    @Test("No scenario reaches the network", arguments: FailureSimulation.Scenario.allCases)
    func noScenarioTouchesTheNetwork(scenario: FailureSimulation.Scenario) async throws {
        let (client, transport) = client(for: scenario)

        _ = try? await client.fetch(on: try testDay())

        // Every scenario answers at least the handshake, and none can answer
        // from anywhere but the closure it was built with.
        #expect(transport.requestCount >= 1, "\(scenario.rawValue)")
    }
}
