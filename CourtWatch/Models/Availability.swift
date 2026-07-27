//
//  Availability.swift
//  CourtWatch
//
//  The domain shape: what the app believes about a day's courts, independent
//  of how the server happened to phrase it.
//
//  The pairing built here — each court's slot statuses against the published
//  slot times — is the structure Phase 4 renders. The payload never restates a
//  slot's time inside its own detail, so position is the only thing connecting
//  a status to an hour, and this is the one place that connection is made.
//

import Foundation

nonisolated enum SlotStatus: Hashable, Sendable {
    case available
    case booked

    /// A status the API has not used before.
    ///
    /// Carrying the raw value rather than folding it into a known case is
    /// deliberate. Defaulting an unrecognised status to `available` would show
    /// a court as free when it may not be, which is the one wrong answer this
    /// app must never give; defaulting it to `booked` would hide courts that
    /// are free. Unknown stays unknown and the UI decides how to say so.
    case unknown(Int)

    /// An hour the payload said nothing readable about.
    ///
    /// The distinction from `unknown` is worth keeping and easy to lose.
    /// `unknown` is a value the API *did* send that this app does not
    /// understand; this is the API not having said anything at all — either
    /// because the court published fewer details than there were slots, or
    /// because the one it published for this hour could not be read.
    ///
    /// Both mean the app cannot claim the court is free, which is the only
    /// thing that matters at the point of drawing — and so both render
    /// identically. But they are different facts about what arrived, and the
    /// domain keeps them apart because they are diagnostically different and
    /// separately testable. The collapse happens in `SlotAppearance`, once, on
    /// purpose.
    case unpublished

    init(rawStatus: Int) {
        switch rawStatus {
        case 0: self = .available
        case 1: self = .booked
        default: self = .unknown(rawStatus)
        }
    }
}

nonisolated struct CourtSlot: Hashable, Sendable {
    let time: SlotTime
    let status: SlotStatus
}

nonisolated struct Court: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String

    /// The facility this court belongs to, derived from its name. Phase 3
    /// persists favorites keyed by this exact string.
    let facilityName: String

    let slots: [CourtSlot]
    let warnings: [String]
}

nonisolated struct Availability: Sendable {
    let slotTimes: [SlotTime]
    let courts: [Court]

    /// How long a slot lasts, in minutes, as published by the API.
    ///
    /// Carried rather than assumed. Whether a slot is over is decided by its
    /// start plus this number, so a wrong value here is the one class of wrong
    /// answer this app must never give: were the Township to move to 30-minute
    /// slots and the app to assume 60, then at 2:45 PM it would still be
    /// showing the 2:30 PM slot as live, fifteen minutes after it ended — a
    /// court advertised as free that is not.
    let slotMinutes: Int

    /// The slot length used when the API does not publish a usable one.
    ///
    /// 60 is the measured value: all three committed fixtures, the inline stub
    /// in the client suite, and both live captures publish `time_increment: 60`.
    ///
    /// Falling back to zero would be "safer" in the narrow sense of never
    /// showing a slot that is over, but it would mark every slot elapsed the
    /// instant it began and tell a user at noon that the day was finished — a
    /// broken app in exchange for a theoretical guarantee.
    static let fallbackSlotMinutes = 60

    /// Courts whose slot array did not match the published slot list.
    ///
    /// These are still present in `courts`, with the slots that could be
    /// paired. Naming them here is what lets the interface say plainly that a
    /// court reported partial data instead of silently showing a short row.
    let degradedCourts: [String]

    /// How many resources the payload carried that could not be read at all.
    ///
    /// Kept distinct from `degradedCourts`, and the distinction matters: a
    /// degraded court is one you can still see, with some hours it said nothing
    /// about, while an unreadable one is not on the screen at all. Merging them
    /// would tell the user the wrong thing about what they are looking at.
    ///
    /// A count rather than names, because a resource whose name or id is what
    /// failed to decode has nothing to be named by.
    let unreadableCourts: Int

    init(envelope: AvailabilityEnvelope) {
        let wire = envelope.body.availability

        // Spelled as an explicit closure rather than `compactMap(SlotTime.init)`.
        // This runs off the main actor, where an unapplied reference to a
        // main-actor-isolated initializer does not convert.
        let times = wire.timeSlots.compactMap { SlotTime(apiString: $0) }

        var courts: [Court] = []
        var degraded: [String] = []

        for resource in wire.resources {
            // `zip` stops at the shorter sequence, so a resource publishing
            // fewer details than there are slot times cannot over-index. The
            // mismatch is recorded rather than thrown: one malformed resource
            // must not cost the user the other seventy-nine.
            //
            // A detail whose status could not be read still arrives here, in
            // its own place, carrying no value — so it becomes an hour the app
            // says nothing about rather than a hole that pulls the rest of the
            // row forward. That placeholder is the whole reason the wire type
            // decodes the field as an optional.
            let slots = zip(times, resource.timeSlotDetails).map { time, detail in
                CourtSlot(
                    time: time,
                    status: detail.status.map { raw in SlotStatus(rawStatus: raw) }
                        ?? .unpublished
                )
            }

            if resource.timeSlotDetails.count != times.count {
                degraded.append(resource.resourceName)
            }

            courts.append(
                Court(
                    id: resource.resourceID,
                    name: resource.resourceName,
                    facilityName: FacilityName.derive(from: resource.resourceName),
                    slots: slots,
                    warnings: resource.warningMessages
                )
            )
        }

        self.slotTimes = times
        self.courts = courts
        self.degradedCourts = degraded
        self.unreadableCourts = wire.droppedResources

        // Guarded rather than trusted. The field is optional on the wire and
        // this is an undocumented third-party endpoint, so a missing or
        // nonsensical increment must degrade to the measured value instead of
        // to a broken screen — a zero or negative length would mark every slot
        // elapsed the moment it began. DATA-09's posture, applied to a field
        // that had not needed it before.
        if let published = wire.timeIncrement, published > 0 {
            self.slotMinutes = published
        } else {
            self.slotMinutes = Self.fallbackSlotMinutes
        }
    }

    /// The courts regrouped as the user thinks of them. Derived rather than
    /// stored so there is one source of truth for what a facility contains.
    var facilities: [Facility] {
        Facility.group(courts)
    }
}
