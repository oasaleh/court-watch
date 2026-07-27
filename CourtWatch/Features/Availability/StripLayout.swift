//
//  StripLayout.swift
//  CourtWatch
//
//  How much a cell is allowed to say, decided from the width it actually got.
//
//  This is the load-bearing decision of the phase, because it turns UI-05 and
//  UI-08 — the two most subjective requirements here — into a function with a
//  return value. "Does it look right on iPad" becomes "does resolving 1032
//  points across 16 slots return the labelled tier", which is answerable on
//  every commit rather than at review time.
//
//  Nothing here renders anything, and that is the point of the seam: the layout
//  decision is answerable without drawing a pixel.
//
//  On the two widths this is asserted against. 402 and 1032 are the measured
//  point sizes of an iPhone 17 Pro and an iPad Pro 13-inch (M5). At run time the
//  caller passes the width its container actually measured, which inside a list
//  row is smaller — roughly 330 on that phone and 960 on that iPad. Both land on
//  the same tier, which is what makes the assertion meaningful rather than a
//  restatement of the constants: 402 gives ≈22 point cells at 16 slots and 330
//  gives ≈17, and both are comfortably inside the dense band.
//

import SwiftUI

/// What a cell draws, in increasing order of how much it says.
///
/// `Comparable` so that D4's claim — the iPad tier at 16 slots is strictly
/// richer than the iPhone's — can be asserted as a comparison rather than as
/// two hardcoded expectations that could both be updated to agree with a bug.
nonisolated enum StripLayout: Hashable, Sendable, Comparable {

    /// A block and nothing else. Too narrow for a glyph, so a sparse hour ruler
    /// sits above the rows instead. This is D2 working as intended rather than
    /// a missing feature: at ≈17 points a cell cannot carry a mark, and ink
    /// density is exactly the encoding that does not need one.
    case dense

    /// Block plus a glyph — but only when the user has declined colour. With
    /// colour carrying the state a cell at this width draws as a bare block, so
    /// it needs the hour ruler just as much as the dense tier does.
    case glyph

    /// Block, symbol, and the hour written inside the cell. No ruler needed —
    /// every cell says its own time.
    case labeled

    /// The strip is abandoned entirely and open hours are listed as full-size
    /// wrapped text.
    ///
    /// Ordered last because it is the most a cell can say, not because it is
    /// the widest. It is reached by text size rather than by width.
    case list
}

extension StripLayout {

    /// Whether the rows need an hour ruler above them.
    ///
    /// True whenever a cell cannot say its own time. Only the labelled tier
    /// writes the hour inside the cell; `dense` never could, and `glyph` stopped
    /// being able to when the symbols were dropped in favour of colour. A tier
    /// that draws a bare block and gets no ruler leaves a screen of coloured
    /// squares with nothing anywhere saying which hour is which.
    var needsHourRuler: Bool {
        switch self {
        case .dense, .glyph: true
        case .labeled, .list: false
        }
    }
}

extension StripLayout {

    /// The court-number column at the leading edge of every row.
    ///
    /// A default rather than a constant reached for from a drawing file, so a
    /// test can state the geometry it is asserting instead of inheriting it.
    static let defaultLabelWidth: Double = 40

    /// The gap between two cells. Small on purpose: at 16 slots every point
    /// spent between cells is a point taken off all of them.
    static let defaultSpacing: Double = 3

    /// Below this a cell cannot carry a glyph legibly.
    static let glyphThreshold: Double = 32

    /// At or above this a cell can carry the hour as text.
    ///
    /// It coincides with Apple's 44-point minimum by arithmetic rather than by
    /// rule: nothing in this grid is tappable, so the hit-target minimum does
    /// not bind here. 44 points is simply about where an hour fits.
    static let labelThreshold: Double = 44

    /// The text size at which no cell width rescues a sixteen-column strip.
    static let listThreshold: DynamicTypeSize = .accessibility3

    /// What one cell would get, in points.
    ///
    /// Never negative, so a container narrower than its own furniture reports
    /// zero rather than a nonsense figure that would resolve to a rich tier.
    static func cellWidth(
        availableWidth: Double,
        slotCount: Int,
        labelWidth: Double = defaultLabelWidth,
        spacing: Double = defaultSpacing
    ) -> Double {
        guard slotCount > 0 else { return 0 }

        let gaps = spacing * Double(slotCount - 1)
        return max(0, (availableWidth - labelWidth - gaps) / Double(slotCount))
    }

    /// The tier to draw.
    static func resolve(
        availableWidth: Double,
        slotCount: Int,
        dynamicTypeSize: DynamicTypeSize,
        labelWidth: Double = defaultLabelWidth,
        spacing: Double = defaultSpacing
    ) -> StripLayout {

        // Checked before the arithmetic, and that ordering is UI-05 itself. At
        // the largest text sizes there is no cell width that rescues a
        // sixteen-column strip, so the strip is abandoned rather than shrunk.
        // Getting this backwards produces a layout that is technically
        // responsive and completely unreadable.
        if dynamicTypeSize >= listThreshold { return .list }

        // Reachable, and exactly TIME-07's finished day. The caller will not
        // draw a strip then, but a layout function that traps on an empty day
        // is a crash waiting for the first user who opens the app at eleven at
        // night. The value is inert — there are no cells to draw.
        guard slotCount > 0 else { return .dense }

        let width = cellWidth(
            availableWidth: availableWidth,
            slotCount: slotCount,
            labelWidth: labelWidth,
            spacing: spacing
        )

        if width >= labelThreshold { return .labeled }
        if width >= glyphThreshold { return .glyph }
        return .dense
    }
}
