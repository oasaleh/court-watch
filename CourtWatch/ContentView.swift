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

/// The status line: how old the data is, and — only when something went wrong —
/// that the last refresh did not work.
///
/// The active filter is deliberately *not* repeated here. It is named in the
/// toolbar, in the control that sets it, where state belongs next to the thing
/// that changes it — and that control uses `Text`, which was measured not to
/// collapse to a bare icon the way a `Label` does. Saying it twice on one screen
/// was noise.
///
/// A failure is not a second permanent field either: it is present only when
/// the last refresh failed, which makes it a notice rather than a status.
nonisolated enum StatusLineText {

    /// `failure` defaults to nothing, so the ordinary line is unchanged
    /// character for character — the most likely regression here is a stray
    /// separator on a line that is on screen every second the app is open.
    ///
    /// The failure's words come from `ErrorPresentation`, the same mapping the
    /// failure screen uses, rather than from a second short phrase written for
    /// this line. Two independent strings for one condition is precisely the
    /// drift that deleting the old copy property was meant to prevent.
    ///
    /// Joined with a full stop rather than a separator glyph, because VoiceOver
    /// reads this as one announcement and a middle dot is not a word.
    static func line(
        filter: StartTimeFilter, fetchedAt: Date, failure: APIError? = nil
    ) -> String {
        let updated = LastRefreshedText.line(at: fetchedAt)

        guard let failure else { return updated }

        return "\(ErrorPresentation.of(failure).title). \(updated)"
    }
}

struct ContentView: View {

    /// The process-wide session, handed down rather than built here.
    ///
    /// This screen used to construct one inside `load()`, so every fetch
    /// performed its own handshake and got its own cookie jar. Signing in
    /// cannot survive that: the login state lives in the jar of the session
    /// that authenticated, and an availability POST on a different jar
    /// carrying a real customer id was measured to be refused outright.
    let session: CourtSession

    /// The account state. Read for exactly two things: which identity the fetch
    /// carries, and what the toolbar control says.
    let account: AccountStore

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

        /// The data, when it arrived, the window it came from, and whether the
        /// most recent refresh over it failed.
        ///
        /// That last one looks like the "loaded with an error still set" state
        /// this enum was built to forbid, and it is not. Loaded-and-the-last-
        /// refresh-failed is real, common, and was until now entirely unspoken.
        /// What must not happen is it being stored *beside* the data, where the
        /// two can drift — so it lives inside the case, alongside the fetch
        /// moment and the window, which are there for the identical reason:
        /// they cannot exist without data to describe and must not outlive it.
        /// A sibling `@State` flag would reintroduce exactly what the enum
        /// prevents.
        case loaded(
            Availability, fetchedAt: Date, window: RequestedWindow?, lastFailure: APIError?)

