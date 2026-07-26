//
//  FixtureLoader.swift
//  CourtWatchTests
//
//  Loads the captured API payloads the offline suite runs against.
//
//  Two details here are specific to an Xcode test target and both were
//  established by running them, not by reading documentation:
//
//    * `Bundle.module` does not exist. It is generated only for SwiftPM
//      targets. The portable equivalent is a token class declared in this
//      bundle, which `Bundle(for:)` resolves back to the bundle that contains
//      it.
//    * Xcode flattens `Fixtures/` into the bundle root when it copies
//      resources, so the lookup takes no `subdirectory:` argument. Passing
//      `subdirectory: "Fixtures"` returns nil even though the file is present.
//
//  Because the tree is flattened, two fixtures with the same leaf name in
//  different folders would collide in the built bundle. Keep leaf names unique.
//

import Foundation
import Testing

/// Resolves the test bundle. `Bundle(for:)` needs a class, and it must be a
/// class compiled into this bundle — hence a private, empty one.
private final class BundleToken {}

nonisolated enum Fixture {

    /// Every fixture the suite loads, by leaf name. Listing them means a
    /// deleted or renamed file is a compile-time concern rather than a runtime
    /// surprise in whichever test happened to load it first.
    static let anonymous = "availability-anonymous"
    static let loggedIn = "availability-loggedin"
    static let shortResource = "availability-short-resource"

    /// The two full captures, for tests that must hold on both.
    ///
    /// This lives on a `nonisolated` type rather than at file scope for a
    /// reason worth keeping: the argument list of a parameterized `@Test` is
    /// evaluated outside the enclosing actor, so a plain file-scope `let` —
    /// which this module's default isolation makes main-actor-isolated —
    /// cannot be used as `arguments:` at all.
    static let bothCaptures = [anonymous, loggedIn]

    /// Raw bytes of a bundled JSON fixture.
    ///
    /// Fails through `#require` rather than returning an optional: a missing
    /// fixture means the resource never reached the test bundle, and that
    /// should report itself as exactly that rather than as a decode error
    /// several layers up.
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)

        let url = try #require(
            bundle.url(forResource: name, withExtension: "json"),
            """
            Missing fixture \(name).json in \(bundle.bundlePath).
            The file should be at CourtWatchTests/Fixtures/\(name).json and is \
            copied into the bundle root by the synchronized group. If it exists \
            on disk but not here, the resource did not reach the test target.
            """
        )

        return try Data(contentsOf: url)
    }
}
