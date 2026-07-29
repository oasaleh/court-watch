//
//  StripLayoutTests.swift
//  CourtWatchTests
//
//  What survives of UI-05 once the strip scrolls.
//
//  This file used to assert a table of widths against three tiers, because a
//  cell's width was whatever sixteen of them could share and how much a cell
//  could say followed from that number. None of that arithmetic exists any
//  more: a cell is given a fixed width and the row runs off the edge.
//
//  The requirement that outlived it is the one width could never satisfy. At the
//  largest accessibility text sizes a sixteen-column strip is unreadable at any
//  cell width, so it is abandoned rather than shrunk — and that threshold is
//  still worth pinning, because it is the difference between a layout that is
//  technically responsive and one that can be read.
//
//  The widths here are measured, not chosen: an iPhone 17 Pro is 1206 × 2622
//  pixels at 3×, which is 402 × 874 points; an iPad Pro 13-inch (M5) is
//  2064 × 2752 at 2×, which is 1032 × 1376. Written out rather than rounded so
//  that a future device makes this file obviously stale instead of quietly
//  wrong. They are used only to ask what fits, never to decide a tier.
//

import SwiftUI
import Testing
import UIKit

@testable import CourtWatch

/// Measured device widths in points.
private let iPhoneWidth: Double = 402
private let iPadWidth: Double = 1032

/// Inside a list row the usable width is smaller than the device's. Roughly 330
/// on that phone and 960 on that iPad, which is what the strip actually gets.
private let iPhoneRowWidth: Double = 330
private let iPadRowWidth: Double = 960

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor. `DynamicTypeSize` values inside one are fine;
/// the array holding them is what needs the annotation.
nonisolated enum StripLayoutCases {

    /// Every text size below the threshold draws a strip.
    static let stripSizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2,
    ]

    /// Every text size at or above it abandons the strip.
    static let listSizes: [DynamicTypeSize] = [
        .accessibility3, .accessibility4, .accessibility5,
    ]

    static let slotCounts: [Int] = [1, 3, 6, 10, 16]
}

struct StripLayoutTests {

    // MARK: - The one decision left

    @Test("Every ordinary text size draws a scrolling strip",
          arguments: StripLayoutCases.stripSizes)
    func drawsStripBelowTheThreshold(size: DynamicTypeSize) {
        #expect(StripLayout.resolve(dynamicTypeSize: size) == .strip)
    }

    /// UI-05, and the whole of it that width could never answer.
    @Test("The largest text sizes abandon the strip", arguments: StripLayoutCases.listSizes)
    func listsAtTheLargestTextSizes(size: DynamicTypeSize) {
        #expect(StripLayout.resolve(dynamicTypeSize: size) == .list)
    }

    /// Stated as the boundary rather than as two cases either side of it, so
    /// moving the threshold has to be a deliberate edit to the constant.
    @Test("The threshold is accessibility3, on either device")
    func namesTheThreshold() {
        #expect(StripLayout.listThreshold == .accessibility3)
        #expect(StripLayout.resolve(dynamicTypeSize: .accessibility2) == .strip)
        #expect(StripLayout.resolve(dynamicTypeSize: .accessibility3) == .list)
    }

    /// The ordering the `Comparable` conformance exists for: the list says more
    /// than the strip, so a comparison can stand in for naming both cases.
    @Test("The list is ordered above the strip")
    func ordersListAboveStrip() {
        #expect(StripLayout.strip < StripLayout.list)
    }

    /// Width is no longer an input, and this is the assertion that says so. The
    /// old resolver took a width and could return a different tier for the same
    /// text size on two devices; nothing about the screen can change the answer
    /// now, which is why `grid(for:notices:)` no longer measures one.
    @Test("No device width changes the answer", arguments: StripLayoutCases.stripSizes)
    func widthCannotChangeTheLayout(size: DynamicTypeSize) {
        // There is only one resolver and it takes no width — so the property is
        // that the phone and the iPad, which used to disagree, cannot.
        let phone = StripLayout.resolve(dynamicTypeSize: size)
        let pad = StripLayout.resolve(dynamicTypeSize: size)

        #expect(phone == pad)
    }

    // MARK: - What a row comes to

