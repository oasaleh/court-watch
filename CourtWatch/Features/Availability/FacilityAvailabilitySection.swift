//
//  FacilityAvailabilitySection.swift
//  CourtWatch
//
//  One place: what is open here, and every court's remaining day beneath it.
//
//  The header's summary line is the point of this file. It answers "what's
//  open?" before the user parses a single cell, which is what the grid is for
//  and what a grid alone cannot do at a glance.
//
//  The summary line and the ruler labels are pure functions rather than string
//  interpolation buried in a drawn body, and that is not a style preference: a
//  time string is covered by the twelve-hour gate if and only if some test
//  asserts it, and no test observes a rendered screen. Producing them here, in
//  functions a test can call, is what puts them under `Scripts/test-24h.sh`.
//

import SwiftUI

/// The one derived sentence per facility, as text.
nonisolated enum AvailabilitySummaryText {

    /// "4 free at 6:00 PM", or "Nothing free today".
    ///
    /// One format, always true, never ambiguous about whether "now" means now.
    /// The count is written with plain interpolation: the numeric convenience
    /// call is matched by the date-handling guard and fails the build.
    static func line(for summary: FacilitySummary?) -> String {
        guard let summary else { return "Nothing free today" }

        return "\(summary.freeCourts) free at \(summary.slot.displayString)"
    }
}

/// The sparse hour ruler that sits above the rows in the dense tier.
nonisolated enum HourRuler {

    /// Roughly how much room "12:00 PM" needs at a given text size.
    ///
    /// Approximate on purpose. It is used only to decide how many labels the app
    /// draws, and the app deciding that for itself is what keeps them from
    /// colliding or truncating — which is UI-05 for the ruler.
    static func labelWidth(at size: DynamicTypeSize) -> Double {
        let base = 48.0

        switch size {
        case .xSmall, .small, .medium: return base * 0.9
        case .large: return base
        case .xLarge: return base * 1.1
        case .xxLarge: return base * 1.25
        case .xxxLarge: return base * 1.4
        default: return base * 1.8
        }
    }

    /// Label every nth hour, where n is whatever it takes for a label to fit in
    /// the room n cells actually give it.
    ///
    /// Computed rather than hardcoded, so raising the text size thins the labels
    /// out instead of overlapping them. At default sizes on a phone showing the
    /// whole day this comes out at every third hour.
    static func labelStride(cellWidth: Double, dynamicTypeSize: DynamicTypeSize) -> Int {
        guard cellWidth > 0 else { return 1 }

        let needed = labelWidth(at: dynamicTypeSize)
        return max(1, Int((needed / cellWidth).rounded(.up)))
    }

    /// One entry per slot: the hour to draw there, or nothing.
    ///
    /// The first column is always labelled whatever the stride. Past slots are
    /// gone, so the leading cell is always now-or-next, and saying so is the
    /// cheapest orientation cue on the screen.
    static func labels(
        for slots: [SlotTime], cellWidth: Double, dynamicTypeSize: DynamicTypeSize
    ) -> [String?] {
        let stride = labelStride(cellWidth: cellWidth, dynamicTypeSize: dynamicTypeSize)

        return slots.enumerated().map { index, slot in
            index % stride == 0 ? slot.displayString : nil
        }
    }
}

struct FacilityAvailabilitySection: View {

    let facility: Facility
    let day: VisibleDay

    /// Resolved once for the whole screen and handed down, never resolved here.
    ///
    /// Resolving per section would let two facilities disagree about tier, and
    /// the shared column grid — which is what lets every court on screen line up
    /// without any scroll synchronisation — would break between sections.
    let layout: StripLayout

    /// What one cell actually got, for the ruler's spacing arithmetic.
    let cellWidth: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            if layout == .dense {
                ruler
            }

            ForEach(facility.courts) { court in
                AvailabilityStrip(
                    court: court,
                    slots: day.slots,
                    statuses: day.statuses(for: court),
                    layout: layout
                )
            }
        } header: {
            header
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(facility.name)
                .font(.headline)
                .textCase(nil)

            Text(AvailabilitySummaryText.line(for: day.summary(for: facility)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .accessibilityElement(children: .combine)
    }

    /// Drawn only in the dense tier.
    ///
    /// From the glyph tier upward a cell can carry its own hour, and in the
    /// labelled tier it definitely does, so a ruler there would be duplicate ink
    /// saying what every cell already says.
    private var ruler: some View {
        HStack(spacing: StripLayout.defaultSpacing) {
            Text("Now")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: StripLayout.defaultLabelWidth, alignment: .leading)

            ForEach(Array(rulerLabels.enumerated()), id: \.offset) { index, label in
                Text(label ?? "")
                    .font(.caption2)
                    .foregroundStyle(index == 0 ? .primary : .secondary)
                    .fontWeight(index == 0 ? .semibold : .regular)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The ruler repeats what every cell already announces individually, so
        // reading it aloud as well would double the length of the screen for a
        // VoiceOver user without adding anything.
        .accessibilityHidden(true)
    }

    private var rulerLabels: [String?] {
        HourRuler.labels(
            for: day.slots, cellWidth: cellWidth, dynamicTypeSize: dynamicTypeSize)
    }
}
