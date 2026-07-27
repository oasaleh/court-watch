//
//  CourtWatchApp.swift
//  CourtWatch
//
//  Created by Omar Saleh on 7/26/26.
//

import SwiftUI

@main
struct CourtWatchApp: App {

    /// Built once for the life of the process and handed down.
    ///
    /// `@State` rather than a plain property: a `App` value is re-created as
    /// SwiftUI sees fit, and a store rebuilt mid-session would re-read from
    /// disk and discard anything held only in memory.
    @State private var favorites = FavoritesStore()

    /// One session — one CSRF token, one cookie jar — for the whole process.
    ///
    /// `@State` for the same reason as above, and here the cost of rebuilding
    /// is higher: a session replaced mid-flight throws away the cookie jar,
    /// and the jar is where being signed in actually lives.
    ///
    /// The screen used to mint one of these per load. That spent a handshake
    /// on every refresh against a host that belongs to the Township, for a
    /// token/jar pair Phase 2 measured to be reusable — and it made signing in
    /// impossible, because the request that authenticated and the request that
    /// fetched would have gone out on two different jars.
    ///
    /// **One session for one process, not a session kept on disk.** Persisting
    /// it across launches is out of scope by requirement rather than by
    /// oversight: this dies with the process and a relaunch re-handshakes.
    @State private var session = CourtWatchApp.makeSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session, favorites: favorites)
        }
    }

    /// The session the app runs on: the simulated one when a failure scenario
    /// is configured, the real one otherwise.
    ///
    /// The choice is made here, at the point of ownership, rather than at each
    /// load. Made per load it rebuilt the simulated session every time, which
    /// quietly breaks any scenario that is a claim about the *sequence* of
    /// loads rather than about one of them.
    static func makeSession() -> CourtSession {
        #if DEBUG
            return FailureSimulation.makeSession() ?? CourtSession()
        #else
            return CourtSession()
        #endif
    }
}
