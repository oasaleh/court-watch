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

    /// Plain, non-technical copy.
    ///
    /// Phase 5 owns the real error presentation and will refine these strings.
    /// The property exists now so the error type is complete and Phase 5
    /// changes wording rather than restructuring the enum. No token, cookie, or
    /// URL is ever interpolated here.
    var userFacingMessage: String {
        switch self {
        case .transport:
            return "Could not reach the court system. Check your connection and try again."
        case .http:
            return "The court system returned an unexpected response. Try again shortly."
        case .decoding:
            return "The court system's response could not be read. It may have changed."
        case .service(_, let message):
            return message ?? "The court system rejected the request."
        case .sessionExpired:
            return "The session could not be renewed. Try again."
        case .slotTimesMissing:
            return "No court times were published for today."
        }
    }
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
