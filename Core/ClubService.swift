import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only source-backed read routes. No default host or URLSession is constructed here.
public struct ClubService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func home(token: String? = nil) async throws -> ClubHome {
        let data = try await post("api/club/home", json: [:], token: token)
        return try decode(ClubValueEnvelope<ClubHome>.self, data).data
    }
    public func owned(token: String) async throws -> [ClubRecord] {
        let data = try await post("api/club/my", json: [:], token: token)
        return try decode(ClubValueEnvelope<ClubOwnedPayload>.self, data).data.owned
    }
    public func directory(name: String? = nil, token: String? = nil) async throws -> [ClubRecord] {
        let data: Data
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The source list binds an optional JSON Club body for both filtered and unfiltered reads.
            data = try await post("api/club/list", json: ["name": name], token: token)
        } else {
            data = try await post("api/club/list", json: [:], token: token)
        }
        return try decode(ClubValueEnvelope<[ClubRecord]>.self, data).data
    }
    public func detail(id: Int, token: String? = nil) async throws -> ClubRecord {
        guard id > 0 else { throw APIError.invalidRequest }
        let data = try await post("api/club/detail", json: ["id": id], token: token)
        let club = try decode(ClubValueEnvelope<ClubRecord>.self, data).data
        guard club.id == id else { throw APIError.malformedResponse }
        return club
    }
    /// Call with a freshly fetched detail from this credential; the session reader enforces it.
    public func members(in club: ClubRecord, token: String) async throws -> [ClubMember] {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        guard club.canSeeMembers else { throw ClubReadFailure.membershipRequired }
        let data = try await post("api/club/members", json: ["clubId": club.id], token: token)
        return try decode(ClubValueEnvelope<[ClubMember]>.self, data).data
    }
    private func post(_ path: String, json: [String: Any], token: String?) async throws -> Data {
        var request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token, includesBody: false)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        let message = (try? JSONDecoder().decode(ClubServerMessage.self, from: data))?.msg
        if status == 401 { throw ClubReadFailure.unauthorized(message: message) }
        if status == 403 { throw ClubReadFailure.forbidden(message: message) }
        guard (200..<300).contains(status) else { throw ClubReadFailure.httpStatus(status, message: message) }
        let envelope = try decode(ClubStatusEnvelope.self, data)
        if envelope.code == 401 { throw ClubReadFailure.unauthorized(message: envelope.msg) }
        if envelope.code == 403 { throw ClubReadFailure.forbidden(message: envelope.msg) }
        guard envelope.code == 200 else { throw ClubReadFailure.rejected(code: envelope.code, message: envelope.msg) }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw APIError.malformedResponse }
    }
}

private struct ClubServerMessage: Decodable {
    let msg: String?
    enum CodingKeys: String, CodingKey { case msg }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        msg = try? c.decode(String.self, forKey: .msg)
    }
}
private struct ClubStatusEnvelope: Decodable {
    let code: Int
    let msg: String?
    enum CodingKeys: String, CodingKey { case code, msg }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(Int.self, forKey: .code)
        // A malformed optional message cannot hide a server authentication decision.
        msg = try? c.decode(String.self, forKey: .msg)
    }
}
private struct ClubValueEnvelope<T: Decodable>: Decodable { let data: T }
private struct ClubOwnedPayload: Decodable {
    let owned: [ClubRecord]
    enum CodingKeys: String, CodingKey { case owned }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owned = try c.decodeIfPresent([ClubRecord].self, forKey: .owned) ?? []
    }
}
