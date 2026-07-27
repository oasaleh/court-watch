//
//  CredentialStoreTests.swift
//  CourtWatchTests
//
//  This file asserts the **outcome algebra**, not the Keychain.
//
//  Research §8 is emphatic and correct: there is no biometric hardware on a
//  test runner, the device-owner check would hang rather than fail, and a
//  suite that touched the real Keychain would be neither hermetic nor
//  repeatable. So the real store is exercised by hand at the checkpoint, where
//  a person can watch the prompt appear, and what is asserted here is the part
//  that can be got wrong silently: which outcome means what, and that they stay
//  distinguishable.
//
//  The distinction this file exists to protect is **declined versus failed**.
//  The requirement says a declined check leaves the app anonymous and fully
//  usable, with nothing reported as an error. If those two ever collapse into
//  one case, that requirement becomes unimplementable and the app grows an
//  error screen where it should have a working grid.
//
//  Nothing here imports `Security` or `LocalAuthentication`, and a gate keeps
//  it that way.
//

import Foundation
import Testing

@testable import CourtWatch

/// A stand-in for the real store, holding what it was given in memory.
///
/// Reaches no Keychain by construction: there is nothing here but a dictionary.
private nonisolated final class StubCredentialStore: CredentialStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var stored: Credentials?
    private var answer: CredentialRead?

    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

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

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum CredentialReadCases {

    /// Every outcome that is **not** the user declining. None of these may
    /// compare equal to `.declined`.
    static let notDeclined: [CredentialRead] = [
        .credential(Credentials(username: "someone", password: "unused")),
        .missing,
        .unavailable,
        .failed(-25300),
        .failed(-34018),
    ]
}

struct CredentialStoreTests {

    // MARK: - The distinction the requirement hangs on

    /// Declining yields the declined case and **no credential**.
    @Test("A declined read returns declined and hands back nothing")
    func declinedReadYieldsNoCredential() async {
        let store = StubCredentialStore(
            stored: Credentials(username: "someone", password: "s3cret-not-real"),
            answering: .declined)

        let result = await store.load(reason: "unused")

        #expect(result == .declined)

        if case .credential = result {
            Issue.record("a declined read produced a credential")
        }
    }

    /// Declined is not any kind of failure. If this ever passes by accident —
    /// because the two were merged — the app grows an error screen where the
    /// requirement demands a working one.
    @Test(
        "Declined is not equal to any other outcome",
        arguments: CredentialReadCases.notDeclined
    )
    func declinedIsNotAFailure(other: CredentialRead) {
        #expect(CredentialRead.declined != other)
    }

    /// Nothing stored is its own answer, and it is not a decline: one means
    /// "you may not have it", the other means "there is nothing to have".
    @Test("A read with nothing stored reports missing, distinctly from declined")
    func missingIsDistinctFromDeclined() async {
        let store = StubCredentialStore()

        let result = await store.load(reason: "unused")

        #expect(result == .missing)
        #expect(result != .declined)
    }

    @Test("A stored credential is returned intact")
    func storedCredentialIsReturned() async {
        let credential = Credentials(username: "someone", password: "s3cret-not-real")
        let store = StubCredentialStore(stored: credential)

        #expect(await store.load(reason: "unused") == .credential(credential))
    }

    /// The four failure-ish outcomes stay four, not one.
    @Test("Every outcome is distinguishable from every other")
    func outcomesArePairwiseDistinct() {
        let all: [CredentialRead] = [
            .credential(Credentials(username: "someone", password: "unused")),
            .declined,
            .missing,
            .unavailable,
            .failed(-25300),
        ]

        for (index, first) in all.enumerated() {
            for second in all[(index + 1)...] {
                #expect(first != second, "\(first) collides with \(second)")
            }
        }
    }

    /// Two different statuses are two different failures — collapsing them
    /// would lose the only diagnostic this case carries.
    @Test("Two failures with different statuses are not the same failure")
    func failuresCarryTheirStatus() {
        #expect(CredentialRead.failed(-25300) != CredentialRead.failed(-34018))
    }

    // MARK: - Redaction

