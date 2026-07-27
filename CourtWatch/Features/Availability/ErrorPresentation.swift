//
//  ErrorPresentation.swift
//  CourtWatch
//
//  The one mapping from a technical failure to what the screen says.
//
//  The design question this answers is not "how do we show an error" but **what
//  does each failure mean to someone standing outside a tennis court, and what
//  can they do about it?** So the taxonomy is organised by the recovery each
//  offers rather than by the shape of the enum. Answering it with the enum's
//  own shape would put "decode failure" and "1507" in front of a person as
//  though those were things anyone could act on, and it would leave being
//  offline and having timed out — the two most common failures by a wide
//  margin, with genuinely different remedies — sharing one sentence because
//  they share one case.
//
//  D3: the switch below has **no catch-all arm**, exactly as `SlotAppearance.of`
//  does over `SlotStatus`, and for the same reason. A new error case must stop
//  this file compiling at the one place that decides what a user is told,
//  rather than inheriting a sentence written for something else. A grep gate
//  keeps the catch-all out; the `URLError.Code` grouping, which legitimately
//  needs a default, is quarantined in `NetworkFailureKind` next door so that
//  gate stays writeable.
//
//  Three rules govern the copy, and they are the point of the file:
//
//    * Name what happened in the user's terms, never the app's. No response
//      codes, no mention of decoding, no jargon dressed up.
//    * Say what they can do. Where there is nothing, say so plainly rather than
//      implying otherwise.
//    * **Never interpolate an associated value.** The decoding case carries the
//      decoder's own description, the service case a message written by a third
//      party for someone else's users, the expiry case a code. None belongs on
//      a screen, and the decoder description in particular can be long,
//      structural, and quote the payload. Asserted by substring, not intended.
//

import Foundation

/// Whether trying again is worth the user's time.
///
/// A named type rather than a boolean: the two cases mean "worth trying" and
/// "this will probably keep happening", and a bare true/false at a call site
/// reads as neither. The failure screen turns this into the retry button's
/// prominence — the control never disappears, because taking away the only
/// thing on the screen leaves a user with nothing but a force-quit, but its
/// weight tells the truth about the odds.
nonisolated enum RetryStrength: Hashable, Sendable {

    /// Something transient, or something the user can fix themselves.
    case worthTrying

    /// The same thing will almost certainly happen again. The button stays;
    /// the sentence stops pretending.
    case probablyPersistent
}

nonisolated struct ErrorPresentation: Hashable, Sendable {

    /// A headline, carrying no full stop.
    let title: String

    /// One sentence naming what happened and what, if anything, to do.
    let message: String

    /// An SF Symbol name. A misspelling here draws **nothing at all** and fails
    /// silently, so the set is pinned by a test that asks UIKit whether each
    /// one resolves.
    let symbolName: String

    let retry: RetryStrength

    /// The one place a failure becomes a sentence.
    ///
    /// No `default` arm, on purpose. See the file note.
    static func of(_ error: APIError) -> ErrorPresentation {
        switch error {
        case .transport(let code):
            switch NetworkFailureKind.of(code) {
            case .offline:
                return ErrorPresentation(
                    title: "No Internet Connection",
                    message: "Check your Wi‑Fi or cellular connection, then try again.",
                    symbolName: "wifi.slash",
                    retry: .worthTrying
                )

            case .farEnd:
                // Deliberately says nothing about the user's connection. This
                // is a timeout or a dropped connection, and sending someone to
                // check working Wi-Fi is worse than saying nothing.
                return ErrorPresentation(
                    title: "The Court System Isn't Answering",
                    message: "The Township's server didn't respond. This usually clears up on "
                        + "its own.",
                    symbolName: "antenna.radiowaves.left.and.right.slash",
                    retry: .worthTrying
                )
            }

        case .http:
            // Reached only when the reply was not an HTTP response at all — the
            // status is never judged anywhere in this app, by design, because
            // the API answers 200 for everything.
            return ErrorPresentation(
                title: "Unexpected Reply",
                message: "The connection didn't answer the way a web request should. "
                    + "Trying again may reach the court system.",
                symbolName: "questionmark.circle",
                retry: .worthTrying
            )

        case .notJSON:
            // A WAF interstitial or a captive-portal login page. Split out from
            // a schema change deliberately: this is the more likely of the two
            // given the host sits behind an F5 ASM, and "the app needs
            // updating" would blame the app for a network that is filtering it.
            return ErrorPresentation(
                title: "Something's in the Way",
                message: "A network in between replied instead of the court system. This is "
                    + "common on public or workplace Wi‑Fi.",
                symbolName: "network.slash",
                retry: .worthTrying
            )

        case .decoding:
            // The associated value is discarded, never interpolated. It is the
            // decoder's own description: long, structural, and liable to quote
            // the payload.
            return ErrorPresentation(
                title: "This App Needs an Update",
                message: "The court system changed how it publishes availability, so this app "
                    + "can no longer read it.",
                symbolName: "exclamationmark.triangle",
                retry: .probablyPersistent
            )

        case .service:
            // The API does send a message here and it is not passed through:
            // it is written for the website's own users, describes a request
            // this app did not make in those terms, and on an unversioned
            // endpoint nothing stops it being unhelpful or enormous.
            return ErrorPresentation(
                title: "The Court System Said No",
                message: "The Township's booking system refused the request. There's nothing "
                    + "to change on this end.",
                symbolName: "hand.raised",
                retry: .probablyPersistent
            )

        case .sessionExpired:
            // The exhausted case: the app already re-handshook once and
            // replayed once, and stopped. The code it carries is diagnostic and
            // stays out of the sentence.
            return ErrorPresentation(
                title: "Couldn't Start a Session",
                message: "The court system wouldn't renew this app's session. Trying again "
                    + "usually works.",
                symbolName: "clock.badge.exclamationmark",
                retry: .worthTrying
            )

        case .slotTimesMissing:
            // A perfectly good response that published no times. Nothing is
            // broken and nothing here will change until the Township posts
            // them, so the sentence says that rather than inviting a retry.
            return ErrorPresentation(
                title: "No Times Published",
                message: "The Township hasn't published any court times for today.",
                symbolName: "calendar.badge.exclamationmark",
                retry: .probablyPersistent
            )
        }
    }
}
