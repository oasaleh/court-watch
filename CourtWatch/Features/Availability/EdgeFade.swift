//
//  EdgeFade.swift
//  CourtWatch
//
//  How much of each edge of a scrolling row is faded out.
//
//  A hard cut at the edge of a scroll view is ambiguous in exactly the wrong
//  way: a block sliced down the middle looks like a rendering fault rather than
//  like content continuing, and at the leading edge it looks like an hour whose
//  colour you can see but whose label you cannot. Fading the edge says the same
//  thing a cut was trying to say — there is more this way — without producing a
//  half-drawn block to explain.
//
//  The subtlety, and the reason this is a type rather than a modifier applied
//  once and forgotten: a fade that is always on is a lie in both directions. Fade
//  the leading edge of a row scrolled to its start and the first hour of the day
//  is dimmed for no reason; fade the trailing edge of a row that fits entirely on
//  screen — an evening with three hours left, which is when this app is most
//  often opened — and the last hour is dimmed to promise content that does not
//  exist. So each edge is driven by whether there is actually anything past it.
//
//  It is a pure function of the scroll geometry, which is what lets the awkward
//  cases be asserted rather than discovered. A view cannot be scrolled in a unit
//  test, and this is the whole of the behaviour that would otherwise only be
//  checkable by hand.
//

import Foundation

/// How opaque each edge of a scrolling row should be, 0 for untouched and 1 for
/// fully faded.
nonisolated struct EdgeFade: Equatable, Sendable {

    /// The leading edge — the one you have scrolled away from.
    let leading: Double

    /// The trailing edge — the one with the rest of the day behind it.
    let trailing: Double

    /// The width the row was measured in, carried along so the view can turn a
    /// fade in points into the fractional gradient stop it needs. Zero until the
    /// first geometry arrives.
    let containerWidth: Double

    /// Nothing faded. What a row that fits entirely on screen stays at forever.
    static let none = EdgeFade(leading: 0, trailing: 0, containerWidth: 0)

    /// How far the row has to scroll before an edge is fully faded, in points.
    ///
    /// A ramp rather than a switch. Flipping a fade on the first pixel of
    /// movement is a visible pop at the exact moment the user's finger is on the
    /// content; over a short distance it reads as the edge softening because the
    /// row moved, which is what actually happened.
    static let defaultRamp: Double = 24

    /// How wide the faded band is, in points.
    ///
    /// Roughly a third of a cell. Wide enough to read as a fade rather than as a
    /// blurred edge, narrow enough that a fully visible cell next to it is not
    /// dimmed.
    static let bandWidth: Double = 26

    /// The fade for a given scroll position.
    ///
    /// `offset` is how far the content has been scrolled from its start,
    /// `contentWidth` the full width of the row, `containerWidth` what is
    /// visible of it.
    ///
    /// Both edges fall out of the same question asked in two directions: how
    /// much is there on this side that you cannot see? When the row fits, the
    /// answer is zero on both and nothing fades. Offsets outside the scrollable
    /// range are clamped rather than rejected, because rubber-banding produces
    /// them on every flick — a negative offset at the start and one past the end
    /// at the finish — and a fade that inverted itself during a bounce would be
    /// worse than none.
    static func resolve(
        offset: Double,
        contentWidth: Double,
        containerWidth: Double,
        ramp: Double = defaultRamp
    ) -> EdgeFade {
        let scrollable = max(0, contentWidth - containerWidth)
        let clamped = min(max(offset, 0), scrollable)

        return EdgeFade(
            leading: fraction(of: clamped, over: ramp),
            trailing: fraction(of: scrollable - clamped, over: ramp),
            containerWidth: max(0, containerWidth)
        )
    }

    /// How far along the ramp a distance is, 0 to 1.
    ///
    /// A ramp of zero or less degenerates to a switch rather than dividing by
    /// it, so a caller that wants no easing can ask for none.
    private static func fraction(of distance: Double, over ramp: Double) -> Double {
        guard ramp > 0 else { return distance > 0 ? 1 : 0 }

        return min(1, max(0, distance / ramp))
    }
}

extension EdgeFade {

    /// Where the fade finishes, as a fraction of the row's width.
    ///
    /// The gradient wants stops in 0…1 and the band is specified in points, so
    /// this is the conversion — capped at a third so that a very narrow row
    /// fades rather than disappearing into two overlapping gradients.
    var bandFraction: Double {
        guard containerWidth > 0 else { return 0 }

        return min(EdgeFade.bandWidth / containerWidth, 1.0 / 3.0)
    }
}
