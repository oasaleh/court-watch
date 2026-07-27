//
//  ContentView.swift
//  CourtWatch
//
//  Created by Omar Saleh on 7/26/26.
//
//  The root screen: fetch today's courts, then hand the derived places to the
//  rest of the interface.
//
//  This is the only view that talks to the network. Everything below it takes
//  the data it needs as a parameter, which keeps those screens previewable and
//  keeps a client out of the view layer, where it would otherwise be
//  constructed afresh on every redraw.
//
//  Staleness is the thing this screen is careful about. Availability decays
//  quickly — a court that was free twenty minutes ago may not be — so the app
//  says when it last heard from the server, and a refresh that fails leaves the
//  old answer *and its old timestamp* on screen rather than pretending. Seeing
//  that the time did not move is how a user learns the data did not get newer.
//

import SwiftUI

/// The last-refreshed line, as a function so a test can assert it.
///
/// A time string is covered by the twelve-hour gate if and only if some test
/// asserts it, and no test observes a rendered screen. Rendering this correctly
/// in a body would prove nothing; producing it here does.
nonisolated enum LastRefreshedText {

    static func line(at moment: Date) -> String {
        "Updated \(CourtTime.string(from: moment))"
    }
}

struct ContentView: View {

    let favorites: FavoritesStore

    /// One value rather than three.
    ///
    /// `isLoading` beside an `error` beside a list permits combinations that
    /// mean nothing — loading and failed at the same time, loaded with an
    /// error still set. An enum makes those unrepresentable rather than merely
    /// unlikely, and a separate "refreshing" flag beside it would reintroduce
    /// exactly what the enum exists to prevent.
    ///
    /// The loaded case carries the whole `Availability` rather than just the
    /// grouped facilities, because what is left of today is derived from the
    /// slot list and the published slot length as well as the courts. Keeping
    /// the fetched value whole means that derivation has one input and cannot
    /// be assembled from pieces that came from different responses.
    ///
    /// It carries the fetch moment in the same case for the same reason: a
    /// timestamp cannot exist without data for it to describe, and cannot
    /// outlive the data it described.
    private enum LoadState {
        case loading
        case loaded(Availability, fetchedAt: Date)
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var isChoosingFacilities = false

    /// The single owner of "now" for the whole screen.
    ///
    /// Injectable so that what counts as elapsed, and what the refresh time
    /// reads, can both be pinned. Every view below takes the resolved day
    /// rather than reading a clock of its own.
    var clock: CourtClock = SystemClock()

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
            ProgressView("Finding today's courts…")

        case .failed:
            failure

        case .loaded(let availability, let fetchedAt):
            loaded(availability, fetchedAt: fetchedAt)
        }
    }

    /// One honest sentence and a way to try again.
    ///
    /// Deliberately not a taxonomy. Telling offline apart from a timeout from a
    /// decode failure from a non-`0000` response code, and designing the
    /// recovery for each, is a later phase's work, and anything richer built
    /// here would be rewritten by it.
    private var failure: some View {
        ContentUnavailableView {
            Label("Couldn't Load Today's Courts", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Check your connection and try again.")
        } actions: {
            Button("Try Again") {
                Task {
                    state = .loading
                    await load()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loaded(_ availability: Availability, fetchedAt: Date) -> some View {
        let facilities = availability.facilities

        return FavoritesScreen(
            facilities: facilities,
            favorites: favorites,
            day: VisibleDay.resolve(
                availability: availability, now: clock.now, startingAt: nil),
            onChooseFacilities: { isChoosingFacilities = true }
        )
        // The platform pull gesture, awaiting the same load path the initial
        // task uses. One function, two callers: a second copy would drift, and
        // the retry-and-handshake behaviour lives in the client where it is
        // already tested.
        .refreshable { await load() }
        // Pinned to the bottom edge rather than placed in the list, so it stays
        // visible however far the user has scrolled. UI-07 is about not having
        // to hunt for it.
        .safeAreaInset(edge: .bottom) {
            Text(LastRefreshedText.line(at: fetchedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
                .accessibilityLabel("Last updated \(CourtTime.string(from: fetchedAt))")
        }
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

    /// The one path to the network, for both the first load and every refresh.
    private func load() async {
        do {
            let client = AvailabilityClient(session: CourtSession())
            let availability = try await client.fetch(on: clock.today)

            // Data and the moment it arrived are stored in one transition, so
            // they cannot drift apart. The moment comes from the injected clock
            // rather than a fresh system read, so a test can pin it.
            state = .loaded(availability, fetchedAt: clock.now)
        } catch {
            // A refresh that fails keeps the last good data *and its original
            // timestamp* on screen. Replacing a working grid with an error is
            // the more common implementation and the wrong one: the user can
            // still use what is there, and the unchanged time is what tells
            // them it did not get newer.
            if case .loaded = state { return }

            state = .failed
        }
    }
}

#Preview {
    ContentView(favorites: FavoritesStore())
}
