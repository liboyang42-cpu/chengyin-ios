import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source-backed, owner-only read routes. No host, credential, approval or live factory default.
public struct NonCashRewardService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func rewards(limit: Int, cursor: String?, token: String) async throws -> NonCashRewardPage {
        guard (1...50).contains(limit), cursor == nil || Self.isAwardID(cursor!) else { throw APIError.invalidRequest }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let data = try await get(path: "api/rewards/noncash", query: query, token: token)
        let wire: Envelope<PageWire> = try decode(data)
        let page = wire.data
        guard page.items.count <= limit, page.asOf >= 0,
              Set(page.items.map(\.awardId)).count == page.items.count,
              page.items.allSatisfy({ $0.asOf == page.asOf }),
              page.nextCursor == nil || (Self.isAwardID(page.nextCursor!) && page.items.count == limit && page.nextCursor == page.items.last?.awardId && page.nextCursor != cursor)
        else { throw APIError.malformedResponse }
        return NonCashRewardPage(items: try page.items.map { try $0.domain() }, nextCursor: page.nextCursor,
                                 asOf: try Self.date(page.asOf))
    }
    public func reward(_ reference: NonCashRewardReference, token: String) async throws -> NonCashReward {
        guard Self.isAwardID(reference.awardId), [reference.contextId, reference.releaseId, reference.instanceId].allSatisfy(Self.validText)
        else { throw APIError.invalidRequest }
        let query = [URLQueryItem(name: "contextType", value: reference.contextType.rawValue),
                     URLQueryItem(name: "contextId", value: reference.contextId),
                     URLQueryItem(name: "releaseId", value: reference.releaseId),
                     URLQueryItem(name: "instanceId", value: reference.instanceId)]
        let data = try await get(path: "api/rewards/noncash/" + reference.awardId, query: query, token: token)
        let wire: Envelope<RewardWire> = try decode(data)
        let value = try wire.data.domain(), old = reference.snapshot
        // State and advisory read statuses may change; frozen scope/terms must not.
        guard value.asOf >= old.asOf, (old.state == .awarded || value.state == old.state),
              value.awardId == old.awardId, value.contextType == old.contextType, value.contextId == old.contextId,
              value.releaseId == old.releaseId, value.instanceId == old.instanceId, value.rulesVersion == old.rulesVersion,
              value.merchantId == old.merchantId, value.storeId == old.storeId, value.rewardTitle == old.rewardTitle,
              value.quantity == old.quantity, value.validFrom == old.validFrom, value.validUntil == old.validUntil,
              value.redemptionConditions == old.redemptionConditions, value.awardedAt == old.awardedAt
        else { throw APIError.malformedResponse }
        return value
    }
    private func get(path: String, query: [URLQueryItem], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token), var parts = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw APIError.invalidRequest }
        parts.queryItems = query
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard status == 200 else {
            if status == 404 { throw AccountCollectionReadFailure.unavailable }
            throw APIError.httpStatus(status)
        }
        let envelope: Status = try decode(data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        return data
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        guard data.count <= 1_048_576 else { throw APIError.malformedResponse }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.malformedResponse }
    }
    private struct Status: Decodable { let code: Int }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct PageWire: Decodable {
        let items: [RewardWire]
        let nextCursor: String?
        let asOf: Int64
        enum CodingKeys: String, CodingKey { case items, nextCursor, asOf }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.contains(.nextCursor) else { throw APIError.malformedResponse }
            items = try c.decode([RewardWire].self, forKey: .items)
            nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
            asOf = try c.decode(Int64.self, forKey: .asOf)
        }
    }
    private struct RewardWire: Decodable {
        let awardId, contextType, contextId, releaseId, instanceId, rulesVersion, merchantId, storeId: String
        let rewardKind, rewardTitle, redemptionConditions, state, validityStatus, fulfillmentStatus: String
        let quantity: Int
        let validFrom, validUntil, awardedAt, asOf: Int64
        func domain() throws -> NonCashReward {
            guard NonCashRewardService.isAwardID(awardId), rewardKind == "PHYSICAL", quantity == 1,
                  [contextId, releaseId, instanceId, rulesVersion, rewardTitle, redemptionConditions].allSatisfy(NonCashRewardService.validText),
                  NonCashRewardService.positiveID(merchantId), NonCashRewardService.positiveID(storeId),
                  validFrom >= 0, validUntil > validFrom, awardedAt >= 0, asOf >= 0,
                  let context = NonCashReward.Context(rawValue: contextType), let state = NonCashReward.State(rawValue: state),
                  let validity = NonCashReward.Validity(rawValue: validityStatus),
                  let fulfillment = NonCashReward.Fulfillment(rawValue: fulfillmentStatus),
                  validity == (asOf < validFrom ? .upcoming : asOf >= validUntil ? .elapsed : .inWindow)
            else { throw APIError.malformedResponse }
            return NonCashReward(awardId: awardId, contextType: context, contextId: contextId, releaseId: releaseId,
                                 instanceId: instanceId, rulesVersion: rulesVersion, merchantId: merchantId, storeId: storeId,
                                 rewardTitle: rewardTitle, quantity: quantity, validFrom: try NonCashRewardService.date(validFrom),
                                 validUntil: try NonCashRewardService.date(validUntil), redemptionConditions: redemptionConditions,
                                 state: state, awardedAt: try NonCashRewardService.date(awardedAt), asOf: try NonCashRewardService.date(asOf),
                                 validityStatus: validity, fulfillmentStatus: fulfillment)
        }
    }
    private static func isAwardID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func validText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 512
    }
    private static func positiveID(_ value: String) -> Bool {
        guard value.first != "0", value.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int64(value) else { return false }
        return id > 0
    }
    private static func date(_ value: Int64) throws -> Date {
        // Deliberately bounded presentation range through year 9999; never truncate/wrap an unsupported timestamp.
        guard (0...253_402_300_799_999).contains(value) else { throw APIError.malformedResponse }
        return Date(timeIntervalSince1970: Double(value) / 1000)
    }
}
