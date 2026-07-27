//
//  SignInWireTests.swift
//  CourtWatchTests
//
//  **The single assertion that matters most in this phase is in this file**:
//  the real captured failure body, whose envelope says `"0000" Successful`,
//  must classify as a rejection.
//
//  Without it, a client that reuses the app's existing envelope rule reports
//  every wrong password as a successful sign-in — telling the user they are
//  signed in when they are not, storing a credential the service just refused,
//  and sending a customer id it does not have.
//
//  The request is asserted against the **encoded bytes**, not against a
//  round-trip. A round-trip through the same type passes whatever spelling that
//  type happens to use, including the wrong one.
//
//  Nothing here contacts anything. Every payload is a string in this file, and
//  no test names the sign-in endpoint.
//

import Foundation
import Testing

@testable import CourtWatch

/// The rejection captured from a single deliberately-wrong-password probe,
/// verbatim. It is the only true example of this endpoint's failure anyone has.
///
/// Note `response_code: "0000"` beside `success: false`, and note that
/// `need_verify_recaptcha` is **already true** here — which is why a captcha
/// cannot be told from a refusal by that flag alone.
private nonisolated let capturedRejection = """
    {
      "headers": {
        "sessionRefreshedOn": null,
        "sessionExtendedCount": 0,
        "response_code": "0000",
        "response_message": "Successful"
      },
      "body": {
        "result": {
          "success": false,
          "message": "Invalid login name or password",
          "error_type": 0,
          "redirect_url": null,
          "security_sign_token": null,
          "public_customer_id": null,
          "sign_in_token_id": null,
          "customer": null,
          "access_token": null,
          "refresh_token": null,
          "ak_update_succeed": false,
          "enable_gpap": false,
          "need_verify_recaptcha": true
        }
      }
    }
    """

private nonisolated func decodedResult(_ json: String) throws -> SignInResult {
    let envelope = try JSONDecoder().decode(SignInEnvelope.self, from: Data(json.utf8))

    return try #require(envelope.body?.result)
}

private nonisolated func encodedRequest() throws -> [String: Any] {
    let body = SignInRequestBody(loginName: "someone@example.invalid", password: "unused-in-this-test")
    let data = try JSONEncoder().encode(body)
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

    return try #require(object as? [String: Any])
}

struct SignInWireTests {

    // MARK: - The request, asserted against the bytes

