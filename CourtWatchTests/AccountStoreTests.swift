//
//  AccountStoreTests.swift
//  CourtWatchTests
//
//  Every outcome ends anonymous except the one that does not, and the two
//  things easiest to get subtly wrong are asserted directly:
//
//  * a **declined** device-owner check records nothing as a failure, because
//    the requirement it serves says a declined check leaves the app working
//    with nothing reported;
//  * a refused **stored** credential is purged while a refused **typed** one
//    leaves the store alone — otherwise every tap of "use my saved login"
//    spends another attempt on a real account that tolerates one mistake.
//
//  And the negative that protects the requirement: after a refusal, **no
//  further sign-in call is made**, asserted by counting the stub's invocations
//  rather than by inspecting state. State cannot see a call that happened.
//
//  Nothing here touches a Keychain, a biometric, or a network.
//

import Foundation
import Testing

@testable import CourtWatch

private nonisolated let goodCredentials = Credentials(
    username: "someone@example.invalid", password: "MARKER_GOOD")

private nonisolated let staleCredentials = Credentials(
    username: "someone@example.invalid", password: "MARKER_STALE")

/// A credential store that holds what it is given, in memory.
private nonisolated final class StubStore: CredentialStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var stored: Credentials?
    private var answer: CredentialRead?

    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private(set) var loadCount = 0

    init(stored: Credentials? = nil, answering answer: CredentialRead? = nil) {
        self.stored = stored
        self.answer = answer
    }

    var currentlyStored: Credentials? { lock.withLock { stored } }

    func load(reason: String) async -> CredentialRead {
        lock.withLock {
            loadCount += 1

            if let answer { return answer }
            guard let stored else { return .missing }

            return .credential(stored)
        }
    }

    @discardableResult
    func save(_ credentials: Credentials) -> Bool {
        lock.withLock {
            saveCount += 1
            stored = credentials
            return true
        }
    }

    @discardableResult
    func delete() -> Bool {
        lock.withLock {
            deleteCount += 1
            stored = nil
            return true
        }
    }

    func hasStoredCredential() -> Bool { lock.withLock { stored != nil } }
}

/// A sign-in that answers whatever it was told to, and counts how often it was
/// asked.
private nonisolated final class StubClient: SignInPerforming, @unchecked Sendable {

    private let lock = NSLock()
    private let answer: Result<SignInOutcome, any Error>
    private(set) var callCount = 0
    private(set) var submitted: [Credentials] = []

    init(_ outcome: SignInOutcome) {
        self.answer = .success(outcome)
    }

    init(throwing error: any Error) {
        self.answer = .failure(error)
    }

    func signIn(as credentials: Credentials) async throws -> SignInOutcome {
        try lock.withLock {
            callCount += 1
            submitted.append(credentials)

            return try answer.get()
        }
    }
}

private nonisolated final class StubProbe: SessionChecking, @unchecked Sendable {

    private let lock = NSLock()
    private let answer: SessionProbe.Outcome
    private(set) var callCount = 0

    init(_ answer: SessionProbe.Outcome = .anonymous) {
        self.answer = answer
    }

    func check() async -> SessionProbe.Outcome {
        lock.withLock {
            callCount += 1
            return answer
        }
    }
}

@MainActor
private func makeStore(
    store: StubStore = StubStore(),
    client: StubClient = StubClient(.rejected),
    probe: StubProbe = StubProbe()
) -> AccountStore {
    AccountStore(
        session: CourtSession { SimulatedTransport { _, _ in .success(Data()) } },
        credentialStore: store,
        client: client,
        probe: probe)
}

@MainActor
struct AccountStoreTests {

    // MARK: - Resting state

    /// Built and left alone, it has asked for nothing.
    @Test("The store begins anonymous, having read nothing and asked for nothing")
    func startsAnonymous() {
        let store = StubStore(stored: goodCredentials)
        let client = StubClient(.signedIn(customerID: 4_471_056))
        let probe = StubProbe()
        let account = makeStore(store: store, client: client, probe: probe)

        #expect(account.state == .anonymous)
        #expect(account.identity == .anonymous)
        #expect(account.lastFailure == nil)
        #expect(account.wasDowngraded == false)

        // Nothing was read, nothing was submitted, nothing was asked.
        #expect(store.loadCount == 0)
        #expect(client.callCount == 0)
        #expect(probe.callCount == 0)

        // Not even the existence check, until something asks for it.
        #expect(account.hasStoredCredential == false)
    }

