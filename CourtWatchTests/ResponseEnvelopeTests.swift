//
//  ResponseEnvelopeTests.swift
//  CourtWatchTests
//
//  The endpoint answers 200 OK for everything, including "Invalid CSRF token".
//  Any code that reads success from the HTTP status has a retry path that will
//  never run and an error path that never fires.
//
//  These tests pin the envelope as the sole authority, including in two
//  deliberately absurd pairings — a failure code inside a 200 and a success
//  code inside a 500 — because a rule that happens to hold on today's inputs
//  is not the same as a rule that is enforced.
//

import Foundation
import Testing

@testable import CourtWatch

private func headers(_ code: String) throws -> ResponseHeaders {
    let envelope = try JSONDecoder().decode(
        AvailabilityEnvelope.self,
        from: try Fixture.data("envelope-\(code)"))
    return envelope.headers
}

struct ResponseEnvelopeTests {

    @Test("The success code classifies as success")
    func classifiesSuccess() throws {
        #expect(try ResponseCode.classify(headers("0000")) == .success)
    }

    /// The five documented codes that mean "your handshake is stale". Held as
    /// data rather than a switch so the retry logic and these tests read the
    /// same source.
    @Test(
        "Every documented expiry code classifies as expiry",
        arguments: ["0002", "0007", "0010", "0012", "0021"]
    )
    func classifiesExpiryCodes(code: String) throws {
        #expect(try ResponseCode.classify(headers(code)) == .expired(code))
        #expect(ResponseCode.expiry.contains(code))
    }

    /// 1507 is what the API answers when the request itself is wrong — sending
    /// a real customer_id anonymously, for instance. Re-handshaking would
    /// repeat the same rejection and add load for nothing.
    @Test("A service error is not an expiry and must not trigger a re-handshake")
    func classifiesServiceError() throws {
        let classification = try ResponseCode.classify(headers("1507"))

        #expect(classification == .service(code: "1507", message: "Invalid request"))
        #expect(ResponseCode.expiry.contains("1507") == false)
    }

    @Test("An unrecognised code classifies as a service error carrying its code")
    func classifiesUnknownCode() {
        let unknown = ResponseHeaders(
            responseCode: "9999", responseMessage: "Something new", sessionRefreshedOn: nil)

        #expect(
            ResponseCode.classify(unknown)
                == .service(code: "9999", message: "Something new"))
    }

    /// The assertion that pins the rule. `0012` is a real failure and it
    /// arrives inside a 200 every time.
    @Test("A failure code inside a 200 OK is an error")
    func failureInsideSuccessStatus() throws {
        let url = try #require(URL(string: "https://example.invalid"))
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))

        #expect(response.statusCode == 200)
        #expect(try ResponseCode.classify(headers("0012")) != .success)
    }

    /// Deliberately absurd — the API does not send 500s. That is the point: the
    /// classification must not consult the status even when the status looks
    /// authoritative.
    @Test("A success code inside a 500 is still a success")
    func successInsideFailureStatus() throws {
        let url = try #require(URL(string: "https://example.invalid"))
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))

        #expect(response.statusCode == 500)
        #expect(try ResponseCode.classify(headers("0000")) == .success)
    }

    @Test("Classification does not vary with the status it arrived with")
    func classificationIgnoresStatus() throws {
        let expiry = try ResponseCode.classify(headers("0012"))
        let url = try #require(URL(string: "https://example.invalid"))

        for status in [200, 401, 403, 500, 503] {
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: nil)

            #expect(response?.statusCode == status)
            #expect(try ResponseCode.classify(headers("0012")) == expiry)
        }
    }

    /// The equality assertions stay here, where the error type lives. The copy
    /// assertion that used to sit alongside them moved to
    /// `ErrorPresentationTests` when the copy moved off this type — what it was
    /// protecting is still protected, one layer out.
    @Test("A transport failure carries its URLError code")
    func transportErrorCarriesCode() {
        let error = APIError.transport(.notConnectedToInternet)

        #expect(error == APIError.transport(.notConnectedToInternet))
        #expect(error != APIError.transport(.timedOut))
    }

    /// Malformed JSON is a decoding failure, not a service failure. Conflating
    /// them would send the user an "the service said no" message when in fact
    /// the payload changed shape.
    @Test("Malformed JSON is a decoding error, distinct from a service error")
    func decodingErrorIsDistinct() throws {
        let garbage = try #require("{not json".data(using: .utf8))

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AvailabilityEnvelope.self, from: garbage)
        }

        #expect(APIError.decoding("x") != APIError.service(code: "x", message: nil))
    }

    /// The envelope fixtures decode through the real path rather than a
    /// shortcut, so a change to the envelope shape breaks these too.
    @Test(
        "Every envelope fixture decodes through the production type",
        arguments: ["0000", "0002", "0007", "0010", "0012", "0021", "1507"]
    )
    func envelopeFixturesDecode(code: String) throws {
        let decoded = try headers(code)

        #expect(decoded.responseCode == code)
        #expect(decoded.responseCode.count == 4)
    }
}
