//
//  AccountStore.swift
//  CourtWatch
//
//  The account state, and the place "every unknown resolves toward anonymous"
//  is enforced rather than described.
//
//  Anonymous is the initial state and the resting state. The store reads
//  nothing at construction, prompts for nothing, and reaches the network for
//  nothing. Signing in was measured to change nothing a user can see — 0 of 80
//  courts differed across 1,280 slots — so a device-owner prompt on cold start
//  would be the most annoying thing this app could do, for no visible return.
//
//  ## The one thing this type must not grow
//
//  **No path inside it may submit a credential without an explicit call from
//  outside.** No retry helper. No "try the stored one if the typed one failed".
//  No recovery on error. No refresh.
//
//  That is written here in those words because the next person to add a
//  convenience will be trying to be helpful, and the cost does not land on a
//  test — it lands on the user's real Township booking account, which arms an
//  extra verification step after a single wrong attempt and cannot be reset
//  from this app.
//
//  ## Nothing here persists
//
//  Not `UserDefaults`, not `@AppStorage` — which was measured in Phase 3 not to
//  publish changes inside an `@Observable` anyway. The credential belongs in
//  the Keychain and the identity is in memory only, dying with the process.
//  Staying signed in across launches is out of scope by requirement.
//

import Foundation
import Observation

/// Where a credential came from, which decides what happens when it is refused.
nonisolated enum CredentialOrigin: Equatable, Sendable {

    /// Typed by a person just now.
    case typed

    /// Read back from the Keychain, which means it can be offered repeatedly
    /// unless something is done about it.
    case stored
}

@Observable
final class AccountStore {

    /// One value, not three flags.
    ///
    /// Anonymous-and-signed-in, or working-and-not-working, are combinations
    /// that mean nothing, and an enum makes them unrepresentable rather than
    /// merely unlikely — the same reason the load state next door is one.
    enum State: Equatable {
        case anonymous
        case working
        case signedIn(customerID: Int)
    }

    private(set) var state: State = .anonymous

    /// The last thing that went wrong, if anything did.
    ///
    /// Cleared at the start of every attempt, so it can never describe an
    /// earlier one. **A declined device-owner check never sets this** — that is
    /// a choice the user made, not a failure, and the distinction is the whole
    /// of the requirement it serves.
    private(set) var lastFailure: APIError?

    /// Whether there is a stored credential to offer.
    ///
    /// Not read at construction. It is refreshed when the account surface is
    /// opened and after anything that could change it, so the app never asks
    /// the Keychain a question nobody is waiting on the answer to.
    private(set) var hasStoredCredential = false

    /// Set when a signed-in fetch was refused and served anonymously instead.
    ///
    /// An app that quietly dropped to anonymous while still displaying "signed
    /// in" would be telling the user something they have no way to check.
    private(set) var wasDowngraded = false

    /// What the session check said last time it was asked. Recorded so
    /// sign-out's cookie guarantee can be asserted rather than eyeballed.
    private(set) var lastSessionCheck: SessionProbe.Outcome?

    /// Shown when the stored credential is unlocked. Names what is being
    /// unlocked and why, because it is the only explanation the system prompt
    /// carries.
    static let unlockReason = "Unlock your saved Township sign-in"

    private let session: CourtSession
    private let credentialStore: any CredentialStoring
    private let client: any SignInPerforming
    private let probe: any SessionChecking

    init(
        session: CourtSession,
        credentialStore: any CredentialStoring,
        client: any SignInPerforming,
        probe: any SessionChecking
    ) {
        self.session = session
        self.credentialStore = credentialStore
        self.client = client
        self.probe = probe
    }

    /// The only thing the rest of the app reads from here.
    var identity: Identity {
        switch state {
        case .signedIn(let customerID):
            return .signedIn(customerID: customerID)

        case .anonymous, .working:
            return .anonymous
        }
    }

    var isWorking: Bool { state == .working }

    /// Asks the Keychain whether there is anything to offer. No device-owner
    /// check, no prompt, no data returned.
    func refreshStoredCredentialAvailability() {
        hasStoredCredential = credentialStore.hasStoredCredential()
    }

    // MARK: - Signing in

    /// Started by a person submitting the form, and by nothing else.
    func signIn(as credentials: Credentials) async {
        guard beginWorking() else { return }

        await exchange(credentials, origin: .typed)
    }

