//
//  CredentialStore.swift
//  CourtWatch
//
//  Where the Township sign-in rests, and what has to happen before it can be
//  read back.
//
//  ## Two mechanisms, defending two different things
//
//  It would be reasonable to look at this file and conclude that one of the two
//  protections is redundant. They are not, and a later tidy-up that removes
//  either would quietly break a requirement, so both reasons are written down.
//
//  **The access control** — `.userPresence` with
//  `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` — defends the item *at
//  rest* on real hardware. It requires a device passcode to exist at all, keeps
//  the item off backups and out of iCloud, and ties it to this device.
//
//  **The explicit device-owner check** defends the item *on read*, and it is
//  what the requirement actually rests on. Measured during planning: on the
//  simulator, a `.userPresence`-protected item is handed back by a Keychain
//  read **immediately, with no prompt of any kind** — before Face ID was
//  enrolled and, more surprisingly, after. Resting the requirement on the
//  access control alone would produce something that cannot be demonstrated
//  and, far worse, *looks* satisfied: someone would watch the app restore a
//  sign-in and reasonably conclude a gate had run. It would not have.
//
//  So this file calls `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`
//  itself, first, and only reads the item if that came back true. Measured to
//  block until answered, to be honoured, and to be drivable from the command
//  line — which is what makes the gate real, watchable, and scriptable.
//
//  ## Declining is not failing
//
//  Also measured: a non-matching face does **not** throw. The policy falls
//  through to the device passcode sheet and waits there, which is precisely the
//  graceful fallback the requirement asks for. The only way back to the app
//  without authenticating is the user *cancelling*. That makes cancellation an
//  ordinary outcome rather than an error, and `localizedCancelTitle` is not
//  decoration — it is the affordance the requirement is made of.
//
//  ## `.userPresence`, not `.biometryCurrentSet`
//
//  The stricter flag destroys the stored item whenever the user re-enrolls a
//  face or adds a fingerprint, silently. The user would then be asked to retype
//  an ActiveCommunities password, with no explanation, against a service that
//  arms a captcha after a single wrong attempt. For a bank that trade is right.
//  Here it is user-hostile and actively dangerous, and `.userPresence` survives
//  enrollment changes and gets the passcode fallback for free.
//
//  ## The seam
//
//  Everything is reachable behind `CredentialStoring` so the test suite never
//  touches the Keychain or the biometric stack — there is no biometric hardware
//  on a test runner and the call would hang. Nothing under `CourtWatchTests`
//  imports `Security` or `LocalAuthentication`, and a gate keeps it that way.
//

import Foundation
import LocalAuthentication
import Security

/// A username and a password, with the password redacted from every printed
/// form of this value.
///
/// Both `description` and `debugDescription` are given, not one: string
/// interpolation reaches the first and `String(reflecting:)`, the debugger and
/// several logging paths reach the second, so covering only one leaves the
/// other open. This is a cheap defence against an expensive mistake — a
/// credential interpolated into a crash report cannot be taken back.
nonisolated struct Credentials: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    let username: String
    let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    var description: String { "Credentials(username: \(username), password: <redacted>)" }

    var debugDescription: String { description }
}

/// What a read produced.
///
/// A small enum rather than a throw for everything, because the interesting
/// distinction is not success-versus-failure. **`declined` must be
/// structurally separate from every failure**: the requirement says a declined
/// check leaves the app anonymous and completely usable, and an error-shaped
/// decline invites an error screen where the requirement demands a working app.
nonisolated enum CredentialRead: Sendable, Equatable {

    case credential(Credentials)

    /// The user answered the device-owner check by cancelling. A choice, not a
    /// fault, and never to be reported as one.
    case declined

    /// Nothing is stored. Distinct from `declined`: one means "you may not
    /// have it", the other means "there is nothing to have".
    case missing

    /// This device cannot perform a device-owner check at all — no passcode
    /// set, or no biometric and no passcode.
    case unavailable

    /// Something else went wrong, carrying the status for diagnosis. Never
    /// shown to anybody.
    case failed(OSStatus)
}

