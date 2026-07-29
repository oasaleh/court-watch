//
//  SlotPalette.swift
//  CourtWatch
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  EVERY COLOUR THE AVAILABILITY GRID DRAWS IS WRITTEN IN THIS FILE.   │
//  │  To change a shade, edit a hex under "The hexes" below. Nothing      │
//  │  else in the app names a colour for a time slot.                     │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  Why a file rather than three `.green`/`.red`/`.orange` literals in the view:
//  those literals are one colour each, and this grid needs two. A hue tuned to
//  read as a pale wash on white is the same hue that comes out muddy once it is
//  mixed into a near-black surface, and the reverse — a hue bright enough to
//  glow in the dark — is washed out and low-contrast on white. So every colour
//  here is declared twice, once per scheme, and resolved against the scheme the
//  cell is actually being drawn in.
//
//  Why hex numbers and not an asset catalog colour set. The strip does not paint
//  its hues directly; it mixes them into the surface (`SlotBlock.fill`) and
//  toward the text colour (`SlotPalette.ink`). Those mixes need a concrete
//  starting colour in a known space, and a hex literal sitting next to the
//  strength it is mixed at is legible as one decision. Split across the catalog
//  UI and this file it would be two, in two places, that only look right
//  together.
//
//  The surface is declared here as well, and that matters more than it looks.
//  A strip row is a grouped-list row, whose background is `secondarySystemGroupedBackground`
//  — white in light mode but #1C1C1E in dark, *not* black. Mixing into black
//  when the row behind is #1C1C1E darkens every block by more than the intended
//  amount, which is precisely the "muddy in dark mode" failure. The value below
//  is the real row colour.
//
//  D2 still holds: hue is the primary channel and ink density is the fallback,
//  reinstated whenever the system reports Differentiate Without Color. Changing
//  a hex here changes how the grid looks; it cannot change what a state means,
//  because meaning lives in `SlotAppearance` and this file never sees a
//  `SlotStatus`. It is handed a `SlotFill` — an amount of ink — and answers with
//  a colour. That separation is what keeps a colour edit from being able to make
//  a booked hour read as free.
//

import SwiftUI

// MARK: - A colour, written once per scheme

/// One colour with a light-mode and a dark-mode value.
///
/// A pair rather than a single value with an opacity or brightness tweak
/// applied at draw time, because "the same colour, adjusted" is the assumption
/// that produces muddy dark mode. Light and dark are chosen independently and
/// the pair keeps them side by side, where a reviewer can see both.
nonisolated struct SchemeColor: Hashable, Sendable {

    /// 0xRRGGBB as drawn on a light background.
    let light: UInt32

    /// 0xRRGGBB as drawn on a dark background.
    let dark: UInt32

    /// The raw hex for a scheme. Exposed so tests can assert the two differ
    /// without going through colour resolution.
    func hex(for scheme: ColorScheme) -> UInt32 {
        scheme == .dark ? dark : light
    }

    func color(for scheme: ColorScheme) -> Color {
        Color(hex: hex(for: scheme))
    }
}

// MARK: - The palette

