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

/// Everything below is `nonisolated` for the same reason the type is: this
/// module defaults to main-actor isolation, and an extension does not inherit
/// the annotation from the type it extends. Without it the *default parameter
/// values* — `= defaultCellWidth`, `= defaultSpacing` — are main-actor
/// expressions, and any `nonisolated` caller that omits an argument fails to
/// compile. Test argument lists are exactly that caller.
nonisolated extension StripLayout {

    // MARK: - Cell geometry
    //
    // Taken from a calendar's event chips rather than invented. Measured off the
    // reference at 91 × 74 with a 7-point horizontal gap, an 8-point vertical
    // one, and a corner radius of about 5 — in that screenshot's pixels, which
    // are 2× device points. So the numbers below are those measurements halved,
    // and the aspect ratio, gap fraction and radius fraction all carry over
    // unchanged.
    //
    // The width is no longer set by the text. It used to be: at 72 points a cell
    // could hold "12:30 PM" outright. At 43 it holds a whole hour — which is
    // what this endpoint publishes and every captured payload contains — and
    // scales a half-hour down to fit. `cellFitsAWholeHour` pins the first and
    // `cellFitsAHalfHourWhenScaled` the second, so the relationship between the
    // width, the font, the padding and the scale floor is checked rather than
    // assumed to still hold.

    /// The court-number column at the leading edge of every row.
    ///
    /// Pinned outside the scroll view now rather than being the first thing in
    /// the row, so it stays on screen while the hours move under it. Narrower
    /// than it was: a 40-point column beside a 43-point cell read as a second
    /// column of content rather than as a label.
    static let defaultLabelWidth: Double = 24

    /// The gap between two cells, in both directions.
    ///
    /// The reference's 7 and 8 pixels at 2×, which come to 3.5 and 4.
    static let defaultSpacing: Double = 4

    /// What one cell gets, in points, before Dynamic Type scaling.
    static let defaultCellWidth: Double = 43

    /// How tall a cell is, before Dynamic Type scaling.
    ///
    /// Shared with `FacilityAvailabilitySection`, which sizes the pinned court
    /// numbers to match. They were two independent numbers that had to agree,
    /// which is the sort of pair that silently stops agreeing.
    static let defaultCellHeight: Double = 35

    /// The corner radius of a cell: the reference's 5 pixels at 2×.
    static let defaultCornerRadius: Double = 3

    /// The breathing room either side of the hour inside a cell.
    ///
    /// Named because it is load-bearing at this width: it is the difference
    /// between the cell and the space the text actually gets, and the tests
    /// measure against that space rather than the cell.
    static let defaultCellPadding: Double = 2

    /// How far the hour may shrink before it would rather truncate.
    ///
    /// Matches the `minimumScaleFactor` the cell applies. Named so a test can
    /// ask whether the longest string the app can print still fits at the floor,
    /// which is the question the width is chosen to answer.
    static let minimumTextScale: Double = 0.7

    /// The point size `.caption2` resolves to at the default text size.
    ///
    /// Written down so the fit can be measured. Dynamic Type moves it, and the
    /// cell scales with it — the check below is that the two are in proportion
    /// at the size everything is designed around.
    static let captionPointSize: Double = 11

    /// The weight the hour is drawn at.
    ///
    /// Regular, after the reference: a calendar chip sets the event's *name*
    /// in semibold and its *time* in regular, and the hour in this grid is the
    /// time rather than the title. It was semibold, which at 11 points on a
    /// saturated block read as heavier than anything else on the screen.
    ///
    /// Named rather than left in the view because the fit tests measure with it.
    /// A weight is a width: changing this changes whether the hour fits, and the
    /// two would otherwise be separate decisions that had to agree.
    static let captionWeight: Font.Weight = .regular

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