/// The seam. Everything the app needs from the Keychain, and nothing else.
nonisolated protocol CredentialStoring: Sendable {

    /// Runs the device-owner check, then reads. Never the other way around.
    func load(reason: String) async -> CredentialRead

    /// Writes, replacing anything already there. Prompts for nothing.
    @discardableResult
    func save(_ credentials: Credentials) -> Bool

    /// Removes, and proves it. Prompts for nothing.
    @discardableResult
    func delete() -> Bool

    /// Whether there is anything to offer, without reading it and without
    /// asking the user for anything.
    func hasStoredCredential() -> Bool
}

nonisolated struct CredentialStore: CredentialStoring, Sendable {

    /// Deliberately not the bundle identifier: this names what the credential
    /// is *for*, and nothing in this repository spells out the account it
    /// belongs to.
    static let service = "court-watch.township-signin"

    private let service: String

    init(service: String = CredentialStore.service) {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,

            // The modern keychain implementation rather than the file-based
            // one. Required for the data-protection accessibility classes to
            // mean what they say.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    // MARK: - Writing

    /// Stores the credential behind the access control described in the file
    /// note.
    ///
    /// **Saving prompts for nothing**, which is the opposite of the natural
    /// assumption — `.userPresence` governs reading the item, not creating it.
    /// Said out loud here because the missing prompt looks like a bug and
    /// somebody will otherwise "fix" it.
    ///
    /// Delete-then-add rather than update: an access control cannot be
    /// modified by an update, so an item written once would keep its original
    /// protection forever.
    @discardableResult
    func save(_ credentials: Credentials) -> Bool {
        guard let secret = credentials.password.data(using: .utf8) else { return false }

        var accessError: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.userPresence],
                &accessError)
        else {
            return false
        }

        _ = SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecAttrAccount as String] = credentials.username
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrAccessControl as String] = access

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Reading

    /// The device-owner check runs **first**, and the item is only read if it
    /// came back true. See the file note for why this is not redundant with the
    /// access control already on the item.
    func load(reason: String) async -> CredentialRead {
        let context = LAContext()

        // Worded as a decision rather than a failure, because cancelling is
        // the only path back to the app once the prompt is up, and the app is
        // entirely usable without ever answering it.
        context.localizedCancelTitle = "Stay Signed Out"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return .unavailable
        }

        do {
            let approved = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: reason)

            guard approved else { return .declined }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                return .declined

            default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        // Hands the already-answered context to the Keychain so the item is
        // not able to ask a second time.
        query[kSecUseAuthenticationContext as String] = context

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let found = item as? [String: Any],
                let secret = found[kSecValueData as String] as? Data,
                let recovered = String(data: secret, encoding: .utf8),
                let username = found[kSecAttrAccount as String] as? String
            else {
                return .failed(errSecDecode)
            }

            return .credential(Credentials(username: username, password: recovered))

        case errSecItemNotFound:
            return .missing

        case errSecUserCanceled:
            return .declined

        default:
            return .failed(status)
        }
    }

    // MARK: - Removing

    /// Deletion needs no authentication — measured, and correct rather than
    /// merely convenient: a sign-out that could fail a device-owner check
    /// would be unavailable exactly when it is most wanted.
    ///
    /// The status is not trusted. Signing out is a claim about what is *gone*,
    /// and only reading back proves it.
    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else { return false }

        return hasStoredCredential() == false
    }

    /// Existence only: no data is returned and no device-owner check is run,
    /// so this can be asked at any time without putting a prompt in front of
    /// anybody.
    func hasStoredCredential() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        // Never prompt. Asking "is there one saved?" is not asking to read it,
        // and opening the account sheet must not put a Face ID sheet in front of
        // someone who only wanted to look.
        //
        // Without this, matching an item guarded by a biometric access control
        // can raise the authentication UI even though no data was requested.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        // `errSecInteractionNotAllowed` means the item is there and declined to
        // be read without authentication — which answers the question asked.
        // Treating it as absent would hide a saved sign-in behind the very
        // prompt this avoids.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}
