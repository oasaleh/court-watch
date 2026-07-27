//
//  AvailabilityWire.swift
//  CourtWatch
//
//  A faithful mirror of the availability payload, kept separate from the
//  domain types on purpose.
//
//  This shape belongs to a third party. It is undocumented, unversioned, and
//  can change without notice, so it is decoded defensively. That defensiveness
//  now reaches *elements*, not only collections, and it takes two deliberately
//  different forms:
//
//    * A slot detail whose status cannot be read keeps its place in the array
//      and yields no value. Details are positionally parallel to the slot
//      times, so deleting one would relabel every later hour — see the note on
//      `WireSlotDetail.status`.
//    * A resource that cannot be read is dropped entirely, and counted.
//      Resources are independent of one another and an unidentifiable one
//      cannot be shown or grouped, so there is nothing to salvage.
//
//  The headers are deliberately **not** tolerant: a response with no readable
//  code keeps throwing, because defaulting it to success would render an error
//  envelope as availability.
//
//  The domain types next door are what the rest of the app is allowed to depend
//  on, and they change only when the app's own needs change.
//
//  Every type here is `nonisolated`. Decoding happens off the main actor, and
//  under this module's default isolation a main-actor-isolated initializer
//  cannot be referenced from there.
//

import Foundation

nonisolated struct AvailabilityEnvelope: Decodable, Sendable {
    let headers: ResponseHeaders
    let body: WireBody
}

nonisolated struct ResponseHeaders: Decodable, Sendable {

    /// A **string**, not a number.
    ///
    /// The measured success value is `"0000"` and the session-expiry codes are
    /// `"0002"` through `"0021"`. Decoded as an integer these collapse to 0, 2,
    /// 21 and the leading zeros that identify them are gone.
    let responseCode: String

    let responseMessage: String?

    /// Already camelCase in the payload, unlike every field around it. Not a
    /// transcription error — do not "correct" it to snake_case.
    let sessionRefreshedOn: String?

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case responseMessage = "response_message"
        case sessionRefreshedOn
    }
}

nonisolated struct WireBody: Decodable, Sendable {
    let availability: WireAvailability
}

nonisolated struct WireAvailability: Decodable, Sendable {
    let timeSlots: [String]
    let resources: [WireResource]
    let timeIncrement: Int?

    /// How many resources were discarded because they could not be read.
    ///
    /// Counted rather than dropped silently. A court that disappears with no
    /// trace is the silent loss this codebase has already refused twice — Phase
    /// 2 kept the names of short courts and Phase 3 kept unmatched favorites for
    /// the same reason. A count is enough here and a name is not available: a
    /// resource whose name or id is what failed to decode has nothing to be
    /// named by.
    let droppedResources: Int

    // Deliberately not decoded: `default_starting_time` and
    // `default_ending_time`. They arrive as "1899-12-30 07:00:00" — a sentinel
    // date, not a slot string — and the ending value (23:00) matches no
    // published slot, the last of which is 22:00. Deriving a slot list or a
    // slot count from them would be wrong in two independent ways. `time_slots`
    // is the only authority.
    //
    // Also not decoded: `page_info.total_records`, which reads 0 while 80
    // resources are present. It describes a pagination concept this endpoint
    // does not use.

    enum CodingKeys: String, CodingKey {
        case timeSlots = "time_slots"
        case resources
        case timeIncrement = "time_increment"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeSlots = try container.decodeIfPresent([String].self, forKey: .timeSlots) ?? []
        timeIncrement = try container.decodeIfPresent(Int.self, forKey: .timeIncrement)

        // Decoded element by element, keeping the ones that decode and counting
        // the ones that do not — see `TolerantResource` for why the tolerance
        // lives in the element type rather than in a loop here.
        let elements =
            try container.decodeIfPresent([TolerantResource].self, forKey: .resources) ?? []

        resources = elements.compactMap(\.resource)
        droppedResources = elements.count - resources.count
    }
}

/// A resource that decodes to nothing rather than failing the document.
///
/// Resources are independent of one another, so an unidentifiable one is safe
/// to discard: without a readable id or name it can neither be shown nor
/// grouped into a facility, so there is nothing to salvage — and the other
/// seventy-nine are unaffected, which is the whole point.
///
/// Note this is **the opposite** of the treatment slot details get, and the
/// asymmetry is deliberate. A detail's meaning comes from its position in the
/// array; a resource's does not.
///
/// Written as a wrapper whose own `init` never throws, rather than as a loop
/// that catches around an unkeyed container. A container's index does not
/// advance past an element whose decode threw, so the catching form has to
/// consume the failed element by hand or spin forever — a trap worth designing
/// out rather than remembering.
private nonisolated struct TolerantResource: Decodable, Sendable {
    let resource: WireResource?

    init(from decoder: any Decoder) throws {
        resource = try? WireResource(from: decoder)
    }
}

nonisolated struct WireResource: Decodable, Sendable {
    let resourceID: Int
    let resourceName: String
    let warningMessages: [String]
    let timeSlotDetails: [WireSlotDetail]

    /// Null on all 80 resources in both captures. A non-optional `String` here
    /// fails the whole payload on a field nothing reads.
    let packageName: String?
    let packageID: Int?
    let typeName: String?
    let attendance: Int?

    enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case resourceName = "resource_name"
        case warningMessages = "warning_messages"
        case timeSlotDetails = "time_slot_details"
        case packageName = "package_name"
        case packageID = "package_id"
        case typeName = "type_name"
        case attendance
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceID = try container.decode(Int.self, forKey: .resourceID)
        resourceName = try container.decode(String.self, forKey: .resourceName)
        warningMessages =
            try container.decodeIfPresent([String].self, forKey: .warningMessages) ?? []
        timeSlotDetails =
            try container.decodeIfPresent([WireSlotDetail].self, forKey: .timeSlotDetails) ?? []
        packageName = try container.decodeIfPresent(String.self, forKey: .packageName)
        packageID = try container.decodeIfPresent(Int.self, forKey: .packageID)
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
        attendance = try container.decodeIfPresent(Int.self, forKey: .attendance)
    }
}

nonisolated struct WireSlotDetail: Decodable, Sendable {

    /// Optional, and this is the single most consequential decision in this
    /// file.
    ///
    /// A null, absent, or wrongly-typed status yields *no value* rather than
    /// throwing — which means the detail object still decodes, and still
    /// occupies its place in the array. That is the whole point, and the reason
    /// the obvious alternative is dangerous:
    ///
    /// `time_slot_details` is **positionally parallel** to `time_slots`, and
    /// nothing in the payload restates a slot's time inside its own detail.
    /// Position is the only thing connecting a status to an hour. So a tolerant
    /// decode that *skipped* the elements it could not read would slide every
    /// later status one place earlier, and a court free at 6 PM would be
    /// advertised as free at 5 PM — a wrong answer, with no error, in the one
    /// direction this app must never be wrong.
    ///
    /// A placeholder holds that connection. A deletion breaks it silently.
    ///
    /// Measured before this was written: one null among the capture's 1,280
    /// details discarded all 80 courts and put the user on an error screen.
    let status: Int?

    let selected: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case selected
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // `decodeIfPresent` is not enough on its own: it returns nil for an
        // absent key or an explicit null, but still throws on a type mismatch —
        // and a status sent as the string "0" is exactly the case measured to
        // fail the whole document today.
        status = (try? container.decode(Int.self, forKey: .status)) ?? nil

        selected = try? container.decodeIfPresent(Bool.self, forKey: .selected) ?? nil
    }
}
