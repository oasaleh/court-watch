//
//  Identity.swift
//  CourtWatch
//
//  Who the app is, as far as the court system is concerned.
//
//  Two cases and one accessor, and it is kept this small on purpose. The whole
//  job of this type is to reach **one field of one request body**. Nothing else
//  in the app branches on it — not the grid, not the filter, not a cell — which
//  is what keeps the promise that availability cannot come to depend on being
//  signed in. One consumer means one place a dependency could grow, and that
//  place is a single integer.
//
//  `nonisolated` so it can be used from parameterized test arguments, which are
//  evaluated outside the enclosing actor.
//

import Foundation

nonisolated enum Identity: Equatable, Hashable, Sendable {

    case anonymous

    /// Signed in, carrying the id the sign-in reply handed back.
    case signedIn(customerID: Int)

    /// What goes on the wire.
    ///
    /// Zero is not a placeholder — it is the value that unlocks the anonymous
    /// path, measured. Exposing this as one accessor rather than letting the
    /// call site switch means the mapping cannot be written backwards, and the
    /// consumer has no branch at all.
    var customerID: Int {
        switch self {
        case .anonymous:
            return 0

        case .signedIn(let id):
            return id
        }
    }

    var isSignedIn: Bool {
        self != .anonymous
    }
}
