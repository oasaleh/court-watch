//
//  FacilityAvailabilitySection.swift
//  CourtWatch
//
//  One place: what is open here, and every court's remaining day beneath it.
//
//  The header's summary line is the point of this file, and it matters more than
//  it used to. The grid no longer shows the whole day at once — the hours scroll
//  — so the one thing that answers "what's open here?" without any interaction
//  is this sentence. It was always the fastest path to the answer; it is now the
//  only one that does not require a gesture.
//
//  The scrolling is arranged once, here, rather than per court. Every court in a
//  facility lives inside a single horizontal scroll view, so the rows move
//  together and stay aligned: 9 AM is directly under 9 AM on every court in the
//  place. A scroll view per row would let them drift apart, and a column of
//  hours that do not line up is worse than no alignment at all, because it still
//  looks like a grid.
//
//  The court numbers are pinned outside that scroll view for the same reason.
//  They are the row's identity, and identity that scrolls away leaves a screen
//  of anonymous coloured rows.
//
//  The summary line is a pure function rather than string interpolation buried
//  in a drawn body, and that is not a style preference: a time string is covered
//  by the twelve-hour gate if and only if some test asserts it, and no test
//  observes a rendered screen. Producing it here, in a function a test can call,
//  is what puts it under `Scripts/test-24h.sh`.
//

import SwiftUI

/// The one derived sentence per facility, as text.
nonisolated enum AvailabilitySummaryText {

    /// "2 of 5 free", "Next free at 10 PM · 2 of 5", or "Nothing free today".
    ///
    /// Three sentences rather than one, because one cannot be read. The old
    /// single form named the time unconditionally — "2 of 5 free at 10 PM" —
    /// and a user who had just asked to see 7 PM onwards read that as the
    /// filter having been ignored. It had not been: 7, 8 and 9 PM were booked
    /// and 10 PM was genuinely the next hour anything opened up. The line was
    /// true and still gave the wrong impression, which is the same cost as
    /// being wrong.
    ///
    /// So the time is named if and only if it is *not* the hour on screen. When
    /// the facility is free at the leading hour the count stands alone and is
    /// about that hour, the one the toolbar names and the strip puts first; when
    /// it is not, the line leads with the hour it actually is free, which is the
    /// fact the user is missing.
    ///
    /// The total is named alongside the count because the count alone cannot be
    /// read either: two free at a two-court place is a quiet evening, two free
    /// at Bear Branch's eleven is a busy one.
    ///
    /// Both numbers are written with plain interpolation: the numeric
    /// convenience call is matched by the date-handling guard and fails the
    /// build.
    static func line(for summary: FacilitySummary?) -> String {
        guard let summary else { return "Nothing free today" }

        let count = "\(summary.freeCourts) of \(summary.totalCourts)"

        guard summary.startsLater else { return "\(count) free" }

        return "Next free at \(summary.slot.displayString) · \(count)"
    }
}

struct FacilityAvailabilitySection: View {

    let facility: Facility
    let day: VisibleDay

    /// Resolved once for the whole screen and handed down, never resolved here.
    ///
    /// It now turns only on text size, so two sections could not disagree in
    /// practice — but it is still passed rather than read, because a view that
    /// reads its own layout is a view that can be given one it ignores.
    let layout: StripLayout

    /// Matches the strip's own cell height so the pinned numbers line up with
    /// the rows they name. Both read the same constant rather than each holding
    /// a number that has to agree with the other's.
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat =
        StripLayout.defaultCellHeight

    /// How much of each edge is currently faded out.
    ///
    /// Driven by the scroll position rather than fixed, because a fade that is
    /// always on dims the first hour of a row nobody has scrolled and the last
    /// hour of a row that fits. See `EdgeFade`.
    @State private var fade: EdgeFade = .none

    var body: some View {
        Section {
            switch layout {
            case .list:
                // No strip to scroll, so no column to pin. Each court draws its
                // own full-width block of text.
                ForEach(facility.courts) { court in
                    strip(for: court)
                }

            case .strip:
                scrollingCourts
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

    /// Every court in the place, as one row of the list.
    ///
    /// One row rather than one per court, and that is what makes the shared
    /// scroll possible: the pinned column and the scrolling hours have to be
    /// siblings in a single `HStack` for the courts to move together, and a list
    /// row per court would put each pair in a separate container with a separate
    /// scroll offset.
    ///
    /// The trade is that the separator between courts goes, since the list now
    /// sees one row where it used to see eleven. The rows are already told apart
    /// by their blocks and their pinned numbers, and a rule between them would
    /// be drawn across the scrolling content or not at all.
    private var scrollingCourts: some View {
        HStack(alignment: .top, spacing: StripLayout.defaultSpacing) {
            courtNumbers

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: StripLayout.defaultSpacing) {
                    ForEach(facility.courts) { court in
                        strip(for: court)
                    }
                }
            }
            // The edges fade rather than cutting. Applied to the scroll view
            // alone, so the pinned court numbers beside it stay at full
            // strength — they are not the thing that continues off-screen.
            .mask(fadeMask)
            .onScrollGeometryChange(for: EdgeFade.self) { geometry in
                EdgeFade.resolve(
                    offset: geometry.contentOffset.x,
                    contentWidth: geometry.contentSize.width,
                    containerWidth: geometry.containerSize.width
                )
            } action: { _, updated in
                fade = updated
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
        .listRowSeparator(.hidden)
    }

    /// Opaque through the middle, falling away at whichever edge has more of the
    /// day behind it.
    ///
    /// The stops are built from the fade rather than fixed, so an edge with
    /// nothing past it stays fully opaque and costs nothing: at `leading == 0`
    /// the first stop is solid and the gradient is flat across the whole row.
    private var fadeMask: some View {
        let band = fade.bandFraction

        return LinearGradient(
            stops: [
                .init(color: .black.opacity(1 - fade.leading), location: 0),
                .init(color: .black, location: band),
                .init(color: .black, location: 1 - band),
                .init(color: .black.opacity(1 - fade.trailing), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// The pinned leading column: one number per court, aligned to its row.
    ///
    /// Hidden from VoiceOver because every cell already announces its own court
    /// by name. Reading the column as well would put a bare number between each
    /// court's hours and the next.
    private var courtNumbers: some View {
        VStack(alignment: .leading, spacing: StripLayout.defaultSpacing) {
            ForEach(facility.courts) { court in
                Text(courtLabel(for: court))
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(
                        width: StripLayout.defaultLabelWidth,
                        height: rowHeight,
                        alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private func strip(for court: Court) -> some View {
        AvailabilityStrip(
            court: court,
            slots: day.slots,
            statuses: day.statuses(for: court),
            layout: layout
        )
    }

    /// Just the number, not the whole name.
    ///
    /// The facility name is the section header directly above, so repeating it
    /// on all eleven rows would spend the width this column is trying to keep
    /// small. A court with no trailing number keeps its full name, because those
    /// exist and a blank label would be worse than a wide one.
    private func courtLabel(for court: Court) -> String {
        CourtNumber.parse(from: court.name).map { "\($0)" } ?? court.name
    }
}
