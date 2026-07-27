//
//  SlotAppearance.swift
//  CourtWatch
//
//  One mapping from what a slot *is* to how it looks and what VoiceOver says.
//
//  Both channels come from here, so the pixels and the spoken word cannot
//  disagree — a cell that looks free and announces itself booked would be worse
//  than either answer alone. It also means the drawing code holds no branch on
//  status at all: it asks for an appearance and renders it.
//
//  D2 (revised): colour is the primary channel and ink density is the fallback.
//  Solid green reads as free, solid red as taken, orange as unknown — chosen
//  because a row of solid blocks reads as a bar chart at a glance, where an
//  outline for booked read as "faint" rather than "taken". Because hue alone
//  fails for red-green colour blindness, the drawing code reinstates the density
//  treatment — solid, outline, hatched — the moment iOS reports Differentiate
//  Without Color, and brings the symbols back with it. Both channels are still
//  described here; which one leads is a rendering decision made at draw time.
//
//  D6: the mapping is total over the three cases with no catch-all arm. A
//  fourth status would stop this file compiling at the one place that decides
//  how a state looks, rather than being quietly routed into an existing branch.
//  That is deliberate and a grep gate keeps it that way — resist adding a
//  `default` to silence the error, because the error is the feature.
//

import Foundation

/// How much ink a cell is drawn with. Not a colour — see the note above.
nonisolated enum SlotFill: Hashable, Sendable {

    /// The most ink: a solid block. Reads as a run of solid bars across a row,
    /// which is what makes "one glance tell all" work without reading anything.
    case filled

    /// The least: an empty shape with a hairline border.
    case outline

    /// In between, and texturally distinct from both — neither a solid block
    /// nor an empty one, so it cannot be mistaken for either at a glance.
    case hatched
}

nonisolated struct SlotAppearance: Hashable, Sendable {

    let fill: SlotFill

    /// An SF Symbol name, drawn only once a cell is wide enough to carry one.
    let symbolName: String

    /// The word VoiceOver reads for this state.
    let spokenState: String

    /// Relative ink density, 0 to 1.
    ///
    /// Exists so that D2's central claim — that the encoding is legible by
    /// density alone — is a checked property rather than an intention. A test
    /// asserts the strict ordering; without a number to compare there would be
    /// nothing to assert and "readable in greyscale" would stay an opinion.
    let inkWeight: Double

    /// The one place a status becomes pixels and words.
    ///
    /// No `default` arm, on purpose. See the file note.
    static func of(_ status: SlotStatus) -> SlotAppearance {
        switch status {
        case .available:
            return SlotAppearance(
                fill: .filled,
                symbolName: "checkmark",
                spokenState: "Available",
                inkWeight: 1.0
            )

        case .booked:
            return SlotAppearance(
                fill: .outline,
                symbolName: "xmark",
                spokenState: "Booked",
                inkWeight: 0.12
            )

        case .unknown:
            // The raw value is deliberately discarded. It is diagnostic, not
            // user-facing, and two different unrecognised codes must look
            // identical — putting an unexplained integer on a user's screen
            // would be worse than saying plainly that the app does not know.
            return SlotAppearance(
                fill: .hatched,
                symbolName: "questionmark",
                spokenState: "Availability unknown",
                inkWeight: 0.55
            )
        }
    }

    /// What VoiceOver reads before the state: the court and the time.
    ///
    /// The default reading of a grid is a flood of context-free state words.
    /// This restores the row and column context a sighted user reads off the
    /// axes, which is UI-06.
    ///
    /// The time comes from `SlotTime.displayString` so it goes through
    /// `CourtTime` like every other time in the app. Building it any other way
    /// fails the discipline guard, and would print a 24-hour time to a
    /// VoiceOver user on a device set that way.
    static func label(court: String, slot: SlotTime) -> String {
        "\(court), \(slot.displayString)"
    }

    /// The whole sentence, in reading order: court, time, then state.
    ///
    /// The view splits this across `accessibilityLabel` and
    /// `accessibilityValue` so VoiceOver announces label-then-value naturally.
    /// Assembled here as well so a test can assert the sentence a user actually
    /// hears — including its time string, which is what puts it under the
    /// twelve-hour gate.
    static func fullLabel(court: String, slot: SlotTime, status: SlotStatus) -> String {
        "\(label(court: court, slot: slot)), \(of(status).spokenState)"
    }
}
