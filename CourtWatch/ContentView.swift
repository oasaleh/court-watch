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
            List(facilities) { facility in
                Button {
                    favorites.toggle(facility.id)
                } label: {
                    row(for: facility)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(for facility: Facility) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(facility.name)

                // Plain interpolation of the count. The generic `formatted`
                // convenience matches the date-discipline guard's pattern and
                // fails the build — integer formatting is not date handling,
                // but the guard cannot tell the two apart and is right not to
                // try.
                Text(facility.courts.count == 1 ? "1 court" : "\(facility.courts.count) courts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if favorites.contains(facility.id) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
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
