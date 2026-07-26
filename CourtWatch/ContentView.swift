//
//  ContentView.swift
//  CourtWatch
//
//  Created by Omar Saleh on 7/26/26.
//

import SwiftUI

/// The slot list the availability endpoint publishes for a tennis court.
/// Stand-in data: the real list arrives with the API client. It is here so the
/// time layer can be seen working on a device rather than only in tests.
private let publishedSlots = [
    "07:00:00", "08:00:00", "09:00:00", "10:00:00",
    "11:00:00", "12:00:00", "13:00:00", "14:00:00",
    "15:00:00", "16:00:00", "17:00:00", "18:00:00",
    "19:00:00", "20:00:00", "21:00:00", "22:00:00",
]

struct ContentView: View {
    // Spelled as a closure rather than a reference to the initializer: with
    // main-actor isolation applied by default, passing the initializer
    // directly drops that isolation and fails to compile.
    private let slots = publishedSlots.compactMap { SlotTime(apiString: $0) }

    var body: some View {
        NavigationStack {
            List(slots, id: \.self) { slot in
                Text(slot.displayString)
            }
            .navigationTitle("Today")
        }
    }
}

#Preview {
    ContentView()
}
