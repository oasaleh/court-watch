//
//  ErrorPresentationTests.swift
//  CourtWatchTests
//
//  This file is DATA-07, and the assertion that carries it is **pairwise
//  distinctness**.
//
//  Checking the presentations one at a time — that each has a title, that each
//  has a message — would pass a mapping where three cases had quietly converged
//  on the same sentence, which is exactly the failure DATA-07 names and exactly
//  what a hurried edit produces. So every pair is compared, and no two may
//  share both a title and a message.
//
//  The second assertion with teeth is the leak rule. `APIError.decoding`
//  carries the decoder's own description, which can be long, structural, and
//  quote parts of the payload; `.service` carries a message written by a third
//  party for the website's own users; `.sessionExpired` carries a code. None of
//  them belongs on a screen. Rather than intending that, errors are built here
//  carrying recognisable markers and the markers are required to appear
//  nowhere in the result.
//

import Foundation
import Testing
import UIKit

@testable import CourtWatch

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum ErrorPresentationCases {

    /// Every distinct presentation the app can put on a failure screen.
    /// Eleven, because `.transport` splits into two — being offline and the far
    /// end not answering have genuinely different remedies and are the two most
    /// common failures by a wide margin — and because sign-in adds three ways a
    /// credential exchange can end badly.
    static let all: [APIError] = [
        .transport(.notConnectedToInternet),
        .transport(.timedOut),
        .http(-1),
        .notJSON,
        .decoding("keyNotFound"),
        .service(code: "1507", message: "Invalid request"),
        .sessionExpired(code: "0012"),
        .slotTimesMissing,
        .credentialsRejected,
        .captchaRequired,
        .signedInWithoutIdentity,
    ]

    /// Codes that mean the user's own connection is down and they can do
    /// something about it.
    static let offline: [URLError.Code] = [
        .notConnectedToInternet,
        .dataNotAllowed,
        .internationalRoamingOff,
    ]

    /// Codes that mean the far end is not answering. A timeout belongs here,
    /// not above: telling someone to check a connection that is working is
    /// worse than saying nothing.
    static let farEnd: [URLError.Code] = [
        .timedOut,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .badServerResponse,
        .secureConnectionFailed,
        URLError.Code(rawValue: -99_999),
    ]

    /// The three the app must not pretend a retry will fix.
    static let persistent: [APIError] = [
        .decoding("keyNotFound"),
        .service(code: "1507", message: "Invalid request"),
        .slotTimesMissing,
        .credentialsRejected,
        .captchaRequired,
        .signedInWithoutIdentity,
    ]

    /// The five where trying again is a reasonable thing to do.
    static let worthRetrying: [APIError] = [
        .transport(.notConnectedToInternet),
        .transport(.timedOut),
        .http(-1),
        .notJSON,
        .sessionExpired(code: "0012"),
    ]
}

struct ErrorPresentationTests {

    // MARK: - The assertion that carries the task

