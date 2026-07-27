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

/// The always-visible status line: how old the data is.
///
/// The active filter is deliberately *not* repeated here. It is named in the
/// toolbar, in the control that sets it, where state belongs next to the thing
/// that changes it — and that control uses `Text`, which was measured not to
/// collapse to a bare icon the way a `Label` does. Saying it twice on one screen
/// was noise.
nonisolated enum StatusLineText {

    static func line(filter: StartTimeFilter, fetchedAt: Date) -> String {
        LastRefreshedText.line(at: fetchedAt)
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
    ///
    /// And it carries the window the data was fetched under, for the same
    /// reason again. Whether the app can answer a widened filter locally depends
    /// on the two agreeing, so they are written in one transition rather than
    /// stored separately where they could drift.
    private enum LoadState {
        case loading
        case loaded(Availability, fetchedAt: Date, window: RequestedWindow?)
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var isChoosingFacilities = false

    /// The active start-time filter.
    ///
    /// Narrowing the visible day is done from data already held; only a widening
    /// the app has computed it cannot serve costs a request.
    @State private var filter = StartTimeFilter.fromNow

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

        case .loaded(let availability, let fetchedAt, let window):
            loaded(availability, fetchedAt: fetchedAt, heldWindow: window)
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

    private func loaded(
        _ availability: Availability, fetchedAt: Date, heldWindow: RequestedWindow?
    ) -> some View {
        let facilities = availability.facilities

        return FavoritesScreen(
            facilities: facilities,
            favorites: favorites,
            day: VisibleDay.resolve(
                availability: availability, now: clock.now, startingAt: filter.start),
            onChooseFacilities: { isChoosingFacilities = true }
        )
        // The platform pull gesture, awaiting the same load path the initial
        // task uses. One function, two callers: a second copy would drift, and
        // the retry-and-handshake behaviour lives in the client where it is
        // already tested.
        //
        // The active window travels with it. A refresh is a round trip that is
        // being paid for anyway, which is the one moment server-side trimming is
        // a real saving rather than an extra request.
        .refreshable {
            await load(
                window: filter.window(
                    over: availability.slotTimes, slotMinutes: availability.slotMinutes))
        }
        // Pinned to the bottom edge rather than placed in the list, so it stays
        // visible however far the user has scrolled. UI-07 is about not having
        // to hunt for it.
        .safeAreaInset(edge: .bottom) {
            Text(StatusLineText.line(filter: filter, fetchedAt: fetchedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
                .accessibilityLabel(
                    StatusLineText.line(filter: filter, fetchedAt: fetchedAt))
        }
        .toolbar {
            // The active choice is shown, not just an icon. A user who has
            // forgotten they set a six o'clock filter and sees three slots must
            // be able to see why — otherwise the app is lying by omission about
            // how busy the courts are.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(StartTimeFilter.choices(for: availability.slotTimes)) { choice in
                        Button {
                            apply(choice, over: availability, heldWindow: heldWindow)
                        } label: {
                            if choice == filter {
                                Label(choice.label, systemImage: "checkmark")
                            } else {
                                Text(choice.label)
                            }
                        }
                    }
                } label: {
                    // A `Label` in an iOS toolbar collapses to its icon whatever
                    // label style is asked for — measured, not assumed — which
                    // would hide the one thing this control exists to disclose.
                    // `Text` does not collapse, so an active filter is named in
                    // the toolbar as well as in the status line below.
                    if filter.start == nil {
                        Label("Start time", systemImage: "clock")
                    } else {
                        Text(filter.label)
                    }
                }
            }

            // The second route into the picker: the invitation is for
            // someone who has chosen nothing, this is for someone who has
            // and wants to change it. A semantic placement rather than a
            // navigation-bar one, so it stays correct on iPad.
            ToolbarItem(placement: .primaryAction) {
                Button("Facilities", systemImage: "sportscourt") {
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

    /// Changes the filter, and fetches only if the data in hand cannot answer it.
    ///
    /// Narrowing, or widening while the whole day is still held, is served
    /// locally and costs nothing. Widening past what a windowed refresh left
    /// behind is the one case that must go back to the server — and the answer
    /// is computed by `covers`, never guessed.
    private func apply(
        _ choice: StartTimeFilter, over availability: Availability,
        heldWindow: RequestedWindow?
    ) {
        filter = choice

        let requested = choice.window(
            over: availability.slotTimes, slotMinutes: availability.slotMinutes)
        guard StartTimeFilter.covers(held: heldWindow, requested: requested) == false else {
            return
        }

        Task { await load(window: requested) }
    }

    /// The one path to the network, for the first load, every refresh, and the
    /// occasional filter change that genuinely needs one.
    private func load(window: RequestedWindow? = nil) async {
        do {
            let client = AvailabilityClient(session: CourtSession())

            // The translation from "what window is wanted" to "how the client is
            // asked for it" happens here, because this is the only file allowed
            // to know both.
            let clientWindow = window.map { wanted in
                AvailabilityClient.SlotWindow(start: wanted.start, end: wanted.end)
            }

            let availability = try await client.fetch(on: clock.today, window: clientWindow)

            // Data, the moment it arrived, and the window it came from are
            // stored in one transition, so they cannot drift apart. The moment
            // comes from the injected clock rather than a fresh system read, so
            // a test can pin it.
            state = .loaded(availability, fetchedAt: clock.now, window: window)
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