    @Test("The encoded request carries all ten captured fields")
    func encodesEveryCapturedField() throws {
        let body = try encodedRequest()

        #expect(
            Set(body.keys) == [
                "login_name", "password", "signin_source_app", "custom_amount",
                "from_original_cui", "locale", "onlineSiteId", "override_partial_error",
                "params", "ak_properties",
            ])
        #expect(body.keys.count == 10)
    }

    /// The booleans are strings, and their casing differs between fields. This
    /// looks like a mistake and is a transcription of what was captured.
    @Test("The string-typed booleans keep their captured spelling")
    func stringBooleansKeepTheirCasing() throws {
        let body = try encodedRequest()

        #expect(body["custom_amount"] as? String == "False")
        #expect(body["override_partial_error"] as? String == "False")
        #expect(body["from_original_cui"] as? String == "true")

        // Strings, emphatically not JSON booleans.
        #expect(body["custom_amount"] is Bool == false)
        #expect(body["from_original_cui"] is Bool == false)
        #expect(body["override_partial_error"] is Bool == false)
    }

    /// Asserted on the raw text as well, because `JSONSerialization` would
    /// happily read `true` and `"true"` into values that compare the same way
    /// if the expectation were sloppier.
    @Test("The raw JSON text quotes the string booleans")
    func rawTextQuotesTheStringBooleans() throws {
        let data = try JSONEncoder().encode(
            SignInRequestBody(loginName: "someone@example.invalid", password: "unused"))
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("\"custom_amount\":\"False\""))
        #expect(text.contains("\"from_original_cui\":\"true\""))
        #expect(text.contains("\"override_partial_error\":\"False\""))
        #expect(text.contains("\"custom_amount\":false") == false)
        #expect(text.contains("\"from_original_cui\":true") == false)
    }

    @Test("The remaining constants are the captured ones")
    func constantsAreTheCapturedOnes() throws {
        let body = try encodedRequest()

        #expect(body["signin_source_app"] as? String == "0")
        #expect(body["locale"] as? String == "en-US")
        #expect(body["onlineSiteId"] as? String == "5")
    }

    /// Present and null, not absent — the same rule the availability request
    /// follows for its unused time bounds.
    @Test("ak_properties is an explicit null rather than an omitted key")
    func akPropertiesIsExplicitlyNull() throws {
        let body = try encodedRequest()

        #expect(body.keys.contains("ak_properties"))
        #expect(body["ak_properties"] is NSNull)
    }

    @Test("The credential reaches the body under the captured key names")
    func credentialIsCarriedUnderTheCapturedKeys() throws {
        let data = try JSONEncoder().encode(
            SignInRequestBody(loginName: "someone@example.invalid", password: "MARKER_PW"))
        let body = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["login_name"] as? String == "someone@example.invalid")
        #expect(body["password"] as? String == "MARKER_PW")
    }

    /// `params` is base64 of the web UI's post-login destination, sent as a
    /// constant. Decoded here so a mistyped constant cannot pass unnoticed.
    @Test("params is the captured redirect, unmodified")
    func paramsIsTheCapturedRedirect() throws {
        let body = try encodedRequest()
        let encoded = try #require(body["params"] as? String)
        let decoded = String(
            decoding: try #require(Data(base64Encoded: encoded)), as: UTF8.self)

        #expect(decoded.contains("ActiveNet_Home"))
        #expect(decoded.contains("FileName=accountoptions.sdi"))
        #expect(decoded.contains("fromLoginPage=true"))
    }

    // MARK: - The trap

    /// **The assertion this whole file exists for.**
    ///
    /// The envelope says the request succeeded. The sign-in did not. A client
    /// that stopped at the envelope would call this a successful login.
    @Test("The real captured rejection is a rejection, despite its 0000 envelope")
    func capturedRejectionIsNotASuccess() throws {
        let envelope = try JSONDecoder().decode(
            SignInEnvelope.self, from: Data(capturedRejection.utf8))

        // The outer layer really does say Successful — this is not a
        // hypothetical.
        #expect(envelope.headers.responseCode == "0000")
        #expect(ResponseCode.classify(envelope.headers) == .success)

        // And the answer is somewhere else entirely.
        let result = try #require(envelope.body?.result)

        #expect(result.success == false)
        #expect(result.outcome == .rejected)
        #expect(result.usableCustomerID == nil)
    }

    /// Its mirror: absence must not read as success either. A reply that has
    /// simply lost the field is not a licence to believe anything.
    @Test("A reply with no success field is not a success")
    func missingSuccessIsNotSuccess() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"message":null}}}
            """)

        #expect(result.success == nil)
        #expect(result.outcome == .rejected)

        if case .signedIn = result.outcome {
            Issue.record("a reply with no success field was read as a sign-in")
        }
    }

    /// An empty result object is the same story with nothing in it at all.
    @Test("An empty result object is not a success")
    func emptyResultIsNotSuccess() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{}}}
            """)

        #expect(result.outcome == .rejected)
    }

    // MARK: - The four outcomes

    /// The captcha case is a refusal that demands verification while naming no
    /// reason. It cannot be told apart by the flag alone, because the captured
    /// rejection carries the flag too — which is the whole reason this
    /// distinction is written down rather than assumed.
    @Test("A refusal that names no reason but wants verification is the captcha case")
    func captchaIsItsOwnOutcome() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":false,
            "message":null,"need_verify_recaptcha":true}}}
            """)

        #expect(result.outcome == .captchaRequired)
        #expect(result.outcome != .rejected)
    }

    /// And the ordering that protects it: a refusal that *does* name a reason
    /// is a refusal, flag or no flag.
    @Test("A named refusal outranks the captcha flag")
    func namedRefusalOutranksTheFlag() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":false,
            "message":"Invalid login name or password","need_verify_recaptcha":true}}}
            """)

        #expect(result.outcome == .rejected)
    }

    @Test("A success carrying an id yields a signed-in outcome")
    func successWithIdentity() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":4471056}}}
            """)

        #expect(result.outcome == .signedIn(customerID: 4_471_056))
    }

    @Test("A success carrying no id leaves the app without one")
    func successWithoutIdentity() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":null}}}
            """)

        #expect(result.outcome == .succeededWithoutIdentity)
    }

    /// The four are four. Collapsing any pair is how the app ends up either
    /// lying about being signed in or sending an id it does not have.
    @Test("The four outcomes are pairwise distinct")
    func outcomesArePairwiseDistinct() {
        let all: [SignInOutcome] = [
            .rejected, .captchaRequired, .signedIn(customerID: 4_471_056),
            .succeededWithoutIdentity,
        ]

        for (index, first) in all.enumerated() {
            for second in all[(index + 1)...] {
                #expect(first != second, "\(first) collides with \(second)")
            }
        }
    }

    // MARK: - An id spelled either way

    /// The API sends string-typed booleans. Assuming its ids are typed
    /// consistently is not a bet worth taking.
    @Test(
        "A customer id decodes from a number or from a string",
        arguments: ["4471056", "\"4471056\"", "\" 4471056 \""]
    )
    func customerIDDecodesEitherSpelling(literal: String) throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":\(literal)}}}
            """)

        #expect(result.outcome == .signedIn(customerID: 4_471_056))
    }

    /// An id that is neither yields no identity rather than a wrong one.
    @Test(
        "An unreadable id yields no identity rather than a guess",
        arguments: ["\"not-a-number\"", "{}", "[]", "true", "null", "0", "\"0\""]
    )
    func unreadableIDYieldsNothing(literal: String) throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":\(literal)}}}
            """)

        #expect(result.usableCustomerID == nil)
        #expect(result.outcome == .succeededWithoutIdentity)
    }

    /// The nested object is a fallback and no further.
    @Test("A customer id nested in the customer object is used as a fallback")
    func nestedCustomerIDIsAFallback() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":null,"customer":{"customer_id":"991234"}}}}
            """)

        #expect(result.outcome == .signedIn(customerID: 991_234))
    }

    /// The reply's own field wins when both are present.
    @Test("The reply's own id outranks the nested one")
    func ownIDOutranksNested() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":4471056,"customer":{"customer_id":991234}}}}
            """)

        #expect(result.outcome == .signedIn(customerID: 4_471_056))
    }

    // MARK: - Tolerance

    /// The success body has never been captured, so a surprising type in one
    /// field must not turn a readable reply into an unreadable one.
    @Test(
        "One field of an unexpected type does not fail the whole decode",
        arguments: [
            #""message":{"nested":"object"}"#,
            #""access_token":12345"#,
            #""customer":"a string where an object was expected""#,
            #""need_verify_recaptcha":"true""#,
        ]
    )
    func oneOddFieldDoesNotBreakTheDecode(field: String) throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":4471056,\(field)}}}
            """)

        #expect(result.outcome == .signedIn(customerID: 4_471_056))
    }

    /// Unknown fields are ignored rather than fatal — this endpoint is
    /// unversioned and may grow keys at any time.
    @Test("Unknown fields are ignored")
    func unknownFieldsAreIgnored() throws {
        let result = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":4471056,"a_field_from_the_future":{"deeply":["nested"]}}}}
            """)

        #expect(result.outcome == .signedIn(customerID: 4_471_056))
    }

    /// The tokens are decoded so their presence can be recorded, and are used
    /// for nothing. Pinned so that "we may as well use it" has to be a
    /// deliberate edit rather than a drift.
    @Test("The tokens are read but reach no outcome")
    func tokensAreRecordedNotUsed() throws {
        let withTokens = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":4471056,"access_token":"MARKER_ACCESS",
            "refresh_token":"MARKER_REFRESH","sign_in_token_id":"MARKER_SIGNIN"}}}
            """)

        let withoutTokens = try decodedResult(
            """
            {"headers":{"response_code":"0000","response_message":"Successful",
            "sessionRefreshedOn":null},"body":{"result":{"success":true,
            "public_customer_id":4471056}}}
            """)

        #expect(withTokens.accessToken == "MARKER_ACCESS")
        #expect(withTokens.outcome == withoutTokens.outcome)
    }
}
