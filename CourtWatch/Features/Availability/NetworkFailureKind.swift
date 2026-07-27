//
//  NetworkFailureKind.swift
//  CourtWatch
//
//  Collapses `URLError.Code` into the only two groups that lead anywhere
//  different: the user's own connection is down and they can do something about
//  it, or the far end is not answering and they cannot.
//
//  **This type exists in its own file for a structural reason, and merging it
//  into `ErrorPresentation` next door would quietly break a gate.** That file's
//  switch over `APIError` is required to have no catch-all arm, so that a new
//  error case stops it compiling at the one place that decides what a user is
//  told rather than being absorbed into a sentence written for something else.
//  A grep for `default:` is what enforces that.
//
//  `URLError.Code` is a large, open-ended system enum that cannot be switched
//  exhaustively and therefore *must* have a default. Putting both switches in
//  one file would make that grep unwriteable — it could no longer tell the
//  legitimate default from the one it exists to forbid. Two files, bought
//  deliberately, so a structural gate stays meaningful.
//
//  So: the default arm below is correct and load-bearing. Do not move this
//  type, and do not "tidy" it into the file next door.
//

import Foundation

nonisolated enum NetworkFailureKind: Hashable, Sendable {

    /// The device is not on a network it is allowed to use. The user can fix
    /// this themselves, which is the only reason it is worth telling apart.
    case offline

    /// Something between here and the Township is not answering. Nothing the
    /// user does to their own device will change it.
    case farEnd

    /// The one place the system enum is read.
    ///
    /// A timeout is deliberately **not** offline. It is the most common failure
    /// after being genuinely disconnected, and the two have opposite remedies:
    /// telling someone to check a connection that is working sends them to fix
    /// the wrong thing, and is worse than saying nothing at all.
    static func of(_ code: URLError.Code) -> NetworkFailureKind {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline

        default:
            // Correct, and the reason this type is quarantined here. Everything
            // else — a timeout, a lost connection, a DNS failure, a code this
            // app has never seen — is the far end not answering.
            //
            // The direction of the fallback matters. Reading an unrecognised
            // code as "you are offline" would tell a user with working Wi-Fi
            // that their connection is broken; reading it as "the far end is
            // not answering" is true of every case in this arm and blames
            // nothing the user controls.
            return .farEnd
        }
    }
}
