//
//  ContentView.swift
//  CourtWatch
//
//  Created by Omar Saleh on 7/26/26.
//
//  The root screen: fetch today's courts once, then hand the derived places to
//  the rest of the interface.
//
//  This is the only view that talks to the network. Everything below it takes
//  the data it needs as a parameter, which keeps those screens previewable and
//  keeps a client out of the view layer, where it would otherwise be
//  constructed afresh on every redraw.
//
//  Loading and failure are deliberately unfinished here. A spinner and one
//  line of text are enough to see the real screens working; the state taxonomy
//  belongs to a later phase, and anything invested in it now gets rewritten.
//

import SwiftUI

struct ContentView: View {

    let favorites: FavoritesStore

    /// One value rather than three.
    ///
    /// `isLoading` beside an `error` beside a list permits combinations that
    /// mean nothing — loading and failed at the same time, loaded with an
    /// error still set. An enum makes those unrepresentable rather than merely
    /// unlikely.
    private enum LoadState {
        case loading
        case loaded([Facility])
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var isChoosingFacilities = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Courts")
        }
        // `.task` rather than `.onAppear`: it gives an async context and
        // cancels itself when the view goes away. It runs once — nothing here
        // polls, retries on a timer, or refreshes in the background.
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()

        case .failed:
            Text("Couldn't load today's courts.")

        case .loaded(let facilities):
            FavoritesScreen(
                facilities: facilities,
                favorites: favorites,
                onChooseFacilities: { isChoosingFacilities = true }
            )
            .toolbar {
                // The second route into the picker: the invitation is for
                // someone who has chosen nothing, this is for someone who has
                // and wants to change it. A semantic placement rather than a
                // navigation-bar one, so it stays correct on iPad.
                ToolbarItem(placement: .primaryAction) {
                    Button("Facilities", systemImage: "slider.horizontal.3") {
                        isChoosingFacilities = true
                    }
                }
            }
            .sheet(isPresented: $isChoosingFacilities) {
                // Its own stack, so the picker gets a title bar and a search
                // field of its own rather than borrowing the one behind it.
                NavigationStack {
                    FacilityPickerScreen(facilities: facilities, favorites: favorites)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isChoosingFacilities = false }
                            }
                        }
                }
            }
        }
    }

    private func load() async {
        do {
            let client = AvailabilityClient(session: CourtSession())
            let availability = try await client.fetch(on: SystemClock().today)
            state = .loaded(availability.facilities)
        } catch {
            state = .failed
        }
    }
}

#Preview {
    ContentView(favorites: FavoritesStore())
}
