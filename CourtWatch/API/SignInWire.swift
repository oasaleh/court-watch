//
//  SignInWire.swift
//  CourtWatch
//
//  The sign-in request as it was captured, and the reply read at both layers.
//
//  ## The request is copied, not designed
//
//  Ten fields, exactly as recorded from a real browser sign-in. Three of them
//  are booleans **spelled as strings**, and the casing is inconsistent between
//  them — `"False"`, `"False"`, `"true"`. That looks like a transcription
//  error and it is not. This API has already been observed to be literal about
//  payload shape, which is why the availability request encodes its unused time
//  bounds as present-and-null rather than omitting them.
//
//  Nothing here is derived, normalised, or tidied, because the cost of being
//  wrong is a sign-in attempt against an account that arms a captcha after one.
//
//  ## The reply is a trap
//
//  The envelope's `response_code` was measured to be `"0000"` — *Successful* —
//  for a **rejected password**. It reports on the transport and CSRF layer and
//  says nothing whatsoever about whether the credentials were any good.
//
//  Every classification rule in this app since Phase 2 keys on that field. A
//  client that reuses it and stops there reports **every wrong password as a
//  successful sign-in**, stores a bad credential, and starts sending a customer
//  id it does not have. The answer is one level down, in `body.result.success`,
//  and its **absence must never read as success**.
//
//  ## Everything optional, deliberately
//
//  The failure body has been captured in full. The **success** body never has.
//  So every field here is optional and every absence has a defined behaviour,
//  and this decode is deliberately *not* tightened on the strength of the field
//  names the failure body revealed — those names are known, their populated
//  shapes are not, and a decoder written to them would be a decoder written to
//  a guess.
//

import Foundation

// MARK: - The request

nonisolated struct SignInRequestBody: Encodable, Sendable {

    let loginName: String
    let password: String

    // Copied verbatim from the capture. Strings, not JSON booleans, and the
    // casing differs between them on purpose — do not normalise this block.
    static let signInSourceApp = "0"
    static let customAmount = "False"
    static let fromOriginalCUI = "true"
    static let locale = "en-US"
    static let onlineSiteID = "5"
    static let overridePartialError = "False"

    /// Base64 of the page the *web UI* wants to land on after signing in:
    /// `.../ActiveNet_Home?FileName=accountoptions.sdi&fromLoginPage=true`.
    ///
    /// It carries no authentication meaning, and an app has no equivalent
    /// destination. Whether it is required at all is unknown, so it is sent as
    /// a constant exactly as captured — not derived, not omitted, not
    /// experimented with. An experiment here costs an attempt.
    static let params =
        "aHR0cHM6Ly9hcG0uYWN0aXZlY29tbXVuaXRpZXMuY29tL3djc2NwYXJrc2FuZHJlYy9BY3Rpdm"
        + "VOZXRfSG9tZT9GaWxlTmFtZT1hY2NvdW50b3B0aW9ucy5zZGkmZnJvbUxvZ2luUGFnZT10cnVl"

    enum CodingKeys: String, CodingKey {
        case loginName = "login_name"
        case password
        case signInSourceApp = "signin_source_app"
        case customAmount = "custom_amount"
        case fromOriginalCUI = "from_original_cui"
        case locale
        case onlineSiteID = "onlineSiteId"
        case overridePartialError = "override_partial_error"
        case params
        case akProperties = "ak_properties"
    }

    /// `ak_properties` is encoded as an explicit null rather than omitted, for
    /// the same reason the availability request keeps its null time bounds: the
    /// captured payload has the key, and this is not an endpoint worth
    /// discovering the difference on.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(loginName, forKey: .loginName)
        try container.encode(password, forKey: .password)
        try container.encode(Self.signInSourceApp, forKey: .signInSourceApp)
        try container.encode(Self.customAmount, forKey: .customAmount)
        try container.encode(Self.fromOriginalCUI, forKey: .fromOriginalCUI)
        try container.encode(Self.locale, forKey: .locale)
        try container.encode(Self.onlineSiteID, forKey: .onlineSiteID)
        try container.encode(Self.overridePartialError, forKey: .overridePartialError)
        try container.encode(Self.params, forKey: .params)
        try container.encodeNil(forKey: .akProperties)
    }
}

// MARK: - An id that may arrive spelled either way

/// A number that the API might send as a number or as a string.
///
/// It sends string-typed booleans; assuming its ids are typed consistently is
/// not a bet worth taking, and the tolerant decode costs a few lines. Anything
/// that is neither yields no id, which resolves to anonymous — the safe
/// direction.
nonisolated struct FlexibleID: Decodable, Sendable, Equatable {

    let value: Int?

    init(value: Int?) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Int.self) {
            value = number
            return
        }

        if let text = try? container.decode(String.self) {
            value = Int(text.trimmingCharacters(in: .whitespaces))
            return
        }

        value = nil
    }
}

// MARK: - The reply

nonisolated struct SignInEnvelope: Decodable, Sendable {
    let headers: ResponseHeaders
    let body: SignInBody?
}

