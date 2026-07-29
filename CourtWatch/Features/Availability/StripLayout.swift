//
//  StripLayout.swift
//  CourtWatch
//
//  Whether a court's day is drawn as a strip at all.
//
//  This file used to answer a harder question. The grid was required to fit
//  sixteen hours across whatever width it was given without scrolling, so a
//  cell's width was whatever sixteen of them could share — about seventeen
//  points on a phone — and the layout decided how much a cell could *say* at
//  that size: a bare block, a block with a glyph, or a block with the hour
//  written inside it. Three tiers, resolved from measured width.
//
//  The strip scrolls horizontally now, so a cell is no longer allotted a share
//  of the screen: it is given the width it needs and the row runs off the edge.
//  Every cell can therefore carry its own hour, which is what removed the hour
//  ruler, and with it the entire reason the tiers existed. What is left is the
//  one decision width could never answer.
//
//  At the largest accessibility text sizes the strip is abandoned rather than
//  shrunk. That is reached by text size, not by width, and it is the whole of
//  UI-05 that survives: a sixteen-column strip at accessibility3 is unreadable
//  at any cell width, and a layout that shrinks to fit there is technically
//  responsive and useless.
//
//  Nothing here renders anything, which is the point of the seam: the decision
//  is answerable without drawing a pixel.
//

import SwiftUI

/// Whether the day is drawn as a scrolling strip or as a list of open hours.
///
/// `Comparable` so "the list says more than the strip" stays assertable, and
/// ordered with `list` last for the same reason it was before: it is the most a
/// cell can say, not the widest.
nonisolated enum StripLayout: Hashable, Sendable, Comparable {

    /// A horizontally scrolling row of blocks, each carrying its own hour.
    case strip

    /// The strip is abandoned entirely and open hours are listed as full-size
    /// wrapped text.
    case list
}

extension StripLayout {

    /// The court-number column at the leading edge of every row.
    ///
    /// Pinned outside the scroll view now rather than being the first thing in
    /// the row, so it stays on screen while the hours move under it. A default
    /// rather than a constant reached for from a drawing file, so a test can
    /// state the geometry it is asserting instead of inheriting it.
    static let defaultLabelWidth: Double = 40

    /// The gap between two cells.
    ///
    /// Wider than it was. It used to be 3 points because at sixteen cells
    /// sharing one screen every point between them was a point taken off all of
    /// them; nothing is being shared now, so the gap can be what actually reads
    /// as a gap.
    static let defaultSpacing: Double = 6

    /// What one cell gets, in points, before Dynamic Type scaling.
    ///
    /// Sized to carry the longest hour this app draws. `SlotTime.displayString`
    /// renders a whole hour as "12 PM" and anything else as "12:30 PM", and the
    /// captured data is hourly — but the wider form is what the type can
    /// produce, so it is what the cell is sized for. A cell that fits the common
    /// case and truncates the other is a cell that silently drops a colon on the
    /// one day a facility publishes half-hours.
    static let defaultCellWidth: Double = 72

    /// The text size at which no cell width rescues a sixteen-column strip.
    static let listThreshold: DynamicTypeSize = .accessibility3

    /// How wide a court's whole day is, laid end to end.
    ///
    /// Not used to decide anything — the row scrolls, so it can be any width at
    /// all. It exists so a test can state what the scroll content comes to, and
    /// so the pinned column's arithmetic has something to be checked against.
    static func contentWidth(
        slotCount: Int,
        cellWidth: Double = defaultCellWidth,
        spacing: Double = defaultSpacing
    ) -> Double {
        guard slotCount > 0 else { return 0 }

        return Double(slotCount) * cellWidth + Double(slotCount - 1) * spacing
    }

    /// Whether the day fits without the user having to scroll.
    ///
    /// The strip scrolls when it has to, and often will; this says when it does
    /// not have to. It is what lets a test state the thing the old design
    /// promised outright — a short evening still fits on one screen — rather
    /// than leaving it to be noticed.
    static func fitsWithoutScrolling(
        availableWidth: Double,
        slotCount: Int,
        labelWidth: Double = defaultLabelWidth,
        cellWidth: Double = defaultCellWidth,
        spacing: Double = defaultSpacing
    ) -> Bool {
        let content = contentWidth(
            slotCount: slotCount, cellWidth: cellWidth, spacing: spacing)

        return content <= availableWidth - labelWidth - spacing
    }

    /// The layout to draw.
    ///
    /// Width is not a parameter any more, and its absence is the change: no
    /// measurement of the screen can make a sixteen-column strip readable at
    /// accessibility3, and no measurement is needed to draw one below that.
    static func resolve(dynamicTypeSize: DynamicTypeSize) -> StripLayout {
        dynamicTypeSize >= listThreshold ? .list : .strip
    }
}
