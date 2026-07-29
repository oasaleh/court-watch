//
//  SlotPaletteTests.swift
//  CourtWatchTests
//
//  Two things this file exists to catch, neither of which a screenshot can.
//
//  The first is a pair that renders identically in both appearances. A palette
//  can be split into a light and a dark value and still hold the same colour in
//  both, and nothing about that is visible in review: the file *looks*
//  appearance-aware, every screenshot of one mode looks right, and the bug is
//  only ever seen by someone who switches.
//
//  The second is contrast, and it is why this file measures rather than
//  compares. The treatment that preceded these pairs had three failures in it —
//  dark-mode label text at 2.9:1, and, in the path a user who has declined
//  colour depends on, white text at 1.78:1 and a gold hairline at 2.3:1. Every
//  one of them looked fine in a screenshot. Only the ratio said otherwise.
//
//  Colours are compared as resolved sRGB components rather than as `Color`
//  values. Two `Color`s built by different routes can compare unequal while
//  rendering identically, which would make an equality assertion pass for the
//  wrong reason; resolving to numbers compares what reaches the screen.
//

import SwiftUI
import Testing

@testable import CourtWatch

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum SlotPaletteCases {

    /// Every amount of ink the grid can draw.
    static let fills: [SlotFill] = [.filled, .outline, .hatched]

    static let schemes: [ColorScheme] = [.light, .dark]
}

/// A colour as it reaches the screen: sRGB components, 0 to 1.
private struct RGB {

    let red: Double
    let green: Double
    let blue: Double

    /// WCAG relative luminance: the standard weights over *linearised*
    /// channels.
    ///
    /// Distinct from the cheap `luminance` below on purpose. That one is an
    /// ordering and says nothing about legibility; this is the number the 4.5:1
    /// rule is defined against, and using the cheap one in its place would
    /// overstate the contrast of exactly the mid-tone colours a palette is made
    /// of.
    let relativeLuminance: Double

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        red = Double(resolved.red)
        green = Double(resolved.green)
        blue = Double(resolved.blue)

        relativeLuminance =
            0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
    }

    /// Straight-line distance in sRGB. Crude as a perceptual measure, which is
    /// fine: it is used only to say "these are not the same colour", never to
    /// claim how different they look.
    func distance(to other: RGB) -> Double {
        let dr = red - other.red
        let dg = green - other.green
        let db = blue - other.blue

        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// How light the colour is, roughly.
    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// WCAG contrast ratio, 1:1 to 21:1.
    func contrast(against other: RGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)

        return (lighter + 0.05) / (darker + 0.05)
    }
}

struct SlotPaletteTests {

    // MARK: - The hour written inside a block

    /// The headline property of the pair model: because both ends are named
    /// rather than derived from a mix, the contrast between them is a fact about
    /// this file alone and can simply be measured.
    ///
    /// AA is the floor asserted, and the supplied pairs land there rather than
    /// at AAA — measured, the weakest is the dark booked pair at about 4.7:1 and
    /// the light free pair at about 5.4:1. That matters because Increase
    /// Contrast has no separate treatment any more: the previous palette mixed a
    /// hue into the surface at a tuned strength, so there was a knob to turn,
    /// and written-out pairs have no knob. A user with that setting on now sees
    /// exactly what everyone else does. Raising these to AAA, or adding a second
    /// set of pairs for that setting, are both real options — guessing at either
    /// would be inventing colours nobody asked for.
    @Test("The hour clears 4.5:1 against its own block",
          arguments: SlotPaletteCases.fills, SlotPaletteCases.schemes)
    func foregroundIsLegibleOnItsBackground(fill: SlotFill, scheme: ColorScheme) {
        let background = RGB(SlotPalette.background(for: fill, scheme: scheme))
        let foreground = RGB(SlotPalette.foreground(for: fill, scheme: scheme))

        #expect(foreground.contrast(against: background) >= 4.5)
    }

    // MARK: - The two appearances are genuinely different

    @Test("Every block is a different colour in dark mode", arguments: SlotPaletteCases.fills)
    func backgroundDiffersByScheme(fill: SlotFill) {
        let colors = SlotPalette.colors(for: fill)

        #expect(colors.background.light != colors.background.dark)

        let light = RGB(SlotPalette.background(for: fill, scheme: .light))
        let dark = RGB(SlotPalette.background(for: fill, scheme: .dark))

        #expect(light.distance(to: dark) > 0.1)
    }

    @Test("Every hour is a different colour in dark mode", arguments: SlotPaletteCases.fills)
    func foregroundDiffersByScheme(fill: SlotFill) {
        let colors = SlotPalette.colors(for: fill)

        #expect(colors.foreground.light != colors.foreground.dark)

        let light = RGB(SlotPalette.foreground(for: fill, scheme: .light))
        let dark = RGB(SlotPalette.foreground(for: fill, scheme: .dark))

        #expect(light.distance(to: dark) > 0.1)
    }