        /// Carries what went wrong, so the screen can ask the mapping what to
        /// say rather than holding an opinion of its own.
        ///
        /// Inside the case rather than in a separate property, for the same
        /// reason the fetch moment and the window live inside the loaded case:
        /// a failure that cannot exist without a failed load cannot drift from
        /// it.
        case failed(APIError)
    }

    @State private var state: LoadState = .loading
    @State private var isChoosingFacilities = false

    /// Whether the account sheet is up.
    @State private var isShowingAccount = false

    /// Whether a fetch is in flight.
    ///
    /// Exists to stop retries piling up. Five impatient taps used to start five
    /// fetches, each of which may make two requests, against a WAF-fronted host
    /// that belongs to the Township — SESS-06 forbids unattended traffic and
    /// this screen is the one place in the app a single user can generate a
    /// burst of it.
    ///
    /// **Checked structurally and by hand rather than by test:** the suite does
    /// not exercise views, so nothing here is covered by it. The copy the
    /// failure screen displays is fully covered by the presentation tests; that
    /// this screen asks for it, and that this flag holds the door, are
    /// checkpoint lines.
    @State private var isFetching = false

    /// The active start-time filter.
    ///
    /// Narrowing the visible day is done from data already held; only a widening
    /// the app has computed it cannot serve costs a request.
    @State private var filter = StartTimeFilter.fromNow

    /// Whether the refresh time is currently on screen.
    ///
    /// It appears on every load and withdraws a few seconds later. Pinning it
    /// permanently spent the bottom of every screen on a line that is only
    /// interesting immediately after a refresh.
    ///
    /// Note what this costs: a refresh that fails leaves the old data and its
    /// original timestamp, and *that unchanged time* was the signal that the
    /// refresh did not work. Once the line withdraws, the signal goes with it,
    /// so failure needs to be said out loud rather than implied.
    @State private var showsRefreshTime = true

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
                // The account control, in the one toolbar slot that was empty.
                // The two existing trailing actions were placed deliberately
                // in Phase 4 and are untouched: a third there would crowd them
                // and would rank the least-used control in the app alongside
                // the two most used.
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            account.refreshStoredCredentialAvailability()
                            isShowingAccount = true
                        } label: {
                            Image(
                                systemName: account.identity.isSignedIn
                                    ? "person.crop.circle.fill" : "person.crop.circle")
                        }
                        // Names the **state**, not just the control. "Account"
                        // tells a VoiceOver user nothing about whether they are
                        // signed in, and that is the one thing this control
                        // exists to expose. The symbol is a supplement to this,
                        // never the only statement of state.
                        .accessibilityLabel(
                            account.identity.isSignedIn
                                ? "Account, signed in" : "Account, not signed in")
                    }
                }
                .sheet(isPresented: $isShowingAccount) {
                    // Its own stack, so it gets a title bar of its own rather
                    // than borrowing the one behind it.
                    NavigationStack {
                        Group {
                            if account.identity.isSignedIn {
                                AccountSummary(account: account)
                            } else {
                                SignInScreen(account: account)
                            }
                        }
                        .toolbar {
                            // A close control, not Done. Nothing here is
                            // committed by dismissing — sign-in has its own
                            // button — and Done means "complete or save".
                            ToolbarItem(placement: .cancellationAction) {
                                Button(role: .close) { isShowingAccount = false }
                            }
                        }
                    }
                }
        }
        // `.task` rather than `.onAppear`: it gives an async context and
        // cancels itself when the view goes away. Keyed on the identity so
        // signing in or out takes effect without the user having to think about
        // it — one extra fetch, caused by one deliberate action, through the
        // same load path and the same in-flight guard. Nothing here polls,
        // retries on a timer, or refreshes in the background.
        .task(id: account.identity) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Finding today's courts…")

        case .failed(let error):
            failure(error)

        case .loaded(let availability, let fetchedAt, let window, let lastFailure):
            loaded(
                availability, fetchedAt: fetchedAt, heldWindow: window,
                lastFailure: lastFailure)
        }
    }

    /// The failure screen, in the words the mapping chose.
    ///
    /// This view holds no opinion about what any error means and branches on no
    /// error case — the same rule the cells follow, and for the same reason:
    /// two opinions can disagree, and the one that would be wrong here is the
    /// one telling a user their connection is broken when it is not.
    private func failure(_ error: APIError) -> some View {
        let presentation = ErrorPresentation.of(error)

        return ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.symbolName)
        } description: {
            Text(presentation.message)
        } actions: {
            retry(presentation.retry)
        }
    }

    /// Try Again, always present, with its weight set by the odds.
    ///
    /// The button never disappears even where retrying is unlikely to help: a
    /// truncated response can fail to decode transiently, the Township can
    /// publish times late, and taking away the only control on the screen
    /// leaves the user nothing to do but force-quit. What would be dishonest is
    /// a message implying a retry will work when it will not — so the sentence
    /// carries that, and the prominence carries it again.
    @ViewBuilder
    private func retry(_ strength: RetryStrength) -> some View {
        let button = Button("Try Again") {
            Task {
                // Belt and braces beside `.disabled` below: the control is
                // already inert while a fetch runs, and the loading state
                // replaces it with a spinner, but setting `.loading` for a
                // fetch that the guard in `load` then refuses would strand the
                // screen on a spinner that never resolves.
                guard isFetching == false else { return }

                state = .loading
                await load()
            }
        }
        // Nothing may queue up behind an impatient user.
        .disabled(isFetching)

        switch strength {
        case .worthTrying:
            button.buttonStyle(.borderedProminent)

        case .probablyPersistent:
            button.buttonStyle(.bordered)
        }
    }

    private func loaded(
        _ availability: Availability, fetchedAt: Date, heldWindow: RequestedWindow?,
        lastFailure: APIError?
    ) -> some View {
        let facilities = availability.facilities
        let statusLine = StatusLineText.line(
            filter: filter, fetchedAt: fetchedAt, failure: lastFailure)

        // A failure pins the line; the countdown belongs to the success case.
        //
        // A failure announced for three seconds and then silently withdrawn is
        // barely better than one never announced — worse, arguably, because the
        // app then looks settled and correct. This is a *condition* rather than
        // a second clock on purpose: nothing in this app schedules work, and a
        // failed refresh deliberately does not advance the fetch moment the
        // countdown below is keyed on, so no new countdown starts by itself and
        // none needs to be cancelled.
        //
        // **Not covered by the suite** — no test observes a rendered view, so
        // whether the line actually stays put is a checkpoint line.
        let showsStatusLine = lastFailure != nil || showsRefreshTime

        return FavoritesScreen(
            facilities: facilities,
            favorites: favorites,
            day: VisibleDay.resolve(
                availability: availability, now: clock.now, startingAt: filter.start),
            degradedCourts: availability.degradedCourts,
            unreadableCourts: availability.unreadableCourts,
            warnings: availability.courts.flatMap(\.warnings),
            onChooseFacilities: { isChoosingFacilities = true }
        )
        // The platform pull gesture, awaiting the same load path the initial
        // task uses. One function, two callers: a second copy would drift, and
        // the retry-and-handshake behaviour lives in the client where it is
        // already tested.
        //
        // Always the whole day, never a window.
        //
        // Server-side trimming looked like a free saving, but the trimmed
        // response *is* the app's picture of the day — so after narrowing to
        // 3 PM the filter menu could only offer 3 PM onwards, and the earlier
        // hours became unreachable. Narrowing was a one-way door.
        //
        // Holding the full day costs one request either way, makes every hour
        // selectable, and is required regardless: an explicit start time reaches
        // back past now, which needs hours the server would have trimmed away.
        .refreshable { await load() }
        // Pinned to the bottom edge rather than placed in the list, so it stays
        // visible however far the user has scrolled. UI-07 is about not having
        // to hunt for it.
        .safeAreaInset(edge: .bottom) {
            // Shown briefly after a load rather than pinned. It answers "did
            // that work?" at the moment the question is being asked, and then
            // stops taking up the bottom of every screen for the rest of the
            // session — unless the answer was *no*, in which case the question
            // has not been answered but raised, and the line stays until a
            // later refresh answers it.
            //
            // The space is reserved whether or not the text is drawn, so the
            // grid does not jump when it goes.
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
                .opacity(showsStatusLine ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: showsStatusLine)
                .accessibilityLabel(statusLine)
                .accessibilityHidden(showsStatusLine == false)
                // Keyed on the fetch moment, so every load — first, refresh, or
                // filter change — restarts the countdown rather than only the
                // first one. `.task(id:)` cancels the previous one, so two loads
                // in quick succession cannot leave an early timer to hide the
                // later message.
                .task(id: fetchedAt) {
                    showsRefreshTime = true

                    try? await Task.sleep(for: .seconds(3))

                    // Cancellation lands here as a no-op: a superseded countdown
                    // must not hide a message it does not own.
                    guard Task.isCancelled == false else { return }

                    showsRefreshTime = false
                }
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
    /// Changes the filter. Never fetches.
    ///
    /// The whole day is always held, so every filter — narrower or wider — is a
    /// subset of data already in hand. Instant, free, works offline, and costs
    /// the WAF-fronted host nothing.
    private func apply(
        _ choice: StartTimeFilter, over availability: Availability,
        heldWindow: RequestedWindow?
    ) {
        filter = choice
    }

    /// The one path to the network, for the first load, every refresh, and the
    /// occasional filter change that genuinely needs one.
    private func load(window: RequestedWindow? = nil) async {
        // One fetch at a time. Refused rather than queued: a second fetch
        // started while the first is running would double the traffic for an
        // answer the user is already waiting for.
        //
        // Released on *every* exit path, the failure path included. Leaving it
        // set after a failed load would make the app unable to retry at all,
        // converting a recoverable state into a dead end — a worse bug than the
        // one this guard fixes.
        guard isFetching == false else { return }

        isFetching = true
        defer { isFetching = false }

        do {
            // Built from the session the app owns, so the token and cookies
            // that authenticated are the ones that carry this POST. The
            // harness, when one is configured, is chosen at that point of
            // ownership rather than here.
            let client = AvailabilityClient(session: session)

            // The translation from "what window is wanted" to "how the client is
            // asked for it" happens here, because this is the only file allowed
            // to know both.
            let clientWindow = window.map { wanted in
                AvailabilityClient.SlotWindow(start: wanted.start, end: wanted.end)
            }

            let availability = try await client.fetch(
                on: clock.today, window: clientWindow, as: account.identity)

            // A signed-in request the server refused was served anonymously
            // instead, so the account surface must stop saying otherwise.
            if availability.downgradedToAnonymous {
                account.reportAnonymousFallback()
            }

            // Data, the moment it arrived, and the window it came from are
            // stored in one transition, so they cannot drift apart. The moment
            // comes from the injected clock rather than a fresh system read, so
            // a test can pin it. A success clears any failure being reported.
            state = .loaded(
                availability.availability, fetchedAt: clock.now, window: window,
                lastFailure: nil)
        } catch {
            // Anything that is not one of the client's own failures is treated
            // as the far end not answering: true of every case that can reach
            // here, retryable, and blaming nothing the user controls.
            let failure = error as? APIError ?? .transport(.unknown)

            // Except a cancellation, which is this view superseding its own
            // work. `.task(id:)` cancels and restarts on every identity change,
            // so signing in or out during a refresh lands here — and a
            // replacement load is already running. Reporting it would put a
            // server-outage notice on screen for a routine action, and it would
            // stay there, because the status line persists while a failure is
            // recorded.
            //
            // Returning before the state is touched leaves the previous data
            // and timestamp exactly as they were, for the new load to replace.
            if failure.isCancellation || error is CancellationError { return }

            // A refresh that fails keeps the last good data *and its original
            // timestamp* on screen. Replacing a working grid with an error is
            // the more common implementation and the wrong one: the user can
            // still use what is there.
            //
            // The timestamp must not move. Saying "couldn't update" beside a
            // time that had silently advanced would be a worse lie than saying
            // nothing at all — which is what the app did until now.
            if case .loaded = state {
                state = keepingData(reporting: failure)
                return
            }

            state = .failed(failure)
        }
    }

    /// The held data, its original fetch moment and window, with the failure
    /// recorded beside them — inside the same case, so the report cannot
    /// outlive the thing it describes.
    private func keepingData(reporting failure: APIError) -> LoadState {
        guard case .loaded(let availability, let fetchedAt, let window, _) = state else {
            return .failed(failure)
        }

        return .loaded(
            availability, fetchedAt: fetchedAt, window: window, lastFailure: failure)
    }
}

#Preview {
    // The same session the app builds, so the preview is not a second
    // arrangement that could drift. Nothing fetches until `.task` runs.
    let session = CourtWatchApp.makeSession()

    ContentView(
        session: session,
        account: AccountStore(
            session: session,
            credentialStore: CredentialStore(),
            client: SignInClient(session: session),
            probe: SessionProbe(session: session)),
        favorites: FavoritesStore())
}
