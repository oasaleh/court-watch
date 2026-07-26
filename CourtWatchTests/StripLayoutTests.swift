//
//  StripLayoutTests.swift
//  CourtWatchTests
//
//  UI-05 and UI-08, as arithmetic.
//
//  The widths here are measured, not chosen: an iPhone 17 Pro is 1206 × 2622
//  pixels at 3×, which is 402 × 874 points; an iPad Pro 13-inch (M5) is
//  2064 × 2752 at 2×, which is 1032 × 1376. Written out rather than rounded so
//  that a future device makes this file obviously stale instead of quietly
//  wrong.
//
//  The two monotonicity properties are what stop this from being a table of
//  points. A per-case table alone would pass against a function with an
//  inverted threshold that happened to match every listed case; asserting that
//  more width never yields a poorer tier, and that a cell never claims more
//  room than exists, constrains the shape of the function instead.
//

import SwiftUI
import Testing

@testable import CourtWatch

/// Measured device widths in points.
private let iPhoneWidth: Double = 402
private let iPadWidth: Double = 1032

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor. `DynamicTypeSize` values inside one are fine;
/// the array holding them is what needs the annotation.
nonisolated enum StripLayoutCases {

    /// width, slots, text size, expected tier.
    static let all: [(Double, Int, DynamicTypeSize, StripLayout)] = [
        // A phone showing the whole day cannot carry a mark in a cell.
        (402, 16, .large, .dense),
        (402, 12, .large, .dense),

        // Enough room for a glyph, not for a word.
        (402, 10, .large, .glyph),

        // Few enough slots that the hour fits inside the cell.
        (402, 6, .large, .labeled),
        (402, 3, .large, .labeled),
        (402, 1, .large, .labeled),

        // D4: the iPad spends its width on labelling in place.
        (1032, 16, .large, .labeled),
        (1032, 1, .large, .labeled),

        // Text size wins over width, on either device.
        (402, 16, .accessibility3, .list),
        (1032, 16, .accessibility3, .list),
        (1032, 3, .accessibility5, .list),
    ]
}

struct StripLayoutTests {

