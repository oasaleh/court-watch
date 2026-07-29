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
//  Every colour is declared twice, once per appearance. A colour tuned to read
//  as a soft block on white is the same one that comes out muddy on black, and
//  the reverse — one bright enough to hold up in the dark — is washed out on
//  white. Declaring a single value and adjusting it at draw time is the
//  assumption that produces bad dark mode, so both halves are written out and
//  chosen rather than derived.
//
//  Each state is a *pair of pairs*: a background and the foreground written on
//  it, per appearance. That is the whole model, and it replaced an earlier one
//  that mixed a single hue into the surface at a tuned strength. The mix was
//  clever and wrong: it made a block's final colour a function of the surface
//  behind it, so the same constant drew differently in two places, and the text
//  on top had to be re-derived from the result and tuned back into legibility.
//  Naming both ends outright is duller and cannot drift.
//
//  Because both ends are named rather than computed, the contrast between them
//  is a property of this file alone. `SlotPaletteTests` measures every pair
//  against WCAG: 4.5:1 for the hour written inside a block, 3:1 for a shape that
//  has to be seen at all. That is not ceremony — measuring is how three real
//  failures were found in the treatment that preceded this one, including white
//  text at 1.78:1 in the path a user who has declined colour depends on.
//
//  D2 still holds: colour is the primary channel and ink density is the
//  fallback, reinstated whenever the system reports Differentiate Without Color.
//  Changing a hex here changes how the grid looks; it cannot change what a state
//  means, because meaning lives in `SlotAppearance` and this file never sees a
//  `SlotStatus`. It is handed a `SlotFill` — an amount of ink — and answers with
//  a colour. That separation is what keeps a colour edit from being able to make
//  a booked hour read as free.
//

import SwiftUI

// MARK: - A colour, written once per appearance

/// One colour with a light-mode and a dark-mode value.
nonisolated struct SchemeColor: Hashable, Sendable {

    /// 0xRRGGBB as drawn on a light background.
    let light: UInt32

    /// 0xRRGGBB as drawn on a dark background.
    let dark: UInt32

    /// The raw hex for an appearance. Exposed so tests can assert the two
    /// differ without going through colour resolution.
    func hex(for scheme: ColorScheme) -> UInt32 {
        scheme == .dark ? dark : light
    }

    func color(for scheme: ColorScheme) -> Color {
        Color(hex: hex(for: scheme))
    }
}

/// A block and the text written on it, in both appearances.
///
/// The two travel together because they are only ever correct together. Split
/// into separate constants, a later edit can brighten a background without
/// touching the foreground that has to stay legible on it — which is exactly how
/// a pair ends up at 1.78:1 with nothing in the file looking wrong.
nonisolated struct SlotColors: Hashable, Sendable {

    let background: SchemeColor
    let foreground: SchemeColor

    init(
        lightBackground: UInt32, lightForeground: UInt32,
        darkBackground: UInt32, darkForeground: UInt32
    ) {
        background = SchemeColor(light: lightBackground, dark: darkBackground)
        foreground = SchemeColor(light: lightForeground, dark: darkForeground)
    }
}

// MARK: - The palette

nonisolated enum SlotPalette {

    // MARK: - The hexes
    //
    // ↓↓↓  CHANGE COLOURS HERE — this block, and only this block.  ↓↓↓

    /// A free hour.
    static let available = SlotColors(
        lightBackground: 0xE0F4D4, lightForeground: 0x416B2A,
        darkBackground: 0x213515, darkForeground: 0x83D754
    )

    /// A taken hour.
    static let booked = SlotColors(
        lightBackground: 0xFECDCE, lightForeground: 0x7F1C1E,
        darkBackground: 0x421011, darkForeground: 0xFF4246
    )

    /// An hour the app cannot vouch for — an unrecognised status, or one the
    /// payload never published.
    ///
    /// Neutral rather than a third hue, and that is the design. Free and busy
    /// are the two answers the user came for; a colour of its own would put this
    /// state on the same footing as them, when what it says is that there is no
    /// answer. Grey reads as absence, which is the truth. It must still never be
    /// mistaken for either, and `blocksStayDistinct` measures that.
    static let unknown = SlotColors(
        lightBackground: 0xE6E6E9, lightForeground: 0x4A4A52,
        darkBackground: 0x2A2A2E, darkForeground: 0xB4B4C0
    )

    /// The backdrop the strip is drawn on: `systemBackground`, because the list
    /// is `.listStyle(.plain)` and its rows draw no card of their own.
    ///
    /// Black in dark mode, not the #1C1C1E of a grouped row. Coupled to the list
    /// style in `FavoritesScreen` — change one and this changes with it. Nothing
    /// is mixed into it any more; it is the reference a shape has to be visible
    /// against once colour has been declined.
    static let surface = SchemeColor(light: 0xFFFFFF, dark: 0x000000)

    // ↑↑↑  CHANGE COLOURS HERE — this block, and only this block.  ↑↑↑

    // MARK: - Resolving

    /// The colours for an amount of ink.
    ///
    /// Takes a `SlotFill`, never a `SlotStatus`. This file draws; it does not
    /// decide what anything means. No `default` arm, matching `SlotAppearance`:
    /// a fourth fill must stop this file compiling rather than silently
    /// inheriting a colour.
    static func colors(for fill: SlotFill) -> SlotColors {
        switch fill {
        case .filled: available
        case .outline: booked
        case .hatched: unknown
        }
    }

    /// The block.
    static func background(for fill: SlotFill, scheme: ColorScheme) -> Color {
        colors(for: fill).background.color(for: scheme)
    }

    /// The hour written on that block.
    static func foreground(for fill: SlotFill, scheme: ColorScheme) -> Color {
        colors(for: fill).foreground.color(for: scheme)
    }

    // MARK: - When colour has been declined
    //
    // Differentiate Without Color is on, so the cell goes back to drawing an
    // amount of ink: a solid block, an empty outline, a hatch. Meaning stops
    // depending on which colour a block is — but the shapes are still drawn in
    // one, and a hairline has to hold up against the *surface* rather than
    // against its own block. The foreground end of each pair is what does that:
    // it is the saturated one, chosen to be legible, where the background is a
    // quiet fill that would all but vanish as a stroke.

    /// What the shape itself is drawn with: the saturated end of the pair.
    static func differentiatedShape(for fill: SlotFill, scheme: ColorScheme) -> Color {
        foreground(for: fill, scheme: scheme)
    }

    /// The hour and the symbol drawn on top of that shape.
    ///
    /// The solid block is drawn in the foreground colour, so the text on it
    /// takes the background — the same pair, read in reverse. Contrast is
    /// symmetric, so a pair that clears 4.5:1 one way clears it the other, and
    /// this path inherits the guarantee instead of needing tuning of its own.
    static func differentiatedInk(for fill: SlotFill, scheme: ColorScheme) -> Color {
        switch fill {
        case .filled:
            return background(for: fill, scheme: scheme)

        case .outline, .hatched:
            // The shape is empty or barely washed, so the hour is really
            // sitting on the surface and keeps the legible end of the pair.
            return foreground(for: fill, scheme: scheme)
        }
    }

    /// What `differentiatedInk` is actually drawn on, so the pair can be
    /// measured rather than assumed.
    ///
    /// The hatched cell is approximated by its surface. Its interior is a 12%
    /// wash over that surface, which moves the number by less than the margin
    /// the test demands.
    static func differentiatedBackdrop(for fill: SlotFill, scheme: ColorScheme) -> Color {
        switch fill {
        case .filled: foreground(for: fill, scheme: scheme)
        case .outline, .hatched: surface.color(for: scheme)
        }
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