nonisolated struct SignInBody: Decodable, Sendable {
    let result: SignInResult?
}

/// What the sign-in actually did, one level below the envelope.
nonisolated struct SignInResult: Decodable, Sendable {

    /// The field that decides everything. **Absence is not success.**
    let success: Bool?

    /// Decoded so its presence can be recorded, and never carried out of this
    /// layer. It is written by a third party for the website's own users, and
    /// it omits the only thing that matters here — that trying again has a
    /// cost. The app writes its own sentence instead.
    let message: String?

    let needVerifyRecaptcha: Bool?

    /// The identity, straight from the sign-in reply. This supersedes the
    /// earlier hypothesis that a second call would be needed to learn it.
    let publicCustomerID: FlexibleID?

    /// A nested object that may also carry an id. Tried as a fallback and no
    /// further.
    let customer: SignInCustomer?

    /// Recorded as present-or-absent and deliberately unused. Using an
    /// unverified token scheme would be guessing.
    let accessToken: String?
    let refreshToken: String?
    let signInTokenID: String?
    let securitySignToken: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case needVerifyRecaptcha = "need_verify_recaptcha"
        case publicCustomerID = "public_customer_id"
        case customer
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case signInTokenID = "sign_in_token_id"
        case securitySignToken = "security_sign_token"
    }

    /// Every field is read with `try?`, so one surprising type cannot fail the
    /// whole decode and turn a readable reply into an unreadable one. The
    /// success body has never been seen; this has to survive shapes nobody has
    /// described.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        success = (try? container.decodeIfPresent(Bool.self, forKey: .success)) ?? nil
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? nil
        needVerifyRecaptcha =
            (try? container.decodeIfPresent(Bool.self, forKey: .needVerifyRecaptcha)) ?? nil
        publicCustomerID =
            (try? container.decodeIfPresent(FlexibleID.self, forKey: .publicCustomerID)) ?? nil
        customer = (try? container.decodeIfPresent(SignInCustomer.self, forKey: .customer)) ?? nil
        accessToken = (try? container.decodeIfPresent(String.self, forKey: .accessToken)) ?? nil
        refreshToken = (try? container.decodeIfPresent(String.self, forKey: .refreshToken)) ?? nil
        signInTokenID = (try? container.decodeIfPresent(String.self, forKey: .signInTokenID)) ?? nil
        securitySignToken =
            (try? container.decodeIfPresent(String.self, forKey: .securitySignToken)) ?? nil
    }

    /// The id to use, from the reply's own field first and the nested object
    /// second.
    ///
    /// Zero is rejected: it is the value that *means* anonymous on the
    /// availability request, so a reply carrying it has not given the app an
    /// identity, whatever it thinks it did.
    var usableCustomerID: Int? {
        for candidate in [publicCustomerID?.value, customer?.customerID?.value, customer?.id?.value]
        {
            if let candidate, candidate != 0 { return candidate }
        }

        return nil
    }
}

nonisolated struct SignInCustomer: Decodable, Sendable {

    let customerID: FlexibleID?
    let id: FlexibleID?

    enum CodingKeys: String, CodingKey {
        case customerID = "customer_id"
        case id
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        customerID = (try? container.decodeIfPresent(FlexibleID.self, forKey: .customerID)) ?? nil
        id = (try? container.decodeIfPresent(FlexibleID.self, forKey: .id)) ?? nil
    }
}

// MARK: - What the reply meant

/// Four outcomes, not a boolean.
///
/// The last two are genuinely different, and collapsing them into "it worked"
/// is how an app ends up sending a customer id it does not have.
nonisolated enum SignInOutcome: Equatable, Sendable {

    /// The credentials were refused. Carries nothing — there is nothing in it
    /// the user should read that the app cannot say better itself.
    case rejected

    /// The service wants a human-verification challenge this app cannot show.
    case captchaRequired

    /// It worked, and handed back an id to use.
    case signedIn(customerID: Int)

    /// It worked, and handed back nothing usable. The app stays anonymous and
    /// says so — which is the correct behaviour anyway, since anonymous is the
    /// state proven to work for all 80 courts.
    case succeededWithoutIdentity
}

extension SignInResult {

    /// Reads the outcome from the inner result alone.
    ///
    /// **Rejection outranks the captcha flag**, and that ordering is forced by
    /// the evidence rather than chosen: the one captured rejection carries
    /// `need_verify_recaptcha: true` *alongside* `success: false` and a message
    /// naming the credentials. The flag there describes what the server wants
    /// next time, not why this attempt failed.
    ///
    /// So the captcha outcome is reserved for a refusal that demands
    /// verification while naming no reason — the shape a pure challenge would
    /// have. Only the *presence* of the message is read, never its text, which
    /// is the same distinction the whole file keeps: structure is a signal,
    /// prose is a liability.
    var outcome: SignInOutcome {
        guard success == true else {
            if needVerifyRecaptcha == true && message == nil {
                return .captchaRequired
            }

            return .rejected
        }

        if let id = usableCustomerID {
            return .signedIn(customerID: id)
        }

        return .succeededWithoutIdentity
    }
}
