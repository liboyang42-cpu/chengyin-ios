import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact public wire adapter only. No CN service, provider HTTP, credentials, or fallback.
@MainActor
public final class USAppleService: USAppleServing {
    private let deployment: USAppleDeployment
    private let transport: any HTTPTransport
    private var admitted = USAppleProductionGate.enabled
    public init(deployment: USAppleDeployment, transport: any HTTPTransport) {
        self.deployment = deployment; self.transport = transport
    }
    #if DEBUG
    /// Internal fixture seam. Tests MUST supply an offline transport; absent from Release.
    convenience init(offlineDeployment: USAppleDeployment, transport: any HTTPTransport) {
        self.init(deployment: offlineDeployment, transport: transport)
        admitted = true
    }
    #endif

    private struct Status: Decodable { let code: Int; let errorCode: String? }
    private struct ChallengeEnvelope: Decodable { let data: USAppleChallenge }
    private struct ExchangeBody: Encodable { let challengeId: String; let state: String; let identityToken: String }
    private struct SafeProfile: Codable {
        let id: Int
        let userType: Int
        let avatar: String
        let nickname: String
        let role: String
        private enum CodingKeys: String, CodingKey { case id, userType, avatar, nickname, role }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(Int.self, forKey: .id)
            userType = try values.decode(Int.self, forKey: .userType)
            // Null is a valid absent avatar. A missing key or another JSON type is not.
            guard values.contains(.avatar) else {
                throw DecodingError.keyNotFound(CodingKeys.avatar,
                    .init(codingPath: values.codingPath, debugDescription: "Missing safe profile field"))
            }
            avatar = try values.decodeIfPresent(String.self, forKey: .avatar) ?? ""
            nickname = try values.decode(String.self, forKey: .nickname)
            role = try values.decode(String.self, forKey: .role)
        }
    }
    private struct ExchangeEnvelope: Decodable {
        let token: String
        let market: String
        let data: SafeProfile
    }

    private struct SessionEnvelope: Decodable {
        let data: SessionProof
    }
    private struct SessionProof: Decodable {
        let market: String
        let realm: String
        let account: SafeProfile
    }

    private func execute(path: String, body: Data) async throws -> Data {
        guard admitted else { throw USAppleError.unavailable }
        try Task.checkCancellation()
        var request = URLRequest(url: deployment.origin.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        // Deliberately no Authorization, Cookie, device ID, locale, market or realm header.
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 65_536,
              let envelope = try? JSONDecoder().decode(Status.self, from: data), envelope.code == status else {
            throw USAppleClientError.invalidResponse
        }
        if status != 200 {
            guard let code = envelope.errorCode, let error = USAppleError(rawValue: code), error.httpStatus == status else {
                throw USAppleClientError.invalidResponse
            }
            throw error
        }
        guard envelope.errorCode == nil else { throw USAppleClientError.invalidResponse }
        return data
    }
    public func challenge() async throws -> USAppleChallenge {
        let data = try await execute(path: "api/us/auth/apple/challenges", body: Data("{}".utf8))
        guard let response = try? JSONDecoder().decode(ChallengeEnvelope.self, from: data) else {
            throw USAppleClientError.invalidResponse
        }
        try response.data.validate()
        return response.data
    }
    public func exchange(challengeId: String, state: String, identityToken: String) async throws -> LoginResult {
        guard admitted else { throw USAppleError.unavailable }
        guard USAppleValidation.isRandomValue(challengeId), USAppleValidation.isRandomValue(state),
              USAppleValidation.isToken(identityToken) else { throw USAppleError.invalidRequest }
        let body = try JSONEncoder().encode(ExchangeBody(challengeId: challengeId, state: state, identityToken: identityToken))
        let data = try await execute(path: "api/us/auth/apple/exchange", body: body)
        guard let response = try? JSONDecoder().decode(ExchangeEnvelope.self, from: data),
              response.market == "US", USAppleValidation.isToken(response.token), response.data.id > 0 else {
            throw USAppleClientError.invalidResponse
        }
        // Re-encode only the five allowlisted profile fields; never import arbitrary account fields.
        let account = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(response.data))
        return LoginResult(token: response.token, account: account)
    }

    /// Protected post-exchange proof. Pass only the fresh candidate returned by this US
    /// exchange; never load a CN credential. No realm/account override is sent or echoed.
    /// The coordinator must still compare account ID with the exchange before persistence.
    public func currentAccount(token: String) async throws -> USAppleVerifiedCurrentAccount {
        guard admitted else { throw USAppleError.unavailable }
        guard USAppleValidation.isToken(token) else { throw USAppleError.invalidRequest }
        try Task.checkCancellation()
        var request = URLRequest(url: deployment.origin.appendingPathComponent("api/us/auth/session"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        // No query/body, Cookie, client-realm header, account ID or provider identity.
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 65_536 else { throw USAppleClientError.invalidResponse }
        // The security filter can issue generic 401 without an errorCode or JSON envelope.
        // Translate to the existing local rejected-identity outcome; never accept evidence.
        if status == 401 { throw USAppleError.invalidIdentity }
        guard let envelope = try? JSONDecoder().decode(Status.self, from: data), envelope.code == status else {
            throw USAppleClientError.invalidResponse
        }
        if status == 503,
           envelope.errorCode == "US_SESSION_UNAVAILABLE" || envelope.errorCode == USAppleError.unavailable.rawValue {
            throw USAppleError.unavailable
        }
        guard status == 200, envelope.errorCode == nil,
              let response = try? JSONDecoder().decode(SessionEnvelope.self, from: data),
              response.data.market == "US", response.data.realm == deployment.realm,
              response.data.account.id > 0 else { throw USAppleClientError.invalidResponse }
        // Only the same five allowlisted fields cross into the native Account value.
        let account = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(response.data.account))
        return USAppleVerifiedCurrentAccount(account: account, market: .unitedStates, realm: response.data.realm)
    }
}
