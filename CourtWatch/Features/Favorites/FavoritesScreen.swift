//
//  FavoritesScreen.swift
//  CourtWatch
//
//  What you see when you open the app: every court at the places you chose,
//  with its whole remaining day, or an invitation to choose some.
//
//  This is UI-09, in the user's own words — *"I'd like to be able to see
//  availability for all in one glance. I do not want to have to click on one
//  court to see its availability."* Nothing on this screen is tappable and
//  nothing leads anywhere; opening the app and scrolling is the whole
//  interaction.
//
//  The branch is driven by what *resolved*, not by how many names are saved.
//  Those two disagree in exactly the case Phase 3 was built around: a user whose
//  saved places no longer match anything has a non-empty selection and nothing
//  to show. Keying the prompt off the saved count would show them a blank
//  screen; keying it off the resolved result invites them to pick again, while
//  their saved names stay on disk waiting to come back.
//
//  Three different screens here are otherwise all "a list with no courts in it",
//  and they must not be confusable: nothing chosen, nothing left today, and
//  nothing loaded. The first two live here and say plainly which they are.
//

import SwiftUI

struct FavoritesScreen: View {

    let facilities: [Facility]
    let favorites: FavoritesStore

    /// What is left of today, resolved by the caller.
    ///
    /// Taken as a parameter rather than computed, so this screen stays a pure
    /// function of what it is handed and the clock keeps a single owner. A view
    /// that read the time itself would be untestable, and two views that both
    /// did it could disagree about what hour it is.
    let day: VisibleDay

    /// Courts whose data was short, courts that could not be read at all, and
    /// every warning the response carried.
    ///
    /// Handed in for the same reason as `day`: this screen is a function of
    /// what it is given. `NoticeText` decides which of them are worth a
    /// sentence, and almost always the answer is none.
    let degradedCourts: [String]
    let unreadableCourts: Int
    let warnings: [String]

    /// Opening the picker is the caller's business.
    ///
    /// This screen has two routes into it — the invitation below and a toolbar
    /// button above — and both must lead to the same place. Handing the action
    /// in keeps one owner of that presentation rather than two pieces of state
    /// that can disagree.
    let onChooseFacilities: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Reading `favorites.facilityNames` here is what subscribes this
        // screen to changes, so toggling inside the picker updates it live.
        let resolved = FavoriteResolution.resolve(
            favorites: favorites.facilityNames, against: facilities)

        let notices = NoticeText.lines(
            unmatchedFavorites: resolved.unmatched,
            degradedCourts: degradedCourts,
            unreadableCourts: unreadableCourts,
            warnings: warnings
        )

        if resolved.matched.isEmpty {
            invitation
        } else if day.isFinished {
            finishedForToday
        } else {
            grid(for: resolved.matched, notices: notices)
        }
    }

    private var invitation: some View {
        ContentUnavailableView {
            Label("Choose Your Facilities", systemImage: "figure.tennis")
        } description: {
            Text("Pick the places you play at and their courts will show up here.")
        } actions: {
            Button("Choose Facilities", action: onChooseFacilities)
                .buttonStyle(.borderedProminent)
        }
    }

    /// TIME-07. Every slot published for today has fully elapsed.
    ///
    /// Deliberately worded and illustrated so it cannot be mistaken for the
    /// invitation above or for a failed load — an empty grid would look like all
    /// three at once. Note that under the ruled slot semantics this state begins
    /// at 11 PM, an hour after the last slot *starts*, because a slot survives
    /// until its own hour ends.
    private var finishedForToday: some View {
        ContentUnavailableView {
            Label("That's It for Today", systemImage: "moon.zzz")
        } description: {
            Text("Every court time for today has passed. Check back tomorrow morning.")
        }
    }

    /// One section per chosen place, every court in it, its whole remaining day.
    ///
    /// The width is measured once, here, for the whole screen. Every section
    /// then draws at the same tier, which is what keeps the columns lined up
    /// across facilities without any shared scrolling machinery — and what makes
    /// "no horizontal scrolling" achievable at all.
    private func grid(for facilities: [Facility], notices: [String]) -> some View {
        GeometryReader { proxy in
            let layout = StripLayout.resolve(
                availableWidth: proxy.size.width,
                slotCount: day.slots.count,
                dynamicTypeSize: dynamicTypeSize
            )
            let cellWidth = StripLayout.cellWidth(
                availableWidth: proxy.size.width,
                slotCount: day.slots.count
            )

            List {
                if notices.isEmpty == false {
                    noticeStrip(notices)
                }

                ForEach(facilities) { facility in
                    FacilityAvailabilitySection(
                        facility: facility,
                        day: day,
                        layout: layout,
                        cellWidth: cellWidth
                    )
                }
            }
            .listStyle(.plain)
        }
    }

    /// One line each for what was kept and never said.
    ///
    /// Low emphasis, no colour, no dismissal, and absent entirely when there is
    /// nothing to say — which is every normal day, including both captured
    /// ones. Deliberately *not* a fourth empty state: these sit above a grid
    /// that exists and must never be the only thing on the screen.
    ///
    /// Grouped as one accessibility element so VoiceOver reads it as a short
    /// paragraph rather than as a run of unrelated fragments before the courts
    /// start.
    private func noticeStrip(_ notices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notices, id: \.self) { notice in
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .listRowSeparator(.hidden)
    }
}

#Preview("Nothing chosen") {
    @Previewable @State var favorites = FavoritesStore()

    return NavigationStack {
        FavoritesScreen(
            facilities: [],
            favorites: favorites,
            day: .empty,
            degradedCourts: [],
            unreadableCourts: 0,
            warnings: [],
            onChooseFacilities: {}
        )
        .navigationTitle("Courts")
    }
}