    /// Light blocks in light mode, dark blocks in dark mode. Stated as a
    /// property rather than as six hex assertions, so it holds through a
    /// re-tune: a pair accidentally swapped between appearances passes every
    /// other test in this file and looks obviously wrong on a device.
    @Test("A block is light in light mode and dark in dark mode",
          arguments: SlotPaletteCases.fills)
    func blocksSitOnTheRightSideOfTheirSurface(fill: SlotFill) {
        let lightSurface = RGB(SlotPalette.surface.color(for: .light))
        let darkSurface = RGB(SlotPalette.surface.color(for: .dark))

        let light = RGB(SlotPalette.background(for: fill, scheme: .light))
        let dark = RGB(SlotPalette.background(for: fill, scheme: .dark))

        #expect(light.luminance > darkSurface.luminance)
        #expect(dark.luminance < lightSurface.luminance)
        #expect(light.luminance > dark.luminance)
    }

    /// The surface is not mixed into anything any more, but it is still what a
    /// declined-colour shape has to be visible against, and it is still set by
    /// the list style rather than by anything in the palette.
    @Test("The surface is the plain-list backdrop the strip is drawn on")
    func surfaceIsTheListBackground() {
        #expect(SlotPalette.surface.light == 0xFFFFFF)
        #expect(SlotPalette.surface.dark == 0x000000)
    }

    // MARK: - The states stay distinct within an appearance

    /// The one thing the grid exists to do. If a colour edit ever pushed two
    /// states together in one appearance, a glance would stop answering the
    /// question — and it could happen in dark mode only, which is why every
    /// appearance is checked rather than just the one on the reviewer's screen.
    @Test("The three blocks stay pairwise distinct in every appearance",
          arguments: SlotPaletteCases.schemes)
    func blocksStayDistinct(scheme: ColorScheme) {
        let available = RGB(SlotPalette.background(for: .filled, scheme: scheme))
        let booked = RGB(SlotPalette.background(for: .outline, scheme: scheme))
        let unknown = RGB(SlotPalette.background(for: .hatched, scheme: scheme))

        #expect(available.distance(to: booked) > 0.1)
        #expect(available.distance(to: unknown) > 0.1)
        #expect(booked.distance(to: unknown) > 0.1)
    }

    @Test("The three hours stay pairwise distinct in every appearance",
          arguments: SlotPaletteCases.schemes)
    func foregroundsStayDistinct(scheme: ColorScheme) {
        let available = RGB(SlotPalette.foreground(for: .filled, scheme: scheme))
        let booked = RGB(SlotPalette.foreground(for: .outline, scheme: scheme))
        let unknown = RGB(SlotPalette.foreground(for: .hatched, scheme: scheme))

        #expect(available.distance(to: booked) > 0.1)
        #expect(available.distance(to: unknown) > 0.1)
        #expect(booked.distance(to: unknown) > 0.1)
    }

    /// D6's colour half. An hour the app cannot vouch for is drawn in neutral
    /// grey precisely so it cannot be read as either answer; a grey that drifted
    /// toward the free green would be the wasted-drive bug wearing a new colour.
    @Test("The unknown state is neutral, not a third answer",
          arguments: SlotPaletteCases.schemes)
    func unknownIsNeutral(scheme: ColorScheme) {
        for color in [
            RGB(SlotPalette.background(for: .hatched, scheme: scheme)),
            RGB(SlotPalette.foreground(for: .hatched, scheme: scheme)),
        ] {
            let channels = [color.red, color.green, color.blue]
            let spread = (channels.max() ?? 0) - (channels.min() ?? 0)

            #expect(spread < 0.06, "grey should have near-equal channels, spread \(spread)")
        }
    }

    /// A block that cannot be told from the row it sits in is not a block.
    @Test("Every block separates from the surface behind it",
          arguments: SlotPaletteCases.schemes)
    func blocksSeparateFromSurface(scheme: ColorScheme) {
        let surface = RGB(SlotPalette.surface.color(for: scheme))

        for fill in SlotPaletteCases.fills {
            let block = RGB(SlotPalette.background(for: fill, scheme: scheme))

            #expect(block.distance(to: surface) > 0.03)
        }
    }

    // MARK: - When colour has been declined

    /// The path a user who has switched Differentiate Without Color on is
    /// relying on, and the one that was carrying white text at 1.78:1 before it
    /// was measured. It is invisible to screenshots — the simulator stores the
    /// preference and SwiftUI never receives it — so this is the only check
    /// there is.
    @Test("The hour clears 4.5:1 when colour has been declined",
          arguments: SlotPaletteCases.fills, SlotPaletteCases.schemes)
    func differentiatedInkIsLegible(fill: SlotFill, scheme: ColorScheme) {
        let backdrop = RGB(SlotPalette.differentiatedBackdrop(for: fill, scheme: scheme))
        let ink = RGB(SlotPalette.differentiatedInk(for: fill, scheme: scheme))

        #expect(ink.contrast(against: backdrop) >= 4.5)
    }

