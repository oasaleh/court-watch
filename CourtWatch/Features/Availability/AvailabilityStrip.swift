//
//  AvailabilityStrip.swift
//  CourtWatch
//
//  One court, its whole remaining day, in a row that always fits the screen.
//
//  Sixteen segments across roughly 275 points of an iPhone is about 17 points
//  each. That is an illegible button and an ordinary chart bar, and the
//  difference is the whole design: nothing in this grid is tappable, so Apple's
//  44-point minimum — a *hit target* rule — does not bind here. The governing
//  constraint is legibility, and a 17-point bar is legible when what it encodes
//  is how much ink it has rather than what is written inside it.
//
//  This file holds no opinion about what a status means. It asks
//  `SlotAppearance` and draws the answer. A status check here would be a second
//  opinion that could disagree with the spoken label, which is exactly the
//  failure a single mapping exists to prevent — so the appearance, and only the
//  appearance, decides.
//

import SwiftUI

struct AvailabilityStrip: View {

    let court: Court
    let slots: [SlotTime]
    let statuses: [SlotStatus]
    let layout: StripLayout

    /// Grows with the user's text size rather than staying pinned, so the strip
    /// gets taller before it is abandoned altogether at accessibility sizes.
    @ScaledMetric(relativeTo: .caption) private var cellHeight: CGFloat = 22

    var body: some View {
        switch layout {
        case .list:
            openHoursList
        case .dense, .glyph, .labeled:
            strip
        }
    }

    // MARK: - The strip

    private var strip: some View {
        HStack(spacing: StripLayout.defaultSpacing) {
            Text(courtLabel)
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: StripLayout.defaultLabelWidth, alignment: .leading)
                .accessibilityLabel(court.name)

            // Each cell takes an equal share of whatever width is actually
            // there, so rounding cannot accumulate across sixteen of them and
            // the row can never come out wider than its container. The tier
            // decides only what a cell *draws* — never what frame it gets.
            // Conflating those two jobs is how a strip ends up one pixel wide
            // of the screen it is supposed to fit.
            //
            // Walking the pairs rather than the slot indices: `VisibleDay`
            // guarantees one status per visible slot, so this is the same
            // sixteen cells — but it is the shape that *cannot* read past
            // either array, which is what lets the placeholder branch go. Every
            // cell now goes through the appearance mapping and every cell is
            // announced. There is no longer a cell hidden from VoiceOver, which
            // was a screen-reader user silently losing squares a sighted user
            // could see were empty.
            ForEach(Array(zip(slots, statuses).enumerated()), id: \.offset) { index, pair in
                SlotCell(
                    appearance: SlotAppearance.of(pair.1),
                    layout: layout,
                    slot: pair.0,
                    label: SlotAppearance.label(court: court.name, slot: pair.0)
                )
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
            }
        }
    }

    /// Just the number, not the whole name.
    ///
    /// The facility name is the section header directly above, so repeating it
    /// in all eleven rows would spend exactly the width that makes the strip fit
    /// at all — this column is what buys the cells their 17 points. A court with
    /// no trailing number keeps its full name, because those exist and a blank
    /// label would be worse than a wide one.
    private var courtLabel: String {
        CourtNumber.parse(from: court.name).map { "\($0)" } ?? court.name
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
        openSlots.isEmpty
            ? "Nothing free"
            : "\(openSlots.count) of \(slots.count) free"
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
    let layout: StripLayout
    let slot: SlotTime
    let label: String

    /// The user has asked not to be made to rely on colour. Meaning moves from
    /// hue back to ink density, and the symbols come back with it.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

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
        let rectangle = RoundedRectangle(cornerRadius: 2, style: .continuous)

        if differentiateWithoutColor {
            // Colour has been declined, so meaning goes back to ink density:
            // solid, empty and hatched are three different amounts of ink and
            // stay distinct with every hue removed.
            switch appearance.fill {
            case .filled:
                rectangle.fill(tint)

            case .outline:
                rectangle.strokeBorder(tint, lineWidth: 2)

            case .hatched:
                rectangle
                    .fill(tint.opacity(0.12))
                    .overlay {
                        DiagonalHatch()
                            .stroke(tint, lineWidth: 1.5)
                            .clipShape(rectangle)
                    }
                    .overlay { rectangle.strokeBorder(tint, lineWidth: 2) }
            }
        } else {
            // Every state is a solid block and hue tells them apart. Chosen
            // deliberately: at a glance a row of blocks reads as a bar chart,
            // and an outline for booked read as "faint" rather than "taken".
            rectangle.fill(tint)
        }
    }

    /// The hour, and nothing else.
    ///
    /// No symbol: once colour carries the state, a tick on every free cell is
    /// ink spent repeating what the block already says, and it steals the height
    /// that makes the hour legible. The symbol comes back only when colour has
    /// been declined, where it is the thing doing the work rather than decoration.
    @ViewBuilder
    private var mark: some View {
        switch layout {
        case .dense, .list:
            EmptyView()

        case .glyph:
            if differentiateWithoutColor {
                Image(systemName: appearance.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(markTint)
            }

        case .labeled:
            VStack(spacing: 1) {
                if differentiateWithoutColor {
                    Image(systemName: appearance.symbolName)
                        .font(.caption2.bold())
                }

                Text(slot.displayString)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(markTint)
            .padding(.horizontal, 2)
        }
    }

    /// Green is free, red is taken, orange is unknown.
    ///
    /// Hue is the primary channel here by explicit choice, which is why the
    /// density treatment above is kept and reinstated the moment the system
    /// reports that colour should not be relied on.
    private var tint: Color {
        switch appearance.fill {
        case .filled: .green
        case .outline: .red
        case .hatched: .orange
        }
    }

    /// Drawn on top of a block, so it has to contrast with it. Only the outline
    /// and hatched treatments leave the background showing, and those exist
    /// solely in the differentiate-without-colour path.
    private var markTint: Color {
        guard differentiateWithoutColor, appearance.fill != .filled else { return .white }
        return tint
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
