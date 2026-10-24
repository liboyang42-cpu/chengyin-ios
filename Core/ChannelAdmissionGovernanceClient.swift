import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls the original admission routes. It does not use `api/native/spaces/admission`.
/// One request per action. A failed response does not mint another request id.
public struct ChannelAdmissionGovernanceClient {
    public static let pausePath = "api/space/join-pause"
    public static let revokePath = "api/invite/revoke"
    public static let receiptPrefix = "api/channel-platform/admission/requests/"

    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let token: String
    private let admission: ChannelRulesAdmission

    public init(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
                admission: ChannelRulesAdmission) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.configuration = configuration
        self.transport = transport
        self.token = token
        self.admission = admission
    }

    public func pause(kind: Int, spaceID: Int64, paused: Bool, until: String?, reason: String, requestID: String) async throws -> [String: Any] {
        try ready { try admission.pauseOriginal(kind: kind, spaceID: spaceID, paused: paused, until: until, reason: reason, requestID: requestID) }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = [
            "guild_kind": kind, "guild_id": spaceID, "paused": paused, "reason": trimmedReason, "request_id": requestID
        ]
        if paused, let until, !until.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["paused_until"] = until
        }
        let data = try await post(Self.pausePath, body)
        return try admission.pauseOriginal(kind: kind, spaceID: spaceID, paused: paused, until: until, reason: reason, requestID: requestID) {
            _, _, _, _, _, _, _ in data
        }
    }

    public func revokeInvite(inviteID: Int64, reason: String, requestID: String) async throws -> [String: Any] {
        try ready { try admission.revokeInviteOriginal(inviteID: inviteID, reason: reason, requestID: requestID) }
        let body: [String: Any] = [
            "invite_id": inviteID,
            "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
            "request_id": requestID
        ]
        let data = try await post(Self.revokePath, body)
        return try admission.revokeInviteOriginal(inviteID: inviteID, reason: reason, requestID: requestID) { _, _, _, _ in data }
    }

    public func recover(requestID: String) async throws -> [String: Any] {
        guard !requestID.contains("/"), requestID.range(of: "^[A-Za-z0-9:._-]{1,64}$", options: .regularExpression) != nil else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        let data = try await get(Self.receiptPrefix + requestID)
        return try admission.recoverOriginal(requestID: requestID) { _, _ in data }
    }

    private func ready(_ probe: () throws -> [String: Any]) throws {
        do {
            _ = try probe()
            throw APIError.invalidRequest
        } catch ChannelAuthorizationError.waitingSource {
            return
        }
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = try make(path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func get(_ path: String) async throws -> [String: Any] {
        var request = try make(path)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func make(_ path: String) throws -> URLRequest {
        let root = configuration.baseURL.absoluteString.hasSuffix("/")
            ? configuration.baseURL.absoluteString
            : configuration.baseURL.absoluteString + "/"
        guard let url = URL(string: root + path), url.host == configuration.baseURL.host else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = object?["code"] as? NSNumber, code.intValue == 200, let payload = object?["data"] as? [String: Any] else {
            throw APIError.malformedResponse
        }
        return payload
    }
}