    @Test("The tier follows from the width and the text size", arguments: StripLayoutCases.all)
    func resolvesTier(
        width: Double, slots: Int, size: DynamicTypeSize, expected: StripLayout
    ) {
        #expect(
            StripLayout.resolve(availableWidth: width, slotCount: slots, dynamicTypeSize: size)
                == expected,
            "\(width)pt across \(slots) slots at \(size)"
        )
    }

    @Test("A phone showing the whole day draws blocks only")
    func phoneWithWholeDayIsDense() {
        #expect(
            StripLayout.resolve(
                availableWidth: iPhoneWidth, slotCount: 16, dynamicTypeSize: .large) == .dense)
    }

    @Test("A phone with six slots has room for a symbol")
    func phoneWithSixSlotsDrawsASymbol() {
        let tier = StripLayout.resolve(
            availableWidth: iPhoneWidth, slotCount: 6, dynamicTypeSize: .large)

        #expect(tier >= .glyph)
    }

    @Test("A phone with three slots writes the hour in the cell")
    func phoneWithThreeSlotsIsLabelled() {
        #expect(
            StripLayout.resolve(
                availableWidth: iPhoneWidth, slotCount: 3, dynamicTypeSize: .large) == .labeled)
    }

    /// D4, asserted rather than argued. The requirement asks the iPad to show
    /// "more time slots at once"; under this design the phone already shows all
    /// of them, so the iPad spends its width writing the hour inside each cell
    /// instead. This is the assertion that pins that reading.
    @Test("An iPad showing the whole day writes the hour in every cell")
    func iPadWithWholeDayIsLabelled() {
        #expect(
            StripLayout.resolve(
                availableWidth: iPadWidth, slotCount: 16, dynamicTypeSize: .large) == .labeled)
    }

    /// A comparison rather than two hardcoded expectations, which could both be
    /// updated to agree with a bug.
    @Test("At the same slot count the iPad tier is strictly richer than the phone's")
    func iPadOutranksPhone() {
        let phone = StripLayout.resolve(
            availableWidth: iPhoneWidth, slotCount: 16, dynamicTypeSize: .large)
        let pad = StripLayout.resolve(
            availableWidth: iPadWidth, slotCount: 16, dynamicTypeSize: .large)

        #expect(pad > phone)
    }

    /// UI-05. At the largest sizes there is no width that rescues a
    /// sixteen-column strip, so the strip is abandoned rather than shrunk.
    @Test(
        "Any width at an accessibility size resolves to the text list",
        arguments: [
            DynamicTypeSize.accessibility3,
            DynamicTypeSize.accessibility4,
            DynamicTypeSize.accessibility5,
        ]
    )
    func accessibilitySizesAbandonTheStrip(size: DynamicTypeSize) {
        for width in [320.0, 402.0, 744.0, 1032.0, 2000.0] {
            #expect(
                StripLayout.resolve(availableWidth: width, slotCount: 16, dynamicTypeSize: size)
                    == .list,
                "\(width)pt at \(size)")
            #expect(
                StripLayout.resolve(availableWidth: width, slotCount: 1, dynamicTypeSize: size)
                    == .list,
                "\(width)pt, one slot, at \(size)")
        }
    }

    /// The ordering inside `resolve` is what this checks: a very wide container
    /// at a very large text size must still list, or the accessibility case is
    /// being decided after the arithmetic instead of before it.
    @Test("A wide iPad at the largest text size still lists")
    func textSizeBeatsWidth() {
        #expect(
            StripLayout.resolve(
                availableWidth: 4000, slotCount: 3, dynamicTypeSize: .accessibility5) == .list)
    }

    /// A finished day has zero slots. The caller will not draw a strip then, but
    /// a layout function that trapped here would crash for the first user who
    /// opened the app at eleven at night.
    @Test("Zero slots resolves without dividing by zero")
    func handlesZeroSlots() {
        #expect(
            StripLayout.resolve(availableWidth: iPhoneWidth, slotCount: 0, dynamicTypeSize: .large)
                == .dense)
        #expect(StripLayout.cellWidth(availableWidth: iPhoneWidth, slotCount: 0) == 0)
    }

    @Test("One slot is labelled on either device")
    func handlesSingleSlot() {
        #expect(
            StripLayout.resolve(availableWidth: iPhoneWidth, slotCount: 1, dynamicTypeSize: .large)
                == .labeled)
        #expect(
            StripLayout.resolve(availableWidth: iPadWidth, slotCount: 1, dynamicTypeSize: .large)
                == .labeled)
    }

    /// A strip one point wider than its container is the classic version of this
    /// bug, so the arithmetic is constrained rather than sampled.
    @Test("A cell never claims more room than exists")
    func neverExceedsAvailableWidth() {
        for width in stride(from: 120.0, through: 1400.0, by: 20.0) {
            for slots in 1...16 {
                let cell = StripLayout.cellWidth(availableWidth: width, slotCount: slots)
                let used =
                    cell * Double(slots)
                    + StripLayout.defaultLabelWidth
                    + StripLayout.defaultSpacing * Double(slots - 1)

                #expect(cell >= 0, "\(width)pt across \(slots) slots")
                #expect(used <= width + 0.000_001, "\(width)pt across \(slots) slots used \(used)")
            }
        }
    }

    /// Constrains the shape of the function rather than a handful of its points:
    /// an inverted threshold that happened to satisfy every case in the table
    /// would fail here.
    @Test("More width never yields a poorer tier")
    func tierIsMonotonicInWidth() {
        for slots in 1...16 {
            var previous = StripLayout.resolve(
                availableWidth: 100, slotCount: slots, dynamicTypeSize: .large)

            for width in stride(from: 110.0, through: 2000.0, by: 10.0) {
                let tier = StripLayout.resolve(
                    availableWidth: width, slotCount: slots, dynamicTypeSize: .large)

                #expect(tier >= previous, "\(width)pt across \(slots) slots went backwards")
                previous = tier
            }
        }
    }

    /// The same property along the other axis: at a fixed width, fewer slots can
    /// only ever give each cell more room.
    @Test("Fewer slots never yields a poorer tier")
    func tierIsMonotonicInSlotCount() {
        for width in [402.0, 744.0, 1032.0] {
            var previous = StripLayout.resolve(
                availableWidth: width, slotCount: 16, dynamicTypeSize: .large)

            for slots in stride(from: 15, through: 1, by: -1) {
                let tier = StripLayout.resolve(
                    availableWidth: width, slotCount: slots, dynamicTypeSize: .large)

                #expect(tier >= previous, "\(width)pt across \(slots) slots went backwards")
                previous = tier
            }
        }
    }

    /// The geometry is stated by the caller rather than inherited from a
    /// drawing file, so a test can assert a layout it fully describes.
    @Test("The caller can state the geometry it means")
    func acceptsExplicitGeometry() {
        // No label column and no gaps: the whole width belongs to the cells.
        #expect(
            StripLayout.cellWidth(
                availableWidth: 320, slotCount: 16, labelWidth: 0, spacing: 0) == 20)

        // The same width once the court column and the gaps are taken out.
        #expect(
            StripLayout.resolve(
                availableWidth: 320, slotCount: 16, dynamicTypeSize: .large,
                labelWidth: 0, spacing: 0) == .dense)
    }

    /// The measured figure this phase's whole design rests on: a container of
    /// about 330 points — an iPhone list row — gives ≈17 point cells at 16
    /// slots. If this ever stops holding, every layout decision above inherits
    /// the error.
    @Test("Sixteen slots in a phone list row are about seventeen points each")
    func reproducesThePlannedCellWidth() {
        let cell = StripLayout.cellWidth(availableWidth: 330, slotCount: 16)

        #expect(cell > 16 && cell < 18, "measured \(cell)pt")
    }
}