nonisolated enum SlotPalette {

    // MARK: - The hexes
    //
    // ↓↓↓  CHANGE COLOURS HERE — this block, and only this block.  ↓↓↓

    /// A free hour. Deeper in light mode so a 28% wash on white still reads as
    /// green rather than as a grey; brighter in dark mode so the same block
    /// does not sink into the row behind it.
    static let available = SchemeColor(light: 0x1F9E4B, dark: 0x3FDD6E)

    /// A taken hour. A true red rather than a warm one: at a 28% wash on white
    /// a warm red and the amber below converge into the same pale orange, which
    /// `SlotPaletteTests.blocksStayDistinct` catches and fails on.
    static let booked = SchemeColor(light: 0xC62828, dark: 0xFF6259)

    /// An hour the app cannot vouch for — an unrecognised status or one the
    /// payload never published. Gold rather than orange, for the reason above:
    /// orange is what red *becomes* when it is washed out, so the two have to be
    /// separated at the hue before the mix pulls them together. Not yellow
    /// either — yellow at a low mix on white is very nearly invisible.
    static let unknown = SchemeColor(light: 0xE8A317, dark: 0xFFB13A)

    /// What the blocks are mixed *into*: the grouped-list row behind the strip.
    ///
    /// Not black in dark mode. See the file note — this is
    /// `secondarySystemGroupedBackground`, and getting it wrong is what makes
    /// dark blocks come out heavier than intended.
    static let surface = SchemeColor(light: 0xFFFFFF, dark: 0x1C1C1E)

    // MARK: - How far the hue is mixed into the surface
    //
    // 0 is the bare surface, 1 the undiluted hue. Higher in dark mode because
    // the fraction that reads as a soft wash on white comes out near-invisible
    // against #1C1C1E.

    /// The everyday wash.
    static let fillStrength = SchemeStrength(light: 0.28, dark: 0.62)

    /// Increased-contrast: the user has asked for stronger separation, so more
    /// of the hue and less of the surface.
    static let fillStrengthIncreased = SchemeStrength(light: 0.38, dark: 0.78)

    /// How far the hue is pushed toward the text colour for the hour written
    /// inside a labelled cell.
    ///
    /// Toward black on light, toward white on dark. Green and amber are the
    /// ones that need it: at full saturation both sit close in luminance to
    /// their own wash, and caption text needs 4.5:1.
    static let inkStrength = SchemeStrength(light: 0.45, dark: 0.34)

    // ↑↑↑  CHANGE COLOURS HERE — this block, and only this block.  ↑↑↑

    // MARK: - Resolving

    /// The hue for an amount of ink.
    ///
    /// Takes a `SlotFill`, never a `SlotStatus`. This file draws; it does not
    /// decide what anything means. No `default` arm, matching `SlotAppearance`:
    /// a fourth fill must stop this file compiling rather than silently
    /// inheriting a colour.
    static func hue(for fill: SlotFill) -> SchemeColor {
        switch fill {
        case .filled: available
        case .outline: booked
        case .hatched: unknown
        }
    }

    /// The undiluted hue, as used for strokes, hatching and glyphs.
    static func tint(for fill: SlotFill, scheme: ColorScheme) -> Color {
        hue(for: fill).color(for: scheme)
    }

    /// The block itself: the hue mixed opaquely into the surface.
    ///
    /// A perceptual mix rather than `.opacity()`. A translucent hue takes its
    /// result from whatever happens to be behind it and loses chroma over a
    /// dark background, which is what comes out muddy; mixing against the real
    /// surface colour does not.
    static func fill(
        for fill: SlotFill,
        scheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Color {
        let strength =
            contrast == .increased
            ? fillStrengthIncreased.value(for: scheme)
            : fillStrength.value(for: scheme)

        return surface.color(for: scheme)
            .mix(with: tint(for: fill, scheme: scheme), by: strength, in: .perceptual)
    }

    /// The hour written inside a labelled cell: the hue pushed far enough
    /// toward the text colour to stay legible on its own wash.
    static func ink(for fill: SlotFill, scheme: ColorScheme) -> Color {
        let strength = inkStrength.value(for: scheme)
        let toward: Color = scheme == .dark ? .white : .black

        return tint(for: fill, scheme: scheme).mix(with: toward, by: strength, in: .perceptual)
    }
}

// MARK: - A mix strength, written once per scheme

nonisolated struct SchemeStrength: Hashable, Sendable {

    let light: Double
    let dark: Double

    func value(for scheme: ColorScheme) -> Double {
        scheme == .dark ? dark : light
    }
}

// MARK: - Hex

extension Color {

    /// A 0xRRGGBB literal as an opaque sRGB colour.
    ///
    /// sRGB explicitly rather than `.displayP3`, because a hex written by a
    /// human is a hex read off a design tool or a browser, and both mean sRGB.
    /// Reading it as P3 would quietly oversaturate every colour in this file.
    ///
    /// `nonisolated` because this module defaults to main-actor isolation and
    /// the palette that calls it is a `nonisolated` type.
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
