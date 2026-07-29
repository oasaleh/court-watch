//
//  AvailabilityStrip.swift
//  CourtWatch
//
//  One court's remaining day, as a row of hours that runs off the edge.
//
//  The row used to be required to fit. Sixteen segments across roughly 275
//  points of an iPhone is about 17 points each, which is an illegible button and
//  an ordinary chart bar — and the whole design followed from that number: a
//  cell too narrow to write in had to encode its state as ink density, and the
//  hour it stood for had to be printed on a ruler above the rows because no cell
//  could say it.
//
//  It scrolls now, so none of that constraint applies. A cell is given the width
//  it needs rather than a sixteenth of the screen, which means it can write its
//  own hour, which is what let the ruler go. What the row gives up is the whole
//  day at a glance; what pays for that is the facility header, which already
//  answers "what's open here?" in a sentence before any cell is read.
//
//  This file holds no opinion about what a status means. It asks
//  `SlotAppearance` and draws the answer. A status check here would be a second
//  opinion that could disagree with the spoken label, which is exactly the
//  failure a single mapping exists to prevent — so the appearance, and only the
//  appearance, decides.
//
//  It holds no opinion about colour either. Every hex lives in
//  `SlotPalette.swift`, declared once for light mode and once for dark. To
//  change a shade, edit it there — not here.
//

import SwiftUI

/// One court's open-hour count, as text.
///
/// Its own type, and tested, for the reason the ambiguity it fixes survived
/// this long: it used to be a private computed property on a view, so no test
/// could see it, and the only place it is ever drawn is the largest
/// accessibility text sizes — a screen nobody looks at until they go looking.
nonisolated enum OpenHoursText {

    /// "7 of 16 hours free", or "Nothing free".
    ///
    /// The unit is named, and that is the whole point of the function. This
    /// line is drawn directly beneath the facility's own, which counts *courts*
    /// in the identical shape — "11 of 11 free" over "7 of 16 free", one about
    /// places and one about times, with nothing on screen to say they had
    /// changed subject. Saying "hours" costs a word and removes the collision.
    ///
    /// Both numbers are written with plain interpolation: the numeric
    /// convenience call is matched by the date-handling guard and fails the
    /// build.
    static func line(open: Int, total: Int) -> String {
        guard open > 0 else { return "Nothing free" }

        return "\(open) of \(total) hours free"
    }
}

struct AvailabilityStrip: View {

    let court: Court
    let slots: [SlotTime]
    let statuses: [SlotStatus]
    let layout: StripLayout

    /// Grows with the user's text size rather than staying pinned, so the row
    /// gets taller before it is abandoned altogether at accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var cellHeight: CGFloat =
        StripLayout.defaultCellHeight

    /// The cell grows with the text inside it, which is new: the width used to
    /// be whatever sixteen cells could share, so it could not respond to type
    /// size at all. Now that the row scrolls, a larger text size makes wider
    /// cells and a longer row rather than smaller text in a fixed box.
    @ScaledMetric(relativeTo: .caption2) private var cellWidth: CGFloat =
        StripLayout.defaultCellWidth

    var body: some View {
        switch layout {
        case .list:
            openHoursList
        case .strip:
            strip
        }
    }

    // MARK: - The strip

    /// The hours, in order, each in a cell of its own.
    ///
    /// No court label at the leading edge any more — it is pinned outside the
    /// scroll view by `FacilityAvailabilitySection`, so that it stays put while
    /// these move. A label inside the scrolling content would slide away and
    /// leave a screen of unattributed rows.
    ///
    /// Walking the pairs rather than the slot indices: `VisibleDay` guarantees
    /// one status per visible slot, so this is the same sixteen cells — but it
    /// is the shape that *cannot* read past either array. Every cell goes
    /// through the appearance mapping and every cell is announced; there is no
    /// cell hidden from VoiceOver, which was a screen-reader user silently
    /// losing squares a sighted user could see were empty.
    private var strip: some View {
        HStack(spacing: StripLayout.defaultSpacing) {
            ForEach(Array(zip(slots, statuses).enumerated()), id: \.offset) { index, pair in
                SlotCell(
                    appearance: SlotAppearance.of(pair.1),
                    slot: pair.0,
                    label: SlotAppearance.label(court: court.name, slot: pair.0)
                )
                .frame(width: cellWidth, height: cellHeight)
            }
        }
    }

    // MARK: - The accessibility-size list

    /// At the largest text sizes the strip is abandoned rather than shrunk.
    ///
    /// Booked hours are omitted here on purpose. There is room for one answer at
    /// this size, and the question this app exists to answer is what is *open* —
    /// listing the closed hours as well would push the open ones off the screen
    /// to say something the user did not ask.
    private var openHoursList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(court.name)
                .font(.headline)

