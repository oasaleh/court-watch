//
//  EdgeFadeTests.swift
//  CourtWatchTests
//
//  The two cases a fade gets wrong, asserted rather than looked for.
//
//  A fade at the edge of a scroll view is easy to add and easy to add wrongly,
//  and both failures are quiet. Fade the leading edge of a row nobody has
//  scrolled and the first hour of the day is dimmed for no reason. Fade the
//  trailing edge of a row that already fits — an evening with three hours left,
//  which is when this app is most often opened — and the last hour is dimmed to
//  promise content that is not there.
//
//  Neither is visible in a screenshot of a scrolled row, because in a scrolled
//  row both fades are correct. They only appear at the ends, which is where a
//  hand check tends not to go, and a view cannot be scrolled in a unit test at
//  all. Hence a pure function, and hence this file.
//

import Testing

@testable import CourtWatch

/// Argument lists live on a `nonisolated` type: `arguments:` is evaluated
/// outside the enclosing actor.
nonisolated enum EdgeFadeCases {

    /// A phone-width row with a whole day in it: sixteen cells at 43 points
    /// with 4-point gaps comes to 748, against roughly 274 visible.
    ///
    /// Derived rather than written out, so that re-sizing the block re-sizes
    /// these cases with it instead of leaving them asserting a row that no
    /// longer exists.
    static let contentWidth: Double = StripLayout.contentWidth(slotCount: 16)
    static let containerWidth: Double = 274

    static var scrollable: Double { contentWidth - containerWidth }
}

struct EdgeFadeTests {

    // MARK: - The two ends

    /// At rest at the start there is nothing to the left, so nothing fades
    /// there. The right still does — the day continues.
    @Test("A row at its start does not fade its leading edge")
    func doesNotFadeAtTheStart() {
        let fade = EdgeFade.resolve(
            offset: 0,
            contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth
        )

        #expect(fade.leading == 0)
        #expect(fade.trailing == 1)
    }

    @Test("A row at its end does not fade its trailing edge")
    func doesNotFadeAtTheEnd() {
        let fade = EdgeFade.resolve(
            offset: EdgeFadeCases.scrollable,
            contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth
        )

        #expect(fade.leading == 1)
        #expect(fade.trailing == 0)
    }

    /// The case the whole type exists for. A short evening fits on screen, so
    /// there is nothing past either edge and neither may fade — a trailing fade
    /// here would dim the last free hour of the day to suggest more hours that
    /// do not exist.
    @Test("A row that fits fades neither edge", arguments: [1, 2, 3])
    func doesNotFadeARowThatFits(slotCount: Int) {
        let content = StripLayout.contentWidth(slotCount: slotCount)

        let fade = EdgeFade.resolve(
            offset: 0, contentWidth: content, containerWidth: EdgeFadeCases.containerWidth)

        #expect(content < EdgeFadeCases.containerWidth, "precondition: \(slotCount) slots fit")
        #expect(fade == EdgeFade(leading: 0, trailing: 0, containerWidth: fade.containerWidth))
    }

    @Test("A row scrolled through the middle fades both edges")
    func fadesBothEdgesInTheMiddle() {
        let fade = EdgeFade.resolve(
            offset: EdgeFadeCases.scrollable / 2,
            contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth
        )

        #expect(fade.leading == 1)
        #expect(fade.trailing == 1)
    }

    // MARK: - The ramp

    /// The fade eases in over a short distance rather than switching on at the
    /// first pixel of movement, which would pop under the user's own finger.
    @Test("The leading fade eases in over the ramp")
    func easesInOverTheRamp() {
        let ramp = EdgeFade.defaultRamp

        for (offset, expected) in [(0.0, 0.0), (ramp / 4, 0.25), (ramp / 2, 0.5), (ramp, 1.0)] {
            let fade = EdgeFade.resolve(
                offset: offset,
                contentWidth: EdgeFadeCases.contentWidth,
                containerWidth: EdgeFadeCases.containerWidth,
                ramp: ramp
            )

            #expect(abs(fade.leading - expected) < 0.001, "at \(offset)pt")
        }
    }

