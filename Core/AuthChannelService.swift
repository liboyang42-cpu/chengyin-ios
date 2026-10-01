import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AuthChannelError: Error, Equatable {
    case invalidPhone, invalidCode, invalidAppleCredential, rateLimited
}

/// Pure source-backed validation. The source phone sheet accepts exactly eleven ASCII
/// digits and up to six numeric code digits. Backend validation remains authoritative.
public enum AuthChannelInput {
    public static func phone(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.utf8.count == 11, result.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw AuthChannelError.invalidPhone
        }
        return result
    }
    public static func code(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...6).contains(result.utf8.count), result.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw AuthChannelError.invalidCode
        }
        return result
    }
}

@MainActor
public protocol AuthChannelServing {
    func sendSMSCode(phone: String) async throws
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult
    func loginWithApple(identityToken: String) async throws -> LoginResult
    func currentAccount(token: String) async throws -> Account
}

/// No retries, persistence, OAuth launch, production defaults or diagnostic credential
/// logging. Every mutation is called only by an explicit user action in the coordinator.
public struct AuthChannelService: AuthChannelServing {
    private let builder: AuthRequestBuilder
    private let transport: any HTTPTransport
    private let auth: AuthService
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        builder = AuthRequestBuilder(configuration: configuration)
        self.transport = transport
        auth = AuthService(configuration: configuration, transport: transport)
    }
    private struct Envelope: Decodable {
        let code: Int
        let token: String?
        let data: Account?
    }
    private struct StatusEnvelope: Decodable { let code: Int }
    private func execute(_ endpoint: AuthEndpoint, fields: [String: String]) async throws -> Data {
        try Task.checkCancellation()
        let request = try builder.make(endpoint, fields: fields)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 429 { throw AuthChannelError.rateLimited }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let body: StatusEnvelope
        do { body = try JSONDecoder().decode(StatusEnvelope.self, from: data) }
        catch { throw APIError.malformedResponse }
        if body.code == 401 { throw APIError.unauthorized }
        if body.code == 429 { throw AuthChannelError.rateLimited }
        guard body.code == 200 else { throw APIError.businessCode(body.code) }
        return data
    }
    public func sendSMSCode(phone: String) async throws {
        _ = try await execute(.smsSend, fields: ["phone": AuthChannelInput.phone(phone)])
    }
    public func loginWithPhone(phone: String, code: String) async throws -> LoginResult {
        try await login(.phone, fields: ["phone": AuthChannelInput.phone(phone), "code": AuthChannelInput.code(code)])
    }
    public func loginWithApple(identityToken: String) async throws -> LoginResult {
        // The opaque Apple credential is exchanged with the existing backend. This is
        // transport validation only, never a claim that the JWT signature was verified.
        guard AuthRequestBuilder.isValidToken(identityToken) else { throw AuthChannelError.invalidAppleCredential }
        return try await login(.apple, fields: ["identityToken": identityToken])
    }
    private func login(_ endpoint: AuthEndpoint, fields: [String: String]) async throws -> LoginResult {
        let data = try await execute(endpoint, fields: fields)
        let body: Envelope
        do { body = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw APIError.malformedResponse }
        guard let token = body.token, AuthRequestBuilder.isValidToken(token),
              let account = body.data, account.id > 0 else { throw APIError.malformedResponse }
        return LoginResult(token: token, account: account)
    }
    public func currentAccount(token: String) async throws -> Account {
        try Task.checkCancellation()
        let result = try await auth.currentAccount(token: token)
        try Task.checkCancellation()
        return result
    }
}
