//
//  SignInScreen.swift
//  CourtWatch
//
//  The form, and the submit rules — which are the requirement, not the styling.
//
//  ## Why the fields are shaped this way
//
//  No iOS password manager exposes a direct API, so AutoFill is the only route,
//  and AutoFill appears because the fields **say what they are**. That is the
//  whole of the integration: `.textContentType(.username)` on one and
//  `.textContentType(.password)` on a `SecureField` on the other.
//
//  Autocapitalisation and autocorrection are off on the username, and that is
//  not tidiness: an autocorrected email address is a wrong credential submitted
//  against a service that arms an extra verification step after one mistake.
//
//  ## There is no retry control on this screen, on purpose
//
//  Every other failure surface in this app keeps a Try Again button, deliberately
//  — taking away the only control on a screen leaves a user with nothing to do
//  but force-quit. **This screen is the exception, and the inconsistency is the
//  point.** There, the control is the remedy. Here, the control is the hazard:
//  one more wrong attempt costs the user something on their real Township
//  account that this app cannot undo.
//
//  So after a refusal the submit button stays inert **until the field changes**.
//  A second attempt requires a keystroke, which means it cannot happen by
//  tapping, by an impatient double-tap, or by a stray gesture. There is no
//  refresh gesture here either.
//
//  ## What is not covered by the suite
//
//  No test observes a rendered screen. The copy is covered where it is decided,
//  and the state machine is covered where it lives; that *this screen asks for
//  them* is a checkpoint line, the same way the fetch guard next door is.
//

import SwiftUI

struct SignInScreen: View {

    let account: AccountStore

    @State private var username = ""
    @State private var password = ""

    /// Closed after a refusal, and opened again by a keystroke.
    ///
    /// Deliberately a flag rather than a remembered copy of what was submitted:
    /// keeping the refused value around to compare against would mean holding a
    /// credential for longer than the one call that needed it.
    @State private var submissionClosed = false

    /// Which control started the request in flight.
    ///
    /// Without it both buttons read `isWorking` and the spinner appears on
    /// whichever one happens to draw it, rather than the one that was tapped.
    private enum AttemptSource { case typed, stored }

    @State private var attemptSource: AttemptSource = .typed

    /// Keyboard focus, so Return moves from the email to the password and then
    /// submits rather than dead-ending.
    private enum Field: Hashable { case email, password }

    @FocusState private var focusedField: Field?

    /// Where VoiceOver is sent when a failure appears below the buttons.
    @AccessibilityFocusState private var failureFocused: Bool

    private var canSubmit: Bool {
        account.isWorking == false
            && submissionClosed == false
            && username.isEmpty == false
            && password.isEmpty == false
    }

    var body: some View {
        Form {
            Section {
                // The state in words, never by a symbol alone. A user can end
                // up anonymous through any of six paths and must always be able
                // to see which state they are in without decoding a glyph.
                Text(AccountStateText.anonymous)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if account.wasDowngraded {
                    // The app dropped to anonymous on its own. Saying nothing
                    // here would leave the user to notice a change of state
                    // they never asked for and cannot otherwise see.
                    Text(AccountStateText.downgraded)
                        .font(.subheadline)
                }
            }

            Section {
                TextField("Email", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .disabled(account.isWorking)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        guard canSubmit else { return }
                        focusedField = nil
                        Task { await submit() }
                    }
                    .disabled(account.isWorking)
                    .onChange(of: password) {
                        // The keystroke that reopens submission. This is the
                        // whole of "a second attempt cannot happen by tapping".
                        submissionClosed = false
                    }
            } header: {
                Text("Township Account")
            } footer: {
                // Says what is kept and where. "Saved for later" named no
                // subject, and what is saved is a password — the one thing a
                // user is entitled to be told about before they type it.
                Text(
                    "Court availability is the same signed in or out. "
                        + "After a successful sign-in your email and password are kept "
                        + "in this device's Keychain."
                )
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if account.isWorking && attemptSource == .typed {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Signing In…")
                        }
                    } else {
                        Text("Sign In")
                    }
                }
                // Closed while a sign-in is in flight, and closed after a
                // refusal until the field changes. **Not covered by the suite**
                // — no test observes a rendered screen, so that this control
                // actually holds the door is a checkpoint line.
                .disabled(canSubmit == false)

                if account.hasStoredCredential {
                    Button {
                        attemptSource = .stored
                        Task { await account.restoreStoredCredential() }
                    } label: {
                        // Progress belongs on the control that was tapped.
                        // Showing it on the other one told the user the wrong
                        // thing about which request was running.
                        if account.isWorking && attemptSource == .stored {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Signing In…")
                            }
                        } else {
                            Text("Use Saved Sign-In")
                        }
                    }
                    .disabled(account.isWorking)
                }
            } footer: {
                if account.hasStoredCredential {
                    // Not "Face ID or your passcode": the device may use Touch
                    // ID, and naming a method it does not have is simply wrong.
                    Text("You'll be asked to verify it's you first.")
                }
            }

            if let failure = account.lastFailure {
                // The words come from the one mapping that decides them. This
                // screen holds no opinion of its own and branches on no error
                // case — the same rule the failure screen and the cells follow.
                let presentation = ErrorPresentation.of(failure)

                Section {
                    Label(presentation.title, systemImage: presentation.symbolName)
                        .font(.headline)
                        // An error that appears silently is invisible to
                        // VoiceOver, which is still sitting on whatever it was
                        // reading before. Moving focus here is how it is told.
                        .accessibilityFocused($failureFocused)

                    Text(presentation.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        attemptSource = .typed
        focusedField = nil

        await account.signIn(as: Credentials(username: username, password: password))

        // Anything that went wrong closes the door until a keystroke reopens
        // it. A refusal is the case this exists for, but a failure the user
        // cannot see the cause of is no reason to let them hammer the service
        // either.
        submissionClosed = account.lastFailure != nil

        if account.lastFailure != nil {
            failureFocused = true
        }
    }
}
