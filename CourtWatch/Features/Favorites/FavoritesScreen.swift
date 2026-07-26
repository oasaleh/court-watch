//
//  FavoritesScreen.swift
//  CourtWatch
//
//  What you see when you open the app: the courts at the places you chose,
//  or an invitation to choose some.
//
//  The branch is driven by what *resolved*, not by how many names are saved.
//  Those two disagree in exactly the case this phase was built around: a user
//  whose saved places no longer match anything has a non-empty selection and
//  nothing to show. Keying the prompt off the saved count would show them a
//  blank screen; keying it off the resolved result invites them to pick again,
//  while their saved names stay on disk waiting to come back.
//
//  Deliberately not here: anything about time. This lists the courts at a
//  place and stops. Slots, availability and the grid are a later phase's, and
//  a court name in a list is the whole of what this one promised.
//

import SwiftUI

struct FavoritesScreen: View {

    let facilities: [Facility]
    let favorites: FavoritesStore

    /// Opening the picker is the caller's business.
    ///
    /// This screen has two routes into it — the invitation below and a toolbar
    /// button above — and both must lead to the same place. Handing the action
    /// in keeps one owner of that presentation rather than two pieces of state
    /// that can disagree.
    let onChooseFacilities: () -> Void

    var body: some View {
        // Reading `favorites.facilityNames` here is what subscribes this
        // screen to changes, so toggling inside the picker updates it live.
        let resolved = FavoriteResolution.resolve(
            favorites: favorites.facilityNames, against: facilities)

        // `resolved.unmatched` is intentionally unused. Saying "one of your
        // places has disappeared" is error-state design and belongs with the
        // rest of it; what this phase owes the user is that the name is kept,
        // and it is. The value is carried on ResolvedFavorites for that
        // surface to pick up — it has not been forgotten.

        if resolved.matched.isEmpty {
            invitation
        } else {
            courts(at: resolved.matched)
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

    /// One section per chosen place, every court in it.
    ///
    /// Every court, not a selection — that is the requirement in full. Section
    /// order follows the resolved list and court order follows the grouping
    /// that produced them, so neither is re-decided here.
    private func courts(at facilities: [Facility]) -> some View {
        List {
            ForEach(facilities) { facility in
                Section(facility.name) {
                    ForEach(facility.courts) { court in
                        Text(court.name)
                    }
                }
            }
        }
    }
}

#Preview("Nothing chosen") {
    @Previewable @State var favorites = FavoritesStore()

    return NavigationStack {
        FavoritesScreen(facilities: [], favorites: favorites, onChooseFacilities: {})
            .navigationTitle("Courts")
    }
}
