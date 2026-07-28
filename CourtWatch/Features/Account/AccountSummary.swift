//
//  AccountSummary.swift
//  CourtWatch
//
//  What the account surface shows once there is an account to show.
//
//  The state is stated **in words**. That is not decoration: the app can end up
//  anonymous through six different routes — a declined device-owner check, an
//  empty Keychain, a reply it could not read, a success that carried no account,
//  a session check that would not confirm, or a signed-in fetch the server
//  refused — and several of them happen without the user doing anything. A
//  symbol alone would leave them guessing which of the two states they are in.
//
//  Signing out is styled as destructive but is not confirmed. The stakes are
//  the saved password, and the cost of losing it is typing it again — against
//  an optional feature that changes nothing the app displays. A dialog in
//  front of a one-tap action the user just deliberately reached for, two
//  screens deep, asks them to answer a question they have already answered.
//

import SwiftUI

struct AccountSummary: View {

    let account: AccountStore


    var body: some View {
        Form {
            Section {
                Label(AccountStateText.signedIn, systemImage: "person.crop.circle.fill")
                    .font(.headline)

                Text(
                    "The courts screen looks exactly the same either way — signing in doesn't "
                        + "reveal any extra courts or times."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await account.signOut() }
                }
                .disabled(account.isWorking)
            } footer: {
                Text("This removes the saved sign-in from this device and ends the session.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The line the account surface shows when the app dropped to anonymous on its
/// own, rather than because the user asked.
///
/// Kept as a function so it can be asserted: no test observes a rendered
/// screen, and a state this important should not be claimed only by a view.
nonisolated enum AccountStateText {

    static let signedIn = "Signed in to your Township account"

    static let anonymous = "You're not signed in."

    /// Shown after a signed-in request was refused and served anonymously. The
    /// alternative — dropping to anonymous while still displaying "signed in" —
    /// would be a lie the user has no way to detect.
    static let downgraded =
        "The court system wouldn't accept the signed-in request, so the app went back to "
        + "browsing anonymously. Everything is still here."
}