    /// No two presentations may share both a title and a message.
    ///
    /// Compared as pairs rather than checked individually, because the failure
    /// this guards against is convergence — three cases drifting onto one
    /// sentence — and no per-case assertion can see that.
    @Test("No two presentations share both a title and a message")
    func everyPresentationIsDistinct() {
        let all = ErrorPresentationCases.all.map { ErrorPresentation.of($0) }

        // Enumerated, never a hand-written number: a count that has to be
        // edited by hand is a count that will eventually be wrong, and a wrong
        // one here would silently stop covering the newest case.
        #expect(all.count == ErrorPresentationCases.all.count)
        #expect(all.count == 11)

        for (i, first) in all.enumerated() {
            for second in all[(i + 1)...] {
                #expect(
                    (first.title == second.title && first.message == second.message) == false,
                    "\(first.title) / \(first.message) collides with \(second.title)"
                )
            }
        }
    }

    /// The stronger form: every title is unique and every message is unique,
    /// not merely every pair.
    @Test("Every title and every message is used exactly once")
    func titlesAndMessagesAreUnique() {
        let all = ErrorPresentationCases.all.map { ErrorPresentation.of($0) }

        #expect(Set(all.map(\.title)).count == ErrorPresentationCases.all.count)
        #expect(Set(all.map(\.message)).count == ErrorPresentationCases.all.count)
    }

    /// Every presentation is a complete, readable sentence rather than a
    /// fragment or an empty string.
    @Test("Every presentation says something", arguments: ErrorPresentationCases.all)
    func everyPresentationIsWritten(error: APIError) {
        let presentation = ErrorPresentation.of(error)

        #expect(presentation.title.isEmpty == false)
        #expect(presentation.message.isEmpty == false)
        #expect(presentation.title.hasSuffix(".") == false, "a headline carries no full stop")
        #expect(presentation.message.hasSuffix("."))
        #expect(presentation.symbolName.isEmpty == false)
    }

    // MARK: - The sentence AUTH-06 exists for

    /// **A refused credential must warn that trying again has a cost.**
    ///
    /// Asserted directly rather than left to the distinctness check, because a
    /// well-meaning edit shortening this to "Incorrect password" would pass
    /// every other test in this file while removing the entire point of the
    /// case. The app is the only thing that can say this: the server's own
    /// message describes what went wrong and says nothing about what a second
    /// attempt would cost.
    @Test("The refusal names the cost of trying again")
    func refusalWarnsAboutRetrying() {
        let presentation = ErrorPresentation.of(.credentialsRejected)
        let message = presentation.message.lowercased()

        // It tells the user not to simply repeat the attempt...
        #expect(message.contains("don't try again"))

        // ...names what a further attempt would cost...
        #expect(message.contains("one more wrong attempt"))
        #expect(message.contains("extra check"))

        // ...and points at where it would have to be resolved.
        #expect(message.contains("website"))

        // And it does not pretend a retry is the way forward.
        #expect(presentation.retry == .probablyPersistent)
    }

    /// The captcha case sends the user somewhere they can actually act.
    @Test("The captcha case points at the website")
    func captchaSendsUserToTheWebsite() {
        let presentation = ErrorPresentation.of(.captchaRequired)

        #expect(presentation.message.lowercased().contains("website"))
        #expect(presentation != ErrorPresentation.of(.credentialsRejected))
    }

    /// The no-identity case must read as a state, not a fault: the app is
    /// anonymous and everything works.
    @Test("The no-identity case reads as a state rather than a failure")
    func noIdentityReadsAsAState() {
        let presentation = ErrorPresentation.of(.signedInWithoutIdentity)
        let text = (presentation.title + " " + presentation.message).lowercased()

        #expect(text.contains("nothing is missing"))

        // Nothing that reads as a fault of the app.
        for alarming in ["error", "failed", "failure", "problem", "wrong", "couldn't"] {
            #expect(text.contains(alarming) == false, "\(alarming) reads as a fault")
        }
    }

    /// All three sign-in outcomes are distinct sentences, and none of them is
    /// any of the eight that already existed.
    @Test("The three sign-in cases are distinct from each other and from the rest")
    func signInCasesAreDistinct() {
        let signIn: [APIError] = [.credentialsRejected, .captchaRequired, .signedInWithoutIdentity]
        let existing: [APIError] = [
            .transport(.notConnectedToInternet), .transport(.timedOut), .http(-1), .notJSON,
            .decoding("x"), .service(code: "1507", message: "Invalid request"),
            .sessionExpired(code: "0012"), .slotTimesMissing,
        ]

        for (index, first) in signIn.enumerated() {
            for second in signIn[(index + 1)...] {
                #expect(ErrorPresentation.of(first) != ErrorPresentation.of(second))
            }

            for other in existing {
                #expect(
                    ErrorPresentation.of(first).title != ErrorPresentation.of(other).title,
                    "a sign-in case borrowed an existing headline")
            }
        }
    }

    // MARK: - The leak rule

    /// Nothing technical may reach a screen. Built with markers rather than
    /// asserted in prose, because "we would never interpolate that" is exactly
    /// the kind of intention that a later edit breaks silently.
    @Test("No presentation carries decoder text, a code, or a third-party message")
    func leaksNothingTechnical() {
        let errors: [APIError] = [
            .decoding(
                """
                keyNotFound(CodingKeys(stringValue: "response_code"), \
                Swift.DecodingError.Context(codingPath: [], debugDescription: \
                "No value associated with key", underlyingError: nil))
                """),
            .service(code: "1507", message: "MARKER_THIRD_PARTY_MESSAGE"),
            .sessionExpired(code: "MARKER_SESSION_CODE"),
            .transport(.notConnectedToInternet),
            .notJSON,
            .credentialsRejected,
            .captchaRequired,
            .signedInWithoutIdentity,
        ]

        let forbidden = [
            "keyNotFound", "CodingKeys", "DecodingError", "codingPath", "debugDescription",
            "MARKER_THIRD_PARTY_MESSAGE", "MARKER_SESSION_CODE", "1507", "0012",
            "://", "activecommunities", "csrf", "Cookie", "token",
            // Nothing from a sign-in reply or a credential either. The three
            // new cases carry no associated value at all, so this is cheap to
            // keep true — and worth pinning anyway, because the next person to
            // add a case will copy one of these.
            "Invalid login name", "public_customer_id", "customer_id", "0000",
            "recaptcha", "access_token", "@",
        ]

        for error in errors {
            let presentation = ErrorPresentation.of(error)
            let text = presentation.title + " " + presentation.message

            for marker in forbidden {
                #expect(
                    text.localizedCaseInsensitiveContains(marker) == false,
                    "\(marker) leaked into: \(text)"
                )
            }
        }
    }

    /// The decoder description in particular can be enormous and can quote the
    /// payload. Whatever it says, the sentence the user reads is the same
    /// length every time.
    @Test("The decoder's own description never changes what the screen says")
    func decoderTextNeverReachesTheScreen() {
        let short = ErrorPresentation.of(.decoding("x"))
        let long = ErrorPresentation.of(.decoding(String(repeating: "payload fragment ", count: 200)))

        #expect(short == long)
    }

    /// The API does send a message, and it is the one place a third-party
    /// string is tempting. It is written for the website's own users, describes
    /// a request this app did not make in those terms, and on an unversioned
    /// endpoint there is nothing stopping it being unhelpful or enormous.
    @Test("A service failure speaks in the app's own voice, whatever the API said")
    func serviceMessageIsNotPassedThrough() {
        let quiet = ErrorPresentation.of(.service(code: "1507", message: "Invalid request"))
        let loud = ErrorPresentation.of(
            .service(code: "9999", message: "PLEASE CALL 817-555-0100 DURING BUSINESS HOURS"))
        let silent = ErrorPresentation.of(.service(code: "1507", message: nil))

        #expect(quiet == loud)
        #expect(quiet == silent)
        #expect(quiet.message.contains("817") == false)
    }

    // MARK: - Offline is told apart from the far end

    @Test(
        "Every offline code reads as the user's own connection",
        arguments: ErrorPresentationCases.offline
    )
    func offlineCodesReadAsOffline(code: URLError.Code) {
        #expect(NetworkFailureKind.of(code) == .offline)

        let presentation = ErrorPresentation.of(.transport(code))

        #expect(presentation == ErrorPresentation.of(.transport(.notConnectedToInternet)))
        #expect(presentation != ErrorPresentation.of(.transport(.timedOut)))
    }

    @Test(
        "Every other code reads as the far end not answering",
        arguments: ErrorPresentationCases.farEnd
    )
    func otherCodesReadAsFarEnd(code: URLError.Code) {
        #expect(NetworkFailureKind.of(code) == .farEnd)

        let presentation = ErrorPresentation.of(.transport(code))

        #expect(presentation == ErrorPresentation.of(.transport(.timedOut)))
        #expect(presentation != ErrorPresentation.of(.transport(.notConnectedToInternet)))
    }

    /// The headline distinction, written out on its own because it is the one
    /// the user meets most often and the one the taxonomy exists for.
    @Test("Being offline and timing out are different sentences")
    func offlineIsNotTimeout() {
        let offline = ErrorPresentation.of(.transport(.notConnectedToInternet))
        let timeout = ErrorPresentation.of(.transport(.timedOut))

        #expect(offline.title != timeout.title)
        #expect(offline.message != timeout.message)
    }

    /// A code nobody has seen before must not claim the user's connection is
    /// down. Telling someone to check working Wi-Fi sends them to fix the wrong
    /// thing, which is the same mistake in miniature that the block-page split
    /// exists to prevent.
    @Test("An unrecognised network code reads as the far end, never as being offline")
    func unknownCodeIsNotReadAsOffline() {
        let invented = URLError.Code(rawValue: -424_242)

        #expect(NetworkFailureKind.of(invented) == .farEnd)
        #expect(
            ErrorPresentation.of(.transport(invented))
                != ErrorPresentation.of(.transport(.notConnectedToInternet)))
    }

    // MARK: - Honesty about whether retrying helps

    @Test(
        "The three that will keep happening say so",
        arguments: ErrorPresentationCases.persistent
    )
    func persistentFailuresSaySo(error: APIError) {
        #expect(ErrorPresentation.of(error).retry == .probablyPersistent)
    }

    @Test(
        "The five worth another go say that instead",
        arguments: ErrorPresentationCases.worthRetrying
    )
    func recoverableFailuresSaySo(error: APIError) {
        #expect(ErrorPresentation.of(error).retry == .worthTrying)
    }

    /// A shape change is the case most likely to be mislabelled as transient,
    /// because it arrives the same way a truncated response does.
    @Test("A response whose shape changed does not promise that retrying helps")
    func shapeChangeIsNotPromisedRecoverable() {
        #expect(ErrorPresentation.of(.decoding("anything")).retry == .probablyPersistent)
    }

    // MARK: - Every presentation is complete

    @Test("Every failure produces a title, a sentence, and a symbol", arguments: ErrorPresentationCases.all)
    func everyErrorIsPresentable(error: APIError) {
        let presentation = ErrorPresentation.of(error)

        #expect(presentation.title.isEmpty == false)
        #expect(presentation.message.isEmpty == false)
        #expect(presentation.symbolName.isEmpty == false)
    }

    /// A title is a headline and carries no full stop; a message is a sentence
    /// and ends like one. Asserted because a screen reader runs the two
    /// together, and a message that trails off mid-thought reads as truncation.
    @Test("Every message is a complete sentence", arguments: ErrorPresentationCases.all)
    func everyMessageIsASentence(error: APIError) {
        let presentation = ErrorPresentation.of(error)

        #expect(presentation.message.hasSuffix(".") || presentation.message.hasSuffix("?"))
        #expect(presentation.title.hasSuffix(".") == false)
        #expect(presentation.title.first?.isUppercase == true)
    }

    /// **An SF Symbol that does not exist draws nothing at all and fails
    /// silently**, so a misspelling here is a blank failure screen — a worse
    /// outcome than the placeholder this replaces. Checked rather than
    /// eyeballed, because the eye is what it defeats.
    @Test("Every symbol actually exists", arguments: ErrorPresentationCases.all)
    func everySymbolRenders(error: APIError) {
        let name = ErrorPresentation.of(error).symbolName

        #expect(UIImage(systemName: name) != nil, "no SF Symbol named \(name)")
    }

    // MARK: - Moved from ResponseEnvelopeTests

    /// This assertion used to live on the error type, which owned its own copy.
    /// The copy moved out; what it was protecting — that every error the client
    /// can throw has something to say — is still worth protecting, one layer
    /// out, and now covers the case Task 2 added.
    @Test("Every error case the client can throw has copy")
    func everyErrorCaseHasCopy() {
        let errors: [APIError] = [
            .transport(.timedOut),
            .http(503),
            .decoding("unexpected shape"),
            .notJSON,
            .service(code: "1507", message: "Invalid request"),
            .sessionExpired(code: "0012"),
            .slotTimesMissing,
        ]

        for error in errors {
            let presentation = ErrorPresentation.of(error)

            #expect(presentation.title.isEmpty == false, "\(error)")
            #expect(presentation.message.isEmpty == false, "\(error)")
        }
    }
}