    @Test("The trailing fade eases out approaching the end")
    func easesOutApproachingTheEnd() {
        let ramp = EdgeFade.defaultRamp
        let end = EdgeFadeCases.scrollable

        for (remaining, expected) in [(0.0, 0.0), (ramp / 2, 0.5), (ramp, 1.0)] {
            let fade = EdgeFade.resolve(
                offset: end - remaining,
                contentWidth: EdgeFadeCases.contentWidth,
                containerWidth: EdgeFadeCases.containerWidth,
                ramp: ramp
            )

            #expect(abs(fade.trailing - expected) < 0.001, "\(remaining)pt from the end")
        }
    }

    /// A caller that wants no easing can ask for none, and must not divide by
    /// the ramp to find out.
    @Test("A zero ramp degenerates to a switch rather than dividing by zero")
    func handlesAZeroRamp() {
        let atStart = EdgeFade.resolve(
            offset: 0, contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth, ramp: 0)

        #expect(atStart.leading == 0)
        #expect(atStart.trailing == 1)

        let moved = EdgeFade.resolve(
            offset: 1, contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth, ramp: 0)

        #expect(moved.leading == 1)
    }

    // MARK: - Rubber-banding

    /// Every flick produces offsets outside the scrollable range — negative at
    /// the start, past the end at the finish. Clamped rather than rejected: a
    /// fade that inverted itself during a bounce would be more distracting than
    /// no fade at all.
    @Test("An over-scrolled offset is clamped, not inverted", arguments: [-120.0, -40.0, -1.0])
    func clampsRubberBandingAtTheStart(offset: Double) {
        let fade = EdgeFade.resolve(
            offset: offset,
            contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth
        )

        #expect(fade.leading == 0)
        #expect(fade.trailing == 1)
    }

    @Test("An offset past the end is clamped too")
    func clampsRubberBandingAtTheEnd() {
        for extra in [1.0, 40.0, 120.0] {
            let fade = EdgeFade.resolve(
                offset: EdgeFadeCases.scrollable + extra,
                contentWidth: EdgeFadeCases.contentWidth,
                containerWidth: EdgeFadeCases.containerWidth
            )

            #expect(fade.leading == 1, "\(extra)pt past the end")
            #expect(fade.trailing == 0, "\(extra)pt past the end")
        }
    }

    /// Both fades stay in range at every position, which is what the gradient
    /// needs: an opacity outside 0…1 is undefined and a location outside it
    /// silently reorders the stops.
    @Test("Both edges stay within range at every offset")
    func staysInRange() {
        for offset in stride(from: -200.0, through: EdgeFadeCases.scrollable + 200, by: 37) {
            let fade = EdgeFade.resolve(
                offset: offset,
                contentWidth: EdgeFadeCases.contentWidth,
                containerWidth: EdgeFadeCases.containerWidth
            )

            #expect(fade.leading >= 0 && fade.leading <= 1, "at \(offset)")
            #expect(fade.trailing >= 0 && fade.trailing <= 1, "at \(offset)")
        }
    }

    // MARK: - The band

    /// The band is specified in points and consumed as a gradient stop, so the
    /// conversion has to survive a row of no width — which is what it is handed
    /// before the first layout pass.
    @Test("A row of no width asks for no band")
    func handlesAnUnmeasuredRow() {
        #expect(EdgeFade.none.bandFraction == 0)
        #expect(EdgeFade.none.containerWidth == 0)
    }

    @Test("The band is the fade width as a fraction of the row")
    func convertsTheBandToAFraction() {
        let fade = EdgeFade.resolve(
            offset: 100,
            contentWidth: EdgeFadeCases.contentWidth,
            containerWidth: EdgeFadeCases.containerWidth
        )

        #expect(
            abs(fade.bandFraction - EdgeFade.bandWidth / EdgeFadeCases.containerWidth) < 0.001)
    }

    /// Two bands wider than the row itself would put the gradient's second stop
    /// past its third, which reorders them and produces a hard edge — the exact
    /// artefact the fade exists to remove.
    @Test("A very narrow row still leaves an opaque middle")
    func capsTheBandOnANarrowRow() {
        for width in [10.0, 30.0, 60.0, 78.0] {
            let fade = EdgeFade.resolve(
                offset: 5, contentWidth: 500, containerWidth: width)

            #expect(fade.bandFraction <= 1.0 / 3.0 + 0.001, "at \(width)pt")
            #expect(fade.bandFraction < 1 - fade.bandFraction, "stops must stay ordered")
        }
    }
}
