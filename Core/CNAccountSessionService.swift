import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Existing CN session reads/revocation are independent of the password-entry channel.
/// This is not a US fallback: US requires its separately gated protected-proof contract.
public struct CNAccountSessionService {
    public let storageScope: RegionalSessionStorageScope
    private let auth: AuthService

    public init(configuration: RegionalConfiguration, storageScope: RegionalSessionStorageScope,
                transport: any HTTPTransport) throws {
        guard configuration.market == .china, storageScope.matches(configuration: configuration),
              let api = configuration.apiConfiguration,
              configuration.availability(of: .domesticChinaPhone) == .available else {
            throw APIError.notConfigured
        }
        self.storageScope = storageScope
        auth = AuthService(configuration: api, transport: transport)
    }

    /// Bodyless POST, raw Authorization, authoritative public appUser projection.
    /// A legacy cached projection without an explicit server role cannot restore a session.
    public func currentAccount(token: String) async throws -> Account {
        try Task.checkCancellation()
        let account = try await auth.currentAccount(token: token)
        guard ["player", "club", "merchant"].contains(account.role) else { throw APIError.malformedResponse }
        try Task.checkCancellation()
        return account
    }

    /// Best-effort remote revocation after the caller has already closed the local session.
    public func logout(token: String) async throws {
        try Task.checkCancellation()
        try await auth.logout(token: token)
        try Task.checkCancellation()
    }
}


extension CNAccountSessionService {
    /// Exact bounded wire shapes from the native SMS/session adapter. This is a transport
    /// allowlist, not provider readiness, authentication, a role grant, or attestation.
    public static func accepts(_ request: URLRequest, configuration: APIConfiguration) -> Bool {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let url = request.url, url.query == nil, url.fragment == nil else { return false }
        let token = request.value(forHTTPHeaderField: "Authorization")
        if url == configuration.url(for: .userInfo) {
            return token.map(AuthRequestBuilder.isValidToken) == true && request.httpBody == nil
                && request.value(forHTTPHeaderField: "Content-Type") == nil
        }
        let keys: Set<String>
        if url == configuration.url(for: .smsSend) { keys = ["phone"]; guard token == nil else { return false } }
        else if url == configuration.url(for: .phone) { keys = ["phone", "code"]; guard token == nil else { return false } }
        else if url == configuration.url(for: .logout) { keys = []; guard token.map(AuthRequestBuilder.isValidToken) == true else { return false } }
        else { return false }
        let prefix = "multipart/form-data; boundary="
        guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
              let body = request.httpBody, body.count <= 1024,
              let text = String(data: body, encoding: .utf8) else { return false }
        let boundary = String(type.dropFirst(prefix.count))
        var fields: [String: String] = [:]
        for key in keys {
            let marker = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n"
            guard let range = text.range(of: marker),
                  let end = text[range.upperBound...].range(of: "\r\n") else { return false }
            fields[key] = String(text[range.upperBound..<end.lowerBound])
        }
        if let phone = fields["phone"], (try? AuthChannelInput.phone(phone)) != phone { return false }
        if let code = fields["code"], (try? AuthChannelInput.code(code)) != code { return false }
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields,
            token: token, boundary: boundary) else { return false }
        // Byte equality rejects extra/duplicate fields, role/identity injection, alternate
        // framing, malformed boundaries, unbounded payloads and noncanonical encodings.
        return canonical.httpBody == body
    }
}