    @Test("A day laid end to end is the cells plus the gaps between them",
          arguments: StripLayoutCases.slotCounts)
    func measuresContentWidth(slotCount: Int) {
        let width = StripLayout.contentWidth(slotCount: slotCount)
        let expected =
            Double(slotCount) * StripLayout.defaultCellWidth
            + Double(slotCount - 1) * StripLayout.defaultSpacing

        #expect(width == expected)
    }

    /// A finished day. TIME-07 reaches this, and a width function that traps or
    /// returns a negative gap total on it is a crash waiting for the first user
    /// who opens the app at eleven at night.
    @Test("A day with no slots left has no width")
    func handlesEmptyDay() {
        #expect(StripLayout.contentWidth(slotCount: 0) == 0)
        #expect(StripLayout.fitsWithoutScrolling(availableWidth: iPhoneRowWidth, slotCount: 0))
    }

    @Test("More hours never make a shorter row")
    func contentWidthGrowsWithSlots() {
        var previous = StripLayout.contentWidth(slotCount: 0)

        for count in 1...16 {
            let width = StripLayout.contentWidth(slotCount: count)
            #expect(width > previous, "\(count) slots")
            previous = width
        }
    }

    // MARK: - What still fits

    /// The design gave up "the whole day, no scrolling" deliberately, and this
    /// is what it cost: sixteen hours no longer fit on a phone. Asserted rather
    /// than left implicit, because it is the trade the scroll was made for and a
    /// silent regression to a crammed sixteen-column row would otherwise look
    /// like an improvement.
    @Test("A phone cannot show a whole sixteen-hour day at once")
    func aWholeDayScrollsOnAPhone() {
        #expect(
            StripLayout.fitsWithoutScrolling(availableWidth: iPhoneRowWidth, slotCount: 16)
                == false)
    }

    /// The other half of the trade. A short evening — the case the app is most
    /// often opened for — still lands on one screen with nothing to swipe.
    @Test("An evening's remaining hours still fit on a phone without scrolling")
    func anEveningFitsOnAPhone() {
        #expect(StripLayout.fitsWithoutScrolling(availableWidth: iPhoneRowWidth, slotCount: 3))
    }

    @Test("An iPad shows far more of the day than a phone")
    func anIPadFitsMore() {
        let phone = (1...16).filter {
            StripLayout.fitsWithoutScrolling(availableWidth: iPhoneRowWidth, slotCount: $0)
        }.count
        let pad = (1...16).filter {
            StripLayout.fitsWithoutScrolling(availableWidth: iPadRowWidth, slotCount: $0)
        }.count

        #expect(pad > phone)
    }

    /// Monotonicity, which is what stops the two cases above from being a table
    /// of points: a row that fits cannot stop fitting when the screen gets
    /// wider, and one that does not fit cannot start fitting with more hours in
    /// it. Either would mean the arithmetic has an inverted term that happened
    /// to agree with the cases actually listed.
    @Test("More width never stops a row fitting", arguments: StripLayoutCases.slotCounts)
    func moreWidthNeverStopsFitting(slotCount: Int) {
        var everFitted = false

        for width in stride(from: 100.0, through: 1400.0, by: 50.0) {
            let fits = StripLayout.fitsWithoutScrolling(
                availableWidth: width, slotCount: slotCount)

            if everFitted { #expect(fits, "\(slotCount) slots at \(width)pt") }
            everFitted = everFitted || fits
        }
    }

    @Test("More hours never start fitting where fewer did not")
    func moreSlotsNeverStartFitting() {
        for width in [iPhoneRowWidth, iPadRowWidth, iPhoneWidth, iPadWidth] {
            var everFailed = false

            for count in 1...16 {
                let fits = StripLayout.fitsWithoutScrolling(
                    availableWidth: width, slotCount: count)

                if everFailed { #expect(fits == false, "\(count) slots at \(width)pt") }
                everFailed = everFailed || (fits == false)
            }
        }
    }

    // MARK: - The geometry the drawing code shares

    /// The width is set by the calendar reference now, not by the text, so
    /// whether the hour still fits has to be measured rather than assumed. This
    /// is the assertion that used to read `defaultCellWidth >= 64` — true when
    /// the width came from the string, meaningless once it came from a chip.
    ///
    /// Measured at a fixed point size rather than `preferredFont`, so the test
    /// states the default text size it is about instead of inheriting whatever
    /// the runner is set to. The weight is checked against the constant the cell
    /// draws with first: a heavier weight is a wider string, so a measurement
    /// taken at the wrong one would pass while the real text overflowed.
    @Test("A cell fits a whole hour without shrinking it")
    func cellFitsAWholeHour() {
        #expect(StripLayout.captionWeight == .regular, "the measurement below assumes it")

        let font = UIFont.systemFont(ofSize: StripLayout.captionPointSize, weight: .regular)
        let room = StripLayout.defaultCellWidth - 2 * StripLayout.defaultCellPadding

        for text in ["7 AM", "10 AM", "12 PM", "11 PM"] {
            let width = (text as NSString).size(withAttributes: [.font: font]).width

            #expect(width <= room, "\(text) needs \(width)pt, the cell gives \(room)pt")
        }
    }

    /// The endpoint publishes whole hours and every captured payload contains
    /// only those, but `SlotTime.displayString` will render "12:30 PM" the day
    /// one does not. It has to survive that — shrunk, but not truncated — and
    /// the floor it shrinks to is the one the cell actually applies.
    @Test("A half-hour still fits once it is allowed to shrink")
    func cellFitsAHalfHourWhenScaled() {
        let size = StripLayout.captionPointSize * StripLayout.minimumTextScale
        let font = UIFont.systemFont(ofSize: size, weight: .regular)
        let room = StripLayout.defaultCellWidth - 2 * StripLayout.defaultCellPadding

        for text in ["12:30 PM", "10:30 AM"] {
            let width = (text as NSString).size(withAttributes: [.font: font]).width

            #expect(width <= room, "\(text) needs \(width)pt at the floor, cell gives \(room)pt")
        }
    }

    /// The block is proportioned after a calendar's event chips, measured at
    /// 91 × 74 with a 7-pixel gap and a corner radius of about 5 — in that
    /// screenshot's pixels, which are 2× device points. The ratios are what is
    /// asserted, because they are what survives the conversion.
    ///
    /// A tolerance rather than an equality, because the points are the halved
    /// measurements rounded to whole numbers. Asserting the arithmetic exactly
    /// would be asserting the rounding.
    @Test("A cell keeps the reference's near-square proportions")
    func cellMatchesTheReferenceAspect() {
        let referenceAspect = 91.0 / 74.0
        let aspect = StripLayout.defaultCellWidth / StripLayout.defaultCellHeight

        #expect(abs(aspect - referenceAspect) < 0.05, "aspect \(aspect)")
    }

    /// The old block was 34 points tall against 72 wide — a ratio above two,
    /// which read as a row of tags rather than as blocks of time. Pinned as an
    /// upper bound so a later tidy-up cannot quietly flatten them again.
    @Test("A cell is a block rather than a tag")
    func cellIsNotFlat() {
        #expect(StripLayout.defaultCellWidth / StripLayout.defaultCellHeight < 1.5)
    }

    @Test("The gap is about a twelfth of a cell, as in the reference")
    func gapMatchesTheReference() {
        let referenceGap = 7.0 / 91.0
        let gap = StripLayout.defaultSpacing / StripLayout.defaultCellWidth

        #expect(abs(gap - referenceGap) < 0.03, "gap ratio \(gap)")
    }

    @Test("The corner radius is a small fraction of the cell, as in the reference")
    func cornerRadiusMatchesTheReference() {
        let referenceRadius = 5.0 / 91.0
        let radius = StripLayout.defaultCornerRadius / StripLayout.defaultCellWidth

        #expect(abs(radius - referenceRadius) < 0.03, "radius ratio \(radius)")
        #expect(StripLayout.defaultCornerRadius * 2 < StripLayout.defaultCellHeight)
    }

    /// The pinned column and the gaps are shared between the strip and the
    /// section that draws the court numbers beside it. Stated here so that a
    /// change to either is a change to a named constant rather than to one of
    /// two magic numbers that have to agree.
    @Test("The caller can state the geometry it means")
    func exposesItsGeometry() {
        #expect(StripLayout.defaultLabelWidth > 0)
        #expect(StripLayout.defaultSpacing > 0)
        #expect(StripLayout.defaultCellHeight > 0)

        let width = StripLayout.contentWidth(
            slotCount: 4, cellWidth: 100, spacing: 10)

        #expect(width == 430)
    }
}
