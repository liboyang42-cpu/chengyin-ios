import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source-backed account reads; deployment approval is separate from endpoint implementation.
public struct SocialAccountService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) { self.configuration = configuration; self.transport = transport }
    public func profile(memberID: Int, token: String?) async throws -> SocialPublicProfile {
        guard memberID > 0 else { throw APIError.invalidRequest }
        let value: SocialPublicProfile = try await read("api/user/public-info", fields: ["member_id": String(memberID)], token: token)
        guard value.id == memberID else { throw APIError.malformedResponse }; return value
    }
    public func informationList(token: String? = nil) async throws -> [SocialInformation] {
        let rows: Rows<SocialInformation> = try await read("api/common/infomation_list", token: token, body: false)
        return rows.rows.filter(\.isUsable)
    }
    public func information(id: Int, token: String? = nil) async throws -> SocialInformation {
        guard id > 0 else { throw APIError.invalidRequest }
        let value: SocialInformation = try await read("api/common/infomation_detail", fields: ["id": String(id)], token: token)
        guard value.isRemoved || value.id == id else { throw APIError.malformedResponse }; return value
    }
    public func invitations(page: Int, token: String) async throws -> SocialInvitePage {
        guard page > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let result: Rows<SocialInvitedMember> = try await read("api/user/invite_list", fields: ["pageNum": String(page), "pageSize": "100"], token: token)
        return .init(members: result.rows, total: result.total, pageNumber: page, pageSize: 100)
    }
    public func rewards(token: String) async throws -> SocialRewardScan {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        return try await read("api/user/points/list", fields: ["pageNum": "1", "pageSize": "200"], token: token)
    }
    public func invitationHistory(page: Int, token: String) async throws -> SocialInviteHistory {
        let invites = try await invitations(page: page, token: token)
        do {
            let scan = try await rewards(token: token)
            return .init(page: invites, rewardScan: scan)
        }
        catch is CancellationError { throw CancellationError() }
        catch APIError.unauthorized { throw APIError.unauthorized }
        catch { try Task.checkCancellation(); return .init(page: invites, rewardScan: nil) }
    }
    private func read<T: Decodable>(_ path: String, fields: [String: String] = [:], token: String? = nil, body: Bool = true) async throws -> T {
        if let token, !AuthRequestBuilder.isValidToken(token) { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token, includesBody: body)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        let envelope = try? JSONDecoder().decode(SocialValue.self, from: data)
        if status == 401 || envelope?["code"].integer == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let code = envelope?["code"].integer else { throw APIError.malformedResponse }
        guard code == 200 else { throw SocialAccountFailure.rejected(code: code, message: envelope?["msg"].text) }
        do { return try JSONDecoder().decode(Payload<T>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    private struct Payload<T: Decodable>: Decodable { let data: T }
    private struct Rows<T: Decodable>: Decodable {
        let rows: [T]
        let total: Int?
        enum Keys: String, CodingKey { case rows, total }
        init(from decoder: Decoder) throws {
            if let values = try? decoder.singleValueContainer().decode([T].self) { rows = values; total = nil }
            else {
                let c = try decoder.container(keyedBy: Keys.self)
                rows = try c.decode([T].self, forKey: .rows)
                let rawTotal = try c.decodeIfPresent(SocialValue.self, forKey: .total)
                total = rawTotal?.integer
                guard rawTotal == nil || total != nil else { throw APIError.malformedResponse }
                guard total.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
            }
        }
    }
}
