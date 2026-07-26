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

    var body: some Scene {
        WindowGroup {
            ContentView(favorites: favorites)
        }
    }
}
