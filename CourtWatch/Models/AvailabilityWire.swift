//
//  AvailabilityWire.swift
//  CourtWatch
//
//  A faithful mirror of the availability payload, kept separate from the
//  domain types on purpose.
//
//  This shape belongs to a third party. It is undocumented, unversioned, and
//  can change without notice, so it is decoded defensively: anything the app
//  does not strictly need is optional, and collections default to empty rather
//  than failing the document. The domain types next door are what the rest of
//  the app is allowed to depend on, and they change only when the app's own
//  needs change.
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
        resources = try container.decodeIfPresent([WireResource].self, forKey: .resources) ?? []
        timeIncrement = try container.decodeIfPresent(Int.self, forKey: .timeIncrement)
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
    let status: Int
    let selected: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case selected
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Int.self, forKey: .status)
        selected = try container.decodeIfPresent(Bool.self, forKey: .selected)
    }
}
