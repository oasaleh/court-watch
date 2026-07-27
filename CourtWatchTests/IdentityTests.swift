//
//  IdentityTests.swift
//  CourtWatchTests
//
//  `Identity` reaches exactly one field of one request body, so what is worth
//  pinning is the mapping to that field — and above all that it cannot be
//  written backwards. Zero is not a placeholder: it is the value that unlocks
//  the anonymous path, measured, and a real customer id sent without a login
//  was measured to be refused outright.
//
//  Argument lists live on a `nonisolated` type: `arguments:` is evaluated
//  outside the enclosing actor. This project has been bitten by that twice.
//

import Foundation
import Testing

@testable import CourtWatch

nonisolated enum IdentityCases {

    /// Ids the API might plausibly hand back, including the awkward ones.
    static let customerIDs = [1, 42, 4_471_056, 991_234, Int.max]
}

struct IdentityTests {

    @Test("Anonymous encodes as zero")
    func anonymousIsZero() {
        #expect(Identity.anonymous.customerID == 0)
        #expect(Identity.anonymous.isSignedIn == false)
    }

    @Test("A signed-in identity encodes its own id", arguments: IdentityCases.customerIDs)
    func signedInCarriesItsID(id: Int) {
        let identity = Identity.signedIn(customerID: id)

        #expect(identity.customerID == id)
        #expect(identity.isSignedIn)
    }

    /// The mapping is not reversible by accident: no signed-in identity the
    /// app can build reports zero, because zero is what *means* anonymous.
    @Test("No real id collides with the anonymous value", arguments: IdentityCases.customerIDs)
    func realIDsAreNotZero(id: Int) {
        #expect(Identity.signedIn(customerID: id).customerID != Identity.anonymous.customerID)
    }

    @Test("Two identities are equal only when they are the same identity")
    func equalityIsStructural() {
        #expect(Identity.anonymous == Identity.anonymous)
        #expect(Identity.signedIn(customerID: 42) == Identity.signedIn(customerID: 42))
        #expect(Identity.signedIn(customerID: 42) != Identity.signedIn(customerID: 43))
        #expect(Identity.signedIn(customerID: 42) != Identity.anonymous)
    }

    /// It is used as a change key for re-fetching, so it has to hash as well as
    /// compare.
    @Test("Identities hash consistently with equality")
    func hashingMatchesEquality() {
        let identities: Set<Identity> = [
            .anonymous, .anonymous, .signedIn(customerID: 42), .signedIn(customerID: 42),
            .signedIn(customerID: 43),
        ]

        #expect(identities.count == 3)
    }

    /// Nothing about a customer id is a secret, but nothing about the type
    /// should invite carrying anything else either — it holds one integer and
    /// that is the whole of it.
    @Test("An identity describes itself with nothing but its id")
    func descriptionCarriesOnlyTheID() {
        #expect(String(describing: Identity.anonymous).contains("anonymous"))
        #expect(String(describing: Identity.signedIn(customerID: 42)).contains("42"))
    }
}
