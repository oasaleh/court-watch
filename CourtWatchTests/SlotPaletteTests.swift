//
//  SlotPaletteTests.swift
//  CourtWatchTests
//
//  That the two schemes differ is the assertion this file exists for.
//
//  A palette can be split into a light and a dark value and still hold the same
//  hex in both, and nothing about that is visible in review: the file *looks*
//  scheme-aware, every screenshot of one mode looks right, and the bug is only
//  ever seen by someone who switches. So the inequality is asserted directly,
//  state by state, in the raw hex and again in the colour the strip actually
//  fills a block with.
//
//  The blocks are compared as resolved sRGB components rather than as `Color`
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

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        red = Double(resolved.red)
        green = Double(resolved.green)
        blue = Double(resolved.blue)
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

    /// How light the colour is, roughly. Enough to assert that a dark-mode
    /// block sits above its surface rather than under it.
    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

struct SlotPaletteTests {

    // MARK: - The two schemes are genuinely different

    @Test("Every hue is a different colour in dark mode", arguments: SlotPaletteCases.fills)
    func hueDiffersByScheme(fill: SlotFill) {
        let hue = SlotPalette.hue(for: fill)

        #expect(hue.light != hue.dark)
    }

    /// The specific failure this guards: a block that draws identically in both
    /// schemes because the pair was filled in with the same value twice.
    @Test("Every block is a different colour in dark mode", arguments: SlotPaletteCases.fills)
    func blockDiffersByScheme(fill: SlotFill) {
        let light = RGB(SlotPalette.fill(for: fill, scheme: .light, contrast: .standard))
        let dark = RGB(SlotPalette.fill(for: fill, scheme: .dark, contrast: .standard))

        #expect(light.distance(to: dark) > 0.1)
    }

    @Test("The hour written in a cell is a different colour in dark mode",
          arguments: SlotPaletteCases.fills)
    func inkDiffersByScheme(fill: SlotFill) {
        let light = RGB(SlotPalette.ink(for: fill, scheme: .light))
        let dark = RGB(SlotPalette.ink(for: fill, scheme: .dark))

        #expect(light.distance(to: dark) > 0.1)
    }

    /// The surface a block is mixed into is the grouped-list row behind it, and
    /// in dark mode that row is #1C1C1E rather than black. Mixing into black
    /// darkens every dark-mode block by more than intended, which is the
    /// "muddy" failure — so the value is pinned rather than left to drift back.
    @Test("The dark surface is the grouped-list row, not black")
    func darkSurfaceIsNotBlack() {
        #expect(SlotPalette.surface.dark != 0x000000)
        #expect(SlotPalette.surface.light != SlotPalette.surface.dark)
    }

    // MARK: - The states stay distinct within a scheme

    /// The one thing the grid exists to do. If a colour edit ever pushed two
    /// states together in one scheme, a glance would stop answering the
    /// question — and it could happen in dark mode only, which is why every
    /// scheme is checked rather than just the one on the reviewer's screen.
    @Test("The three blocks stay pairwise distinct in every scheme",
          arguments: SlotPaletteCases.schemes)
    func blocksStayDistinct(scheme: ColorScheme) {
        let available = RGB(SlotPalette.fill(for: .filled, scheme: scheme, contrast: .standard))
        let booked = RGB(SlotPalette.fill(for: .outline, scheme: scheme, contrast: .standard))
        let unknown = RGB(SlotPalette.fill(for: .hatched, scheme: scheme, contrast: .standard))

        #expect(available.distance(to: booked) > 0.1)
        #expect(available.distance(to: unknown) > 0.1)
        #expect(booked.distance(to: unknown) > 0.1)
    }

    @Test("The three hues are pairwise distinct in every scheme",
          arguments: SlotPaletteCases.schemes)
    func huesStayDistinct(scheme: ColorScheme) {
        let hexes = SlotPaletteCases.fills.map { SlotPalette.hue(for: $0).hex(for: scheme) }

        #expect(Set(hexes).count == hexes.count)
    }

    /// A block that cannot be told from the row it sits in is not a block. Both
    /// schemes, because the light mix is deliberately the fainter of the two
    /// and is the one with the smaller margin.
    @Test("Every block separates from the surface behind it",
          arguments: SlotPaletteCases.schemes)
    func blocksSeparateFromSurface(scheme: ColorScheme) {
        let surface = RGB(SlotPalette.surface.color(for: scheme))

        for fill in SlotPaletteCases.fills {
            let block = RGB(SlotPalette.fill(for: fill, scheme: scheme, contrast: .standard))

            #expect(block.distance(to: surface) > 0.05)
        }
    }

    /// Dark mode paints *onto* its surface rather than into it: every block has
    /// to come out lighter than the row behind it, or the grid reads as holes
    /// punched in the list.
    @Test("Dark-mode blocks sit above their surface", arguments: SlotPaletteCases.fills)
    func darkBlocksAreLighterThanSurface(fill: SlotFill) {
        let surface = RGB(SlotPalette.surface.color(for: .dark))
        let block = RGB(SlotPalette.fill(for: fill, scheme: .dark, contrast: .standard))

        #expect(block.luminance > surface.luminance)
    }

    // MARK: - The mix strengths

    /// The reason the pair exists: the fraction that reads as a soft wash on
    /// white is near-invisible against #1C1C1E, so dark mode must take more of
    /// the hue. Asserted as an ordering rather than as two literals, so tuning
    /// a value cannot silently invert the relationship.
    @Test("Dark mode takes more of the hue than light mode does")
    func darkMixesHarder() {
        #expect(SlotPalette.fillStrength.dark > SlotPalette.fillStrength.light)
        #expect(SlotPalette.fillStrengthIncreased.dark > SlotPalette.fillStrengthIncreased.light)
    }

    @Test("Increased contrast takes more of the hue than standard does",
          arguments: SlotPaletteCases.schemes)
    func increasedContrastMixesHarder(scheme: ColorScheme) {
        let standard = SlotPalette.fillStrength.value(for: scheme)
        let increased = SlotPalette.fillStrengthIncreased.value(for: scheme)

        #expect(increased > standard)
    }

    @Test("Every mix strength stays a fraction")
    func mixStrengthsAreFractions() {
        let all = [
            SlotPalette.fillStrength, SlotPalette.fillStrengthIncreased, SlotPalette.inkStrength,
        ]

        for strength in all {
            #expect(strength.light > 0 && strength.light < 1)
            #expect(strength.dark > 0 && strength.dark < 1)
        }
    }

    @Test("Increased contrast draws a different block from standard",
          arguments: SlotPaletteCases.schemes)
    func increasedContrastChangesTheBlock(scheme: ColorScheme) {
        let standard = RGB(SlotPalette.fill(for: .filled, scheme: scheme, contrast: .standard))
        let increased = RGB(SlotPalette.fill(for: .filled, scheme: scheme, contrast: .increased))

        #expect(standard.distance(to: increased) > 0.01)
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
}