            Text(openCountLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if openSlots.isEmpty == false {
                Text(openSlots.map(\.displayString).joined(separator: ", "))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Plain interpolation, never the numeric convenience call: that call is
    /// matched by the date-handling guard and fails the build.
    private var openCountLine: String {
        OpenHoursText.line(open: openSlots.count, total: slots.count)
    }

    /// The hours this court is free.
    ///
    /// Derived by asking the single status-to-appearance mapping whether a cell
    /// looks like an available one, rather than by re-deciding here what
    /// "available" means. That keeps this list, the drawn cells and the spoken
    /// labels all downstream of one answer — and it stays correct if the domain
    /// ever grows a fourth state, which would map to its own appearance rather
    /// than quietly matching this comparison.
    private var openSlots: [SlotTime] {
        let free = SlotAppearance.of(.available)

        return zip(slots, statuses)
            .filter { SlotAppearance.of($0.1) == free }
            .map(\.0)
    }
}

// MARK: - One cell

private struct SlotCell: View {

    let appearance: SlotAppearance
    let slot: SlotTime
    let label: String

    /// The user has asked not to be made to rely on colour. Meaning moves from
    /// the block's colour back to ink density, and the symbols come back with it.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @Environment(\.colorScheme) private var colorScheme

    /// The user has asked for stronger contrast. It moves the text rather than
    /// the block: the background is what gives a state its identity at a glance,
    /// so shifting it would change what the grid looks like instead of how
    /// legible it is.
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            shape
            mark
        }
        // One element per cell, or VoiceOver reads a grid as a flood of
        // context-free state words. The label restores the row and column a
        // sighted user reads off the axes; the state goes in the value slot so
        // the announcement comes out as label-then-value naturally.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(appearance.spokenState)
    }

    @ViewBuilder
    private var shape: some View {
        let rectangle = RoundedRectangle(
            cornerRadius: StripLayout.defaultCornerRadius, style: .continuous)

        if differentiateWithoutColor {
            // Colour has been declined, so meaning goes back to ink density:
            // solid, empty and hatched are three different amounts of ink and
            // stay distinct with every hue removed.
            //
            // Drawn in the saturated end of the palette's pair rather than the
            // block colour. The block colour is a quiet fill and would all but
            // vanish as a hairline, and in this path the shape *is* the meaning.
            switch appearance.fill {
            case .filled:
                rectangle.fill(shapeTint)

            case .outline:
                rectangle.strokeBorder(shapeTint, lineWidth: 2)

            case .hatched:
                rectangle
                    .fill(shapeTint.opacity(0.12))
                    .overlay {
                        DiagonalHatch()
                            .stroke(shapeTint, lineWidth: 1.5)
                            .clipShape(rectangle)
                    }
                    .overlay { rectangle.strokeBorder(shapeTint, lineWidth: 2) }
            }
        } else {
            rectangle.fill(SlotPalette.background(for: appearance.fill, scheme: colorScheme))
        }
    }

    /// The hour, written inside the block.
    ///
    /// Every cell carries it now. That is what replaced the ruler: a sparse
    /// strip of hours above the rows, labelled every third column because that
    /// was all that fit, leaving two cells in three that the user had to count
    /// across to place. A cell wide enough to say its own hour does not need
    /// counting.
    ///
    /// The symbol comes back only when colour has been declined, where it is the
    /// thing doing the work rather than decoration.
    private var mark: some View {
        HStack(spacing: 1) {
            if differentiateWithoutColor {
                Image(systemName: appearance.symbolName)
                    .font(.system(size: 8, weight: .bold))
            }

            Text(slot.displayString)
                .font(.caption2.weight(StripLayout.captionWeight))
                .lineLimit(1)
                .minimumScaleFactor(StripLayout.minimumTextScale)
        }
        .foregroundStyle(markTint)
        .padding(.horizontal, StripLayout.defaultCellPadding)
    }

    /// What the shape is drawn with once colour has been declined.
    private var shapeTint: Color {
        SlotPalette.differentiatedShape(
            for: appearance.fill, scheme: colorScheme, contrast: contrast)
    }

    /// Drawn on top of a cell, so it has to contrast with whatever that cell
    /// drew — and the two paths draw very different things, so each gets its own
    /// answer from the palette.
    private var markTint: Color {
        differentiateWithoutColor
            ? SlotPalette.differentiatedInk(
                for: appearance.fill, scheme: colorScheme, contrast: contrast)
            : SlotPalette.foreground(
                for: appearance.fill, scheme: colorScheme, contrast: contrast)
    }
}

/// Diagonal stripes, so the unrecognised state has a *texture* rather than
/// merely another shade. A shade is a third point on the same scale and can be
/// mistaken for either neighbour at a glance; a texture cannot.
private struct DiagonalHatch: Shape {

    var spacing: CGFloat = 3

    /// Explicitly `nonisolated`: this module defaults to main-actor isolation
    /// and the protocol requirement is not.
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height

        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }

        return path
    }
}
