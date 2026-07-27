//
//  APIError.swift
//  CourtWatch
//
//  Success and failure are decided by `headers.response_code` and nothing else.
//
//  The endpoint answers `200 OK` for every outcome, including "Invalid CSRF
//  token" and "Invalid request". A client that branches on the HTTP status
//  therefore has a retry path that never executes and reports failures as
//  successes. The status is not consulted anywhere in this file, and a grep
//  gate in the phase verification keeps it that way.
//
//  This type carries no user-facing copy. It used to, as a placeholder, and the
//  property was deleted rather than reworded: a presentation is a title *and* a
//  sentence *and* a symbol *and* a claim about whether retrying helps, which is
//  not a string; an API-layer error type is the wrong home for interface
//  decisions; and leaving the old property beside the new mapping would create
//  two sources of copy that drift, which is the failure a single mapping exists
//  to prevent. `ErrorPresentation` is the one place a failure becomes words.
//

import Foundation

nonisolated enum APIError: Error, Equatable, Sendable {

    /// The request never completed. Carries the underlying `URLError.Code` so
    /// "no connection" can read differently from "timed out".
    case transport(URLError.Code)

    /// A genuinely non-2xx response. The API is not expected to send one, but
    /// the WAF or a proxy in front of it might, and that is worth telling apart
    /// from an application-level failure.
    case http(Int)

    /// The response arrived but did not have the expected shape.
    case decoding(String)

    /// The response was not the API at all.
    ///
    /// Split out from `decoding` because the HTTP status is deliberately never
    /// judged — the endpoint answers 200 for everything — so a WAF
    /// interstitial or a captive-portal login page arrives as a body that fails
    /// to parse and would otherwise be reported as a schema change.
    ///
    /// The two deserve opposite sentences. "The court system changed and the
    /// app needs an update" is honest for a shape change and misleading for a
    /// block page, and given that an F5 ASM WAF fronts the host, the block page
    /// is the more likely of the two.
    ///
    /// Carries nothing. There is no diagnostic here worth the risk of putting a
    /// third party's HTML anywhere near a screen.
    case notJSON

    /// A non-success code that re-handshaking will not fix.
    case service(code: String, message: String?)

    /// An expiry code that survived the one permitted re-handshake and retry.
    ///
    /// Carries the code only. The CSRF token and cookies must never appear in
    /// an error value, a log line, or anything that might be shown or reported.
    case sessionExpired(code: String)

    /// A successful response that published no usable slot times, which leaves
    /// nothing to render.
    case slotTimesMissing
}

nonisolated enum ResponseCode {

    /// The only code that means success.
    static let success = "0000"

    /// Codes meaning "your handshake is stale — get a new one and replay".
    ///
    /// Held as a set rather than a `switch` so the retry logic in
    /// `AvailabilityClient` and the tests that pin this behaviour read from one
    /// source. Adding a newly observed code should require one edit, here.
    static let expiry: Set<String> = ["0002", "0007", "0010", "0012", "0021"]

    enum Classification: Equatable, Sendable {
        case success
        case expired(String)
        case service(code: String, message: String?)
    }

    /// Reads the outcome from the envelope. The HTTP status is not a parameter
    /// and could not be consulted here even by mistake.
    static func classify(_ headers: ResponseHeaders) -> Classification {
        let code = headers.responseCode

        if code == success {
            return .success
        }

        if expiry.contains(code) {
            return .expired(code)
        }

        return .service(code: code, message: headers.responseMessage)
    }
}
