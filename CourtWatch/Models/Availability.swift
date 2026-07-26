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

    /// Courts whose slot array did not match the published slot list.
    ///
    /// These are still present in `courts`, with the slots that could be
    /// paired. Naming them here gives Phase 5 something honest to surface
    /// instead of silently showing a short row.
    let degradedCourts: [String]

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
            let slots = zip(times, resource.timeSlotDetails).map { time, detail in
                CourtSlot(time: time, status: SlotStatus(rawStatus: detail.status))
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
    }

    /// The courts regrouped as the user thinks of them. Derived rather than
    /// stored so there is one source of truth for what a facility contains.
    var facilities: [Facility] {
        Facility.group(courts)
    }
}