    /// In this path the *shape* carries the meaning — solid, empty, hatched —
    /// so it has to be visible against the surface at 3:1, the bar for a
    /// graphical object. The block colour would not manage it: it is a quiet
    /// fill, which is why the shape is drawn in the saturated end of the pair.
    @Test("The declined-colour shape clears 3:1 against the surface",
          arguments: SlotPaletteCases.fills, SlotPaletteCases.schemes)
    func differentiatedShapeSeparatesFromSurface(fill: SlotFill, scheme: ColorScheme) {
        let surface = RGB(SlotPalette.surface.color(for: scheme))
        let shape = RGB(SlotPalette.differentiatedShape(for: fill, scheme: scheme))

        #expect(shape.contrast(against: surface) >= 3.0)
    }

    /// White is what the solid block's ink used to be, and dark mode is where
    /// that was catastrophic: the block there is the bright end of the pair, and
    /// white on it measures under 2:1.
    ///
    /// Asserted for dark only, because light mode is the honest exception —
    /// white on the deep green would in fact pass. Claiming white fails
    /// everywhere would be a satisfying assertion and a false one, and a test
    /// that overstates its finding is the kind that gets deleted later along
    /// with the finding.
    @Test("White would fail on the dark-mode solid block")
    func whiteWouldFailOnTheDarkSolidBlock() {
        let block = RGB(SlotPalette.differentiatedBackdrop(for: .filled, scheme: .dark))

        #expect(RGB(.white).contrast(against: block) < 4.5)
    }

    /// The solid block is drawn in the foreground colour and the hour on it in
    /// the background colour — the same pair, read in reverse. Contrast is
    /// symmetric, so this path inherits the pair's guarantee rather than needing
    /// tuning of its own, and that inheritance is what is asserted.
    @Test("The declined-colour block reads its pair in reverse",
          arguments: SlotPaletteCases.schemes)
    func differentiatedBlockReversesThePair(scheme: ColorScheme) {
        let block = RGB(SlotPalette.differentiatedBackdrop(for: .filled, scheme: scheme))
        let ink = RGB(SlotPalette.differentiatedInk(for: .filled, scheme: scheme))

        let background = RGB(SlotPalette.background(for: .filled, scheme: scheme))
        let foreground = RGB(SlotPalette.foreground(for: .filled, scheme: scheme))

        #expect(block.distance(to: foreground) < 0.001)
        #expect(ink.distance(to: background) < 0.001)
        #expect(ink.contrast(against: block) >= 4.5)
    }

    // MARK: - Hex

    /// The channel order, checked. A red/blue swap here would tint the whole
    /// grid and every other assertion in this file would still pass.
    @Test("A hex reads as red, then green, then blue")
    func readsHexChannelsInOrder() {
        let red = RGB(Color(hex: 0xFF0000))
        #expect(red.red > 0.99 && red.green < 0.01 && red.blue < 0.01)

        let green = RGB(Color(hex: 0x00FF00))
        #expect(green.red < 0.01 && green.green > 0.99 && green.blue < 0.01)

        let blue = RGB(Color(hex: 0x0000FF))
        #expect(blue.red < 0.01 && blue.green < 0.01 && blue.blue > 0.99)
    }

    @Test("Black and white round-trip through hex")
    func readsHexEndpoints() {
        let black = RGB(Color(hex: 0x000000))
        #expect(black.luminance < 0.01)

        let white = RGB(Color(hex: 0xFFFFFF))
        #expect(white.luminance > 0.99)
    }

    /// The four hexes a designer handed over, pinned exactly as given. Every
    /// other test here is a property; these two are the record of what was
    /// asked for, so a re-tune that drifts off the brief is visible as a diff.
    @Test("The supplied hexes are drawn as supplied")
    func keepsTheSuppliedHexes() {
        #expect(SlotPalette.available.background.light == 0xE0F4D4)
        #expect(SlotPalette.available.foreground.light == 0x416B2A)
        #expect(SlotPalette.available.background.dark == 0x213515)
        #expect(SlotPalette.available.foreground.dark == 0x83D754)

        #expect(SlotPalette.booked.background.light == 0xFECDCE)
        #expect(SlotPalette.booked.foreground.light == 0x7F1C1E)
        #expect(SlotPalette.booked.background.dark == 0x421011)
        #expect(SlotPalette.booked.foreground.dark == 0xFF4246)
    }
}