    /// Both printed forms, because they are reached by different code paths
    /// and covering one leaves the other. The marker is deliberately
    /// distinctive so a partial leak cannot hide inside ordinary prose.
    @Test("The password appears in neither printed form of a credential")
    func passwordIsRedactedBothWays() {
        let credential = Credentials(
            username: "someone", password: "MARKER_SECRET_VALUE_ffffffff")

        let interpolated = "\(credential)"
        let reflected = String(reflecting: credential)
        let described = credential.description
        let debugged = credential.debugDescription

        for rendering in [interpolated, reflected, described, debugged] {
            #expect(
                rendering.contains("MARKER_SECRET_VALUE_ffffffff") == false,
                "the password leaked into: \(rendering)")
            #expect(rendering.contains("redacted"))
        }

        // The username is not a secret and stays legible, or the redaction is
        // hiding the wrong thing.
        #expect(interpolated.contains("someone"))
    }

    /// Redaction must not depend on the value being short, ordinary, or
    /// free of characters that might be escaped away.
    @Test(
        "Redaction holds whatever the password looks like",
        arguments: [
            "MARKER_a", "MARKER_" + String(repeating: "x", count: 500),
            "MARKER_\"quoted\"", "MARKER_ with spaces ", "MARKER_🎾",
            "MARKER_\\backslash", "MARKER_\n newline",
        ]
    )
    func redactionHoldsForAnyValue(secret: String) {
        let credential = Credentials(username: "someone", password: secret)

        #expect("\(credential)".contains(secret) == false)
        #expect(String(reflecting: credential).contains(secret) == false)
    }

    /// Whatever the password is, the description is the same — so nothing
    /// about it can be inferred from what gets printed.
    @Test("The printed form does not vary with the password")
    func printedFormIsConstant() {
        let short = Credentials(username: "someone", password: "a")
        let long = Credentials(username: "someone", password: String(repeating: "z", count: 400))

        #expect(short.description == long.description)
        #expect(short.debugDescription == long.debugDescription)
    }

    // MARK: - Save and delete

    /// Saving needs no authentication and no prompt, so it is a plain call.
    @Test("Saving stores the credential and asks for nothing")
    func savingStores() {
        let store = StubCredentialStore()
        let credential = Credentials(username: "someone", password: "s3cret-not-real")

        #expect(store.hasStoredCredential() == false)
        #expect(store.save(credential))
        #expect(store.hasStoredCredential())
        #expect(store.currentlyStored == credential)
        #expect(store.loadCount == 0, "saving must not read, and must not prompt")
    }

    /// Deleting leaves nothing behind, and the store agrees afterwards.
    @Test("Deleting removes the credential and leaves nothing")
    func deletingRemoves() async {
        let store = StubCredentialStore(
            stored: Credentials(username: "someone", password: "s3cret-not-real"))

        #expect(store.delete())
        #expect(store.hasStoredCredential() == false)
        #expect(store.currentlyStored == nil)
        #expect(await store.load(reason: "unused") == .missing)
    }

    /// Deleting when there is nothing to delete is not an error — sign-out has
    /// to work from any state.
    @Test("Deleting nothing still succeeds")
    func deletingNothingSucceeds() {
        let store = StubCredentialStore()

        #expect(store.delete())
        #expect(store.hasStoredCredential() == false)
    }

    /// Saving twice replaces rather than accumulating.
    @Test("Saving again replaces what was there")
    func savingReplaces() {
        let store = StubCredentialStore()

        store.save(Credentials(username: "first", password: "s3cret-not-real"))
        store.save(Credentials(username: "second", password: "also-not-real"))

        #expect(store.currentlyStored?.username == "second")
    }

    // MARK: - The real store, without invoking it

    /// The one thing worth pinning about the real store from here: it names
    /// what the credential is for rather than spelling out whose account it
    /// is, and it is not the bundle identifier.
    @Test("The real store's service name identifies the purpose, not the account")
    func serviceNameIsImpersonal() {
        #expect(CredentialStore.service.isEmpty == false)
        #expect(CredentialStore.service.contains("@") == false)
        #expect(CredentialStore.service.lowercased().contains("township"))
    }

    /// That its read path consults the device-owner check *before* the
    /// Keychain is asserted structurally, by a gate over the source, rather
    /// than by mocking Apple's frameworks — which would prove only that the
    /// mock was called.
    @Test("The real store conforms to the seam the suite drives")
    func realStoreConformsToTheSeam() {
        let store: any CredentialStoring = CredentialStore()

        #expect(store is CredentialStore)
    }
}