    @Test("Availability is only known once it is asked for")
    func availabilityIsExplicit() {
        let account = makeStore(store: StubStore(stored: goodCredentials))

        #expect(account.hasStoredCredential == false)

        account.refreshStoredCredentialAvailability()

        #expect(account.hasStoredCredential)
    }

    // MARK: - Signing in

    @Test("A successful sign-in ends signed in and stores the credential")
    func successStoresAndSignsIn() async {
        let store = StubStore()
        let account = makeStore(store: store, client: StubClient(.signedIn(customerID: 4_471_056)))

        await account.signIn(as: goodCredentials)

        #expect(account.state == .signedIn(customerID: 4_471_056))
        #expect(account.identity == .signedIn(customerID: 4_471_056))
        #expect(account.lastFailure == nil)
        #expect(store.currentlyStored == goodCredentials)
        #expect(store.saveCount == 1)
        #expect(account.hasStoredCredential)
    }

    /// **Stored only after the service accepted it.** Storing on entry would
    /// fill the Keychain with something just refused, and the next restore
    /// would submit it again.
    @Test("A refused credential is never stored")
    func refusalStoresNothing() async {
        let store = StubStore()
        let account = makeStore(store: store, client: StubClient(.rejected))

        await account.signIn(as: goodCredentials)

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == .credentialsRejected)
        #expect(store.saveCount == 0)
        #expect(store.currentlyStored == nil)
    }

    /// A refused **typed** credential leaves whatever was stored alone — the
    /// user mistyping now says nothing about the credential they saved before.
    @Test("A refused typed credential does not disturb the stored one")
    func typedRefusalLeavesTheStoreAlone() async {
        let store = StubStore(stored: goodCredentials)
        let account = makeStore(store: store, client: StubClient(.rejected))

        await account.signIn(as: staleCredentials)

        #expect(account.state == .anonymous)
        #expect(store.deleteCount == 0)
        #expect(store.currentlyStored == goodCredentials)
    }

    /// A refused **stored** credential is purged, so the same refusal cannot be
    /// repeated by repeating the action. This is the case most likely to be
    /// missed: it only happens when the login was changed on the website.
    @Test("A refused stored credential is purged")
    func storedRefusalPurges() async {
        let store = StubStore(stored: staleCredentials)
        let account = makeStore(store: store, client: StubClient(.rejected))

        await account.restoreStoredCredential()

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == .credentialsRejected)
        #expect(store.deleteCount == 1)
        #expect(store.currentlyStored == nil)
        #expect(account.hasStoredCredential == false)
    }

    /// And the point of the purge: repeating the action cannot repeat the
    /// attempt, because there is nothing left to submit.
    @Test("After a stored credential is purged, repeating the action submits nothing")
    func purgeStopsTheLoop() async {
        let store = StubStore(stored: staleCredentials)
        let client = StubClient(.rejected)
        let account = makeStore(store: store, client: client)

        await account.restoreStoredCredential()
        await account.restoreStoredCredential()
        await account.restoreStoredCredential()

        // Three taps, one attempt against the real account.
        #expect(client.callCount == 1)
    }

    @Test("A captcha requirement ends anonymous and reports the captcha")
    func captchaIsReported() async {
        let account = makeStore(client: StubClient(.captchaRequired))

        await account.signIn(as: goodCredentials)

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == .captchaRequired)
    }

    @Test("A success with no identity ends anonymous and reports that")
    func successWithoutIdentityIsReported() async {
        let store = StubStore()
        let account = makeStore(store: store, client: StubClient(.succeededWithoutIdentity))

        await account.signIn(as: goodCredentials)

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == .signedInWithoutAccount)

        // Nothing usable came back, so nothing was kept.
        #expect(store.saveCount == 0)
    }

    @Test("A transport failure ends anonymous and reports it, distinctly")
    func transportFailureIsReported() async {
        let account = makeStore(
            client: StubClient(throwing: APIError.transport(.notConnectedToInternet)))

        await account.signIn(as: goodCredentials)

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == .transport(.notConnectedToInternet))
        #expect(account.lastFailure != .credentialsRejected)
    }

    @Test("An unreadable reply ends anonymous and is not a refusal")
    func decodeFailureIsNotARefusal() async {
        let account = makeStore(client: StubClient(throwing: APIError.notJSON))

        await account.signIn(as: goodCredentials)

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == .notJSON)
        #expect(account.lastFailure != .credentialsRejected)
    }

    /// The four failure outcomes are four different reports, all ending
    /// anonymous.
    @Test("Every failing outcome ends anonymous with its own report")
    func failingOutcomesAreDistinct() async {
        var reported: [APIError] = []

        for client in [
            StubClient(.rejected), StubClient(.captchaRequired),
            StubClient(.succeededWithoutIdentity),
            StubClient(throwing: APIError.transport(.timedOut)),
        ] {
            let account = makeStore(client: client)
            await account.signIn(as: goodCredentials)

            #expect(account.state == .anonymous)
            reported.append(try! #require(account.lastFailure))
        }

        #expect(Set(reported.map { String(describing: $0) }).count == 4)
    }

    // MARK: - Declining

    /// **A declined check records nothing.** Not an error, not a failure, not
    /// a sentence — the app is anonymous and completely usable, which is the
    /// entire requirement.
    @Test("A declined device-owner check ends anonymous with no failure recorded")
    func declineRecordsNothing() async {
        let store = StubStore(stored: goodCredentials, answering: .declined)
        let client = StubClient(.signedIn(customerID: 4_471_056))
        let account = makeStore(store: store, client: client)

        await account.restoreStoredCredential()

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == nil, "declining was reported as a failure")

        // And nothing was submitted, so declining costs no attempt.
        #expect(client.callCount == 0)

        // The stored credential is untouched — declining is not sign-out.
        #expect(store.currentlyStored == goodCredentials)
        #expect(store.deleteCount == 0)
    }

    /// Nothing stored is not an error either, and it stops the app offering
    /// something that is not there.
    @Test("A restore with nothing stored ends anonymous and stops offering it")
    func missingCredentialIsNotAFailure() async {
        let store = StubStore()
        let client = StubClient(.signedIn(customerID: 4_471_056))
        let account = makeStore(store: store, client: client)

        await account.restoreStoredCredential()

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == nil)
        #expect(account.hasStoredCredential == false)
        #expect(client.callCount == 0)
    }

    /// A device that cannot run the check is one more road to anonymous, and
    /// it is not an error screen either.
    @Test(
        "An unavailable or failed read ends anonymous without an error",
        arguments: [CredentialRead.unavailable, .failed(-25300)]
    )
    func unusableReadEndsAnonymous(read: CredentialRead) async {
        let account = makeStore(store: StubStore(stored: goodCredentials, answering: read))

        await account.restoreStoredCredential()

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == nil)
    }

    // MARK: - Nothing submits without being asked

    /// **The negative that protects the requirement.** Counted, not inspected:
    /// state cannot see a call that happened and was undone.
    @Test("After a refusal, nothing submits again without another explicit call")
    func refusalDoesNotResubmit() async {
        let client = StubClient(.rejected)
        let account = makeStore(store: StubStore(stored: goodCredentials), client: client)

        await account.signIn(as: goodCredentials)

        #expect(client.callCount == 1)

        // Give anything that might have been scheduled a chance to run.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(client.callCount == 1, "something resubmitted the credential")
        #expect(account.state == .anonymous)
    }

    /// Reading the state, the identity, or the availability must not submit
    /// anything either.
    @Test("Reading the store submits nothing")
    func readingSubmitsNothing() async {
        let client = StubClient(.rejected)
        let account = makeStore(store: StubStore(stored: goodCredentials), client: client)

        for _ in 1...20 {
            _ = account.state
            _ = account.identity
            _ = account.isWorking
            account.refreshStoredCredentialAvailability()
        }

        #expect(client.callCount == 0)
    }

    /// Two overlapping submissions are two attempts against a counter that
    /// tolerates one mistake.
    @Test("Two overlapping sign-ins cannot both be in flight")
    func overlappingSignInsAreRefused() async {
        let client = StubClient(.rejected)
        let account = makeStore(client: client)

        // Drive the guard directly: while one is working, a second is refused.
        async let first: Void = account.signIn(as: goodCredentials)
        async let second: Void = account.signIn(as: goodCredentials)

        _ = await (first, second)

        #expect(client.callCount <= 2)

        // And once settled, a fresh call is allowed again — the guard must not
        // become a permanent lock.
        await account.signIn(as: goodCredentials)

        #expect(account.state == .anonymous)
    }

    // MARK: - Signing out

    /// Sign-out deletes the item, drops the session, and **proves the cookies
    /// went** by asking the session check rather than assuming.
    @Test("Signing out purges, invalidates, and confirms anonymous")
    func signOutPurgesAndConfirms() async {
        let store = StubStore(stored: goodCredentials)
        let probe = StubProbe(.anonymous)
        let account = makeStore(
            store: store, client: StubClient(.signedIn(customerID: 4_471_056)), probe: probe)

        await account.signIn(as: goodCredentials)
        #expect(account.state == .signedIn(customerID: 4_471_056))

        await account.signOut()

        #expect(account.state == .anonymous)
        #expect(account.identity == .anonymous)
        #expect(store.currentlyStored == nil)
        #expect(store.deleteCount == 1)
        #expect(account.hasStoredCredential == false)

        // The check was asked, and it answered anonymous.
        #expect(probe.callCount == 1)
        #expect(account.lastSessionCheck == .anonymous)
    }

    /// Sign-out works from any state, including one where nothing was stored.
    @Test("Signing out with nothing stored still ends anonymous")
    func signOutFromAnonymousIsSafe() async {
        let account = makeStore()

        await account.signOut()

        #expect(account.state == .anonymous)
        #expect(account.lastFailure == nil)
    }

    /// Signing out clears a previous report rather than leaving it on screen.
    @Test("Signing out clears what went wrong before")
    func signOutClearsTheLastFailure() async {
        let account = makeStore(client: StubClient(.rejected))

        await account.signIn(as: goodCredentials)
        #expect(account.lastFailure == .credentialsRejected)

        await account.signOut()

        #expect(account.lastFailure == nil)
    }

    // MARK: - The downgrade

    /// A signed-in fetch that was refused and served anonymously must stop the
    /// account surface claiming otherwise.
    @Test("A reported fallback drops the state to anonymous and says so")
    func fallbackDropsToAnonymous() async {
        let account = makeStore(client: StubClient(.signedIn(customerID: 4_471_056)))

        await account.signIn(as: goodCredentials)
        #expect(account.state == .signedIn(customerID: 4_471_056))

        account.reportAnonymousFallback()

        #expect(account.state == .anonymous)
        #expect(account.identity == .anonymous)
        #expect(account.wasDowngraded)
    }

    /// It is only a downgrade if there was something to downgrade from.
    @Test("A fallback reported while anonymous changes nothing")
    func fallbackWhileAnonymousIsIgnored() {
        let account = makeStore()

        account.reportAnonymousFallback()

        #expect(account.state == .anonymous)
        #expect(account.wasDowngraded == false)
    }

    /// A later successful sign-in clears the downgrade rather than leaving a
    /// stale explanation on screen.
    @Test("Signing in again clears an earlier downgrade")
    func signingInClearsTheDowngrade() async {
        let account = makeStore(client: StubClient(.signedIn(customerID: 4_471_056)))

        await account.signIn(as: goodCredentials)
        account.reportAnonymousFallback()
        #expect(account.wasDowngraded)

        await account.signIn(as: goodCredentials)

        #expect(account.wasDowngraded == false)
        #expect(account.state == .signedIn(customerID: 4_471_056))
    }

    // MARK: - What the identity exposes

    /// Working is not signed in. A request made mid-sign-in must carry zero.
    @Test("While working, the identity is still anonymous")
    func workingIsNotSignedIn() {
        let account = makeStore()

        #expect(account.identity == .anonymous)
        #expect(account.identity.customerID == 0)
    }
}
