//
//  HTTPTransport.swift
//  CourtWatch
//
//  The seam that keeps the test suite hermetic.
//
//  Everything above this protocol is exercised without a network. `URLSession`
//  conforms below, and nothing else in the app constructs one — the session
//  that owns the cookie jar is created by `CourtSession` and handed out, so a
//  request cannot accidentally be sent through a jar that does not match the
//  CSRF token it carries.
//

import Foundation

nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {

    /// Maps Foundation's failures onto the app's error type at the boundary, so
    /// no caller has to know that `URLError` exists.
    ///
    /// Note the status code is returned, not judged. It is carried for the rare
    /// genuinely-non-2xx case a proxy or the WAF might produce; it is never
    /// what decides whether a request succeeded.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.http(-1)
            }

            return (data, http)
        } catch let error as URLError {
            throw APIError.transport(error.code)
        }
    }
}
