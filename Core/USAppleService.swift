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
    }
    private struct ExchangeEnvelope: Decodable {
        let token: String
        let market: String
        let data: SafeProfile
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
}
