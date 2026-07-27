//
//  SignInClient.swift
//  CourtWatch
//
//  Exchanges a credential for a session, then checks whether it worked.
//
//  ## Nothing here holds the credential
//
//  It arrives as a **parameter**, is encoded into the request body, and goes
//  out of scope. There is no property on this type that could retain it after
//  the call returns, which means there is nothing for a retry to resubmit —
//  a second attempt would have to re-prompt a human. That is the requirement
//  expressed as a type rather than as a rule someone has to remember, and it
//  matters because one wrong attempt arms a captcha on a real booking account.
//
//  ## Two layers, because the outer one lies
//
//  The envelope reports on transport and CSRF. It answers `"0000"` —
//  *Successful* — for a rejected password. So classification happens twice:
//  the outer step **delegates to the shared classifier**, because sign-in sits
//  behind the same handshake as everything else and a stale token here should
//  re-handshake exactly as it does anywhere; the inner step reads
//  `body.result.success` and decides what actually happened.
//
//  **That delegation is right here and wrong one file over.** The session check
//  must not do it, because `"0021"` means "stale session" on the availability
//  endpoint and "not signed in" on that one. This instruction does not
//  generalise past this POST.
//
//  ## And then it distrusts the answer
//
//  A reported success is **confirmed** before the app believes it. The success
//  body has never been captured, so every belief formed from it is a belief
//  about an unverified shape — including the one belief this could get
//  catastrophically wrong. The session check's two answers were both measured,
//  it needs no credential, and it costs one cheap GET on a path the user just
//  deliberately triggered.
//
//  The confirmation looks redundant next to a body that already said
//  `success: true`. That appearance is exactly what it is there to distrust.
//

import Foundation

nonisolated struct SignInClient: Sendable {

    static let endpoint = URL(
        string: "https://anc.apm.activecommunities.com/wcscparksandrec"
            + "/rest/user/signin?locale=en-US")!

    private let session: CourtSession
    private let probe: SessionProbe

    init(session: CourtSession) {
        self.session = session
        self.probe = SessionProbe(session: session)
    }

    init(session: CourtSession, probe: SessionProbe) {
        self.session = session
        self.probe = probe
    }

    /// Takes the credential, uses it once, and keeps none of it.
    func signIn(as credentials: Credentials) async throws -> SignInOutcome {
        let payload = try JSONEncoder().encode(
            SignInRequestBody(
                loginName: credentials.username, password: credentials.password))

        // One re-handshake and one replay, the same bound the availability
        // path keeps and for the same WAF-facing reason.
        var attempt = 0

        while true {
            attempt += 1

            let token = try await session.token()
            let transport = await session.currentTransport()

            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            request.setValue("court-watch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await transport.send(request)

            let envelope: SignInEnvelope
            do {
                envelope = try JSONDecoder().decode(SignInEnvelope.self, from: data)
            } catch {
                // A block page and a schema change are two different failures
                // and neither is a rejection — so neither invites a retry with
                // a credential attached.
                guard AvailabilityClient.looksLikeJSON(data) else {
                    throw APIError.notJSON
                }

                throw APIError.decoding(String(describing: error))
            }

            switch ResponseCode.classify(envelope.headers) {
            case .success:
                guard let result = envelope.body?.result else {
                    // The envelope was fine and there was nothing inside it.
                    // That is not a rejection and must never read as success.
                    throw APIError.decoding("sign-in reply carried no result")
                }

                #if DEBUG
                    SignInShapeRecorder.record(
                        data, producedIdentity: result.usableCustomerID != nil)
                #endif

                return await confirmed(result.outcome)

            case .expired(let code):
                guard attempt == 1 else {
                    throw APIError.sessionExpired(code: code)
                }

                await session.invalidate()

            case .service(let code, let text):
                throw APIError.service(code: code, message: text)
            }
        }
    }

    /// A reported success only counts if the endpoint whose answers are
    /// measured agrees. If it does not, the app is not signed in, whatever the
    /// body claimed — and the safe direction is anonymous.
    private func confirmed(_ outcome: SignInOutcome) async -> SignInOutcome {
        guard case .signedIn = outcome else { return outcome }

        return await probe.check() == .authenticated ? outcome : .succeededWithoutIdentity
    }
}

/// The seam the account state is built against.
///
/// One method, taking what it needs and returning what it found. Note what is
/// *not* on it: nothing to store a credential in, and nothing to ask it to try
/// again. A conforming type could not offer an automatic retry without changing
/// this shape.
nonisolated protocol SignInPerforming: Sendable {
    func signIn(as credentials: Credentials) async throws -> SignInOutcome
}

extension SignInClient: SignInPerforming {}
