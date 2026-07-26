//
//  FacilityPickerScreen.swift
//  CourtWatch
//
//  Choosing the places you play at.
//
//  Two constraints shape this file:
//
//    * It takes a list of places and never a client. The network belongs to
//      the root screen; a view that built its own client would rebuild it on
//      every redraw and could not be previewed or reasoned about in isolation.
//    * Row titles are the derived place name, never a court name. That is the
//      whole of FAC-01 — the API returns 80 numbered courts and this list
//      shows the 27 places they belong to. The court *count* is a number, not
//      a court number, and is fine.
//
//  Filtering goes through FacilitySearch rather than a `contains` written
//  here. That module exists because the idiomatic call returns false for the
//  apostrophe the iOS keyboard inserts, and a second matching rule spelled out
//  inline is exactly how that bug would come back.
//

import SwiftUI

struct FacilityPickerScreen: View {

    let facilities: [Facility]
    let favorites: FavoritesStore

    @State private var query = ""

    /// Filtered, never re-sorted.
    ///
    /// `Facility.group` already returns these in name order and that order is
    /// covered by its own tests. Sorting again here would be a second ordering
    /// rule that could quietly disagree with the first.
    private var visible: [Facility] {
        facilities.filter { FacilitySearch.matches(facility: $0.name, query: query) }
    }

    var body: some View {
        // `List(visible)` takes its identity from `Facility.id`, the derived
        // name. An array index would do instead, and rows would change
        // identity as the filter narrows — animating into each other's places.
        List(visible) { facility in
            Button {
                // Persisted before this returns. There is no save button and
                // no edit mode to leave, which is what FAC-04 asks for.
                favorites.toggle(facility.id)
            } label: {
                row(for: facility)
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $query, prompt: "Search facilities")
        .overlay {
            // A blank list leaves the user unable to tell "no such place" from
            // "the app broke". The system form names the query back to them.
            if visible.isEmpty && query.isEmpty == false {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Facilities")
    }

    private func row(for facility: Facility) -> some View {
        let isFavorite = favorites.contains(facility.id)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(facility.name)

                // Plain interpolation. The generic `formatted` convenience
                // matches the date-discipline guard's pattern and fails the
                // build; integer formatting is not date handling, but the
                // guard cannot tell them apart and is right not to try.
                Text(facility.courts.count == 1 ? "1 court" : "\(facility.courts.count) courts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isFavorite {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        // Without this the row is only tappable where there is text.
        .contentShape(.rect)
        // A checkmark is invisible to VoiceOver, which would otherwise read
        // the row identically whether or not it is chosen.
        .accessibilityAddTraits(isFavorite ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    @Previewable @State var favorites = FavoritesStore()

    return NavigationStack {
        FacilityPickerScreen(
            facilities: [
                Facility(
                    name: "Shadowbend Tennis",
                    courts: (1...5).map {
                        Court(
                            id: $0, name: "Shadowbend Tennis \($0)",
                            facilityName: "Shadowbend Tennis", slots: [], warnings: [])
                    }),
                Facility(
                    name: "Harper's Landing Tennis Court",
                    courts: (1...2).map {
                        Court(
                            id: 100 + $0, name: "Harper's Landing Tennis Court \($0)",
                            facilityName: "Harper's Landing Tennis Court", slots: [], warnings: [])
                    }),
            ],
            favorites: favorites)
    }
}