    /// Started by an explicit user action — never by a launch, a refresh, or a
    /// retry.
    ///
    /// The device-owner check runs inside the credential store's read, before
    /// anything is handed back.
    func restoreStoredCredential() async {
        guard beginWorking() else { return }

        switch await credentialStore.load(reason: Self.unlockReason) {
        case .credential(let found):
            await exchange(found, origin: .stored)

        case .declined:
            // **The requirement that matters most.** Declining is a completed
            // choice, not an error: nothing is recorded, nothing is shown, and
            // the app is anonymous and entirely usable. The grid needs no
            // credential at all and has been on screen throughout.
            state = .anonymous

        case .missing:
            // Nothing stored. Say nothing, stop offering it, and leave the
            // sign-in form where it already is.
            hasStoredCredential = false
            state = .anonymous

        case .unavailable, .failed:
            // The check could not run, or the read did not work. Both resolve
            // toward anonymous like everything else here, and neither is worth
            // an error screen when the form the user needs is already in front
            // of them.
            state = .anonymous
        }
    }

    /// Signs out, and proves it.
    ///
    /// Prompts for nothing: deletion was measured to need no authentication,
    /// and a sign-out that could fail a device-owner check would be
    /// unavailable exactly when it is most wanted.
    ///
    /// `CourtSession.invalidate()` does the cookie half for free — it discards
    /// the token **and** replaces the transport with a fresh one carrying no
    /// cookies at all, which is the mechanism Phase 2 built so a token could
    /// never be paired with a foreign jar. Nothing new was needed for it.
    ///
    /// Then the session check is asked, so "the cookies are gone" is an
    /// observation rather than an assumption.
    func signOut() async {
        // Guarded like the two ways in. Without this a second tap while the
        // first was still running invalidated the session twice and sent two
        // session checks — two handshakes and two GETs nobody asked for,
        // against the host the one-attempt rule exists to be careful with. It
        // also leaves the button disabled for the duration, which is what the
        // account screen was already reading `isWorking` to decide.
        guard beginWorking() else { return }

        credentialStore.delete()
        hasStoredCredential = false

        await session.invalidate()

        state = .anonymous
        lastFailure = nil
        wasDowngraded = false

        lastSessionCheck = await probe.check()
    }

    /// Told by the fetch path that a signed-in request was refused and served
    /// anonymously instead.
    func reportAnonymousFallback() {
        guard case .signedIn = state else { return }

        state = .anonymous
        wasDowngraded = true
    }

    // MARK: - The core

    /// Refuses a second attempt while one is in flight.
    ///
    /// Sharper than the fetch guard next door and for a sharper reason: two
    /// concurrent submissions are two attempts against a counter that only
    /// tolerates one mistake.
    private func beginWorking() -> Bool {
        guard state != .working else { return false }

        state = .working
        lastFailure = nil
        wasDowngraded = false

        return true
    }

    /// The one place a credential is handed to the client, called only from the
    /// two entry points above.
    private func exchange(_ credentials: Credentials, origin: CredentialOrigin) async {
        do {
            switch try await client.signIn(as: credentials) {
            case .signedIn(let customerID):
                // **Stored only after the service has accepted it.** Storing on
                // entry would fill the Keychain with something that was just
                // refused, and the next restore would submit it again — turning
                // one mistake into a permanent, self-repeating hazard.
                credentialStore.save(credentials)
                hasStoredCredential = true

                state = .signedIn(customerID: customerID)

            case .rejected:
                // A refused **stored** credential is deleted.
                //
                // Otherwise the user taps restore, gets the same refusal, and
                // every tap costs another attempt on their real account.
                // Deleting turns a repeatable hazard into a single event
                // followed by an honest prompt to sign in again.
                //
                // This only happens when the login has been changed on the
                // website — rare, and exactly when nobody is expecting to be
                // told anything.
                if origin == .stored {
                    credentialStore.delete()
                    hasStoredCredential = false
                }

                finish(reporting: .credentialsRejected)

            case .captchaRequired:
                finish(reporting: .captchaRequired)

            case .succeededWithoutIdentity:
                finish(reporting: .signedInWithoutAccount)
            }
        } catch let failure as APIError {
            finish(reporting: failure)
        } catch {
            finish(reporting: .transport(.unknown))
        }
    }

    /// Every failure ends the same way: anonymous, with one thing recorded.
    private func finish(reporting failure: APIError) {
        state = .anonymous
        lastFailure = failure
    }
}
