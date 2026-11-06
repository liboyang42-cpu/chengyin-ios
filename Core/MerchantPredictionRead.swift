import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only context-immutable injection. Nil remains the shipped default.
/// This does not authorize settlement, XP, coupons, or any player prediction action.
public struct MerchantPredictionReadApproval {
    public let revision: UUID
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int, revision: UUID = UUID()) throws {
        _ = try OperationEndpointApproval(baseURL: baseURL, namespace: namespace, accountID: accountID,
            paths: ["api/merchant/access/me", "api/merchant/predict/inbox"])
        guard market == .china else { throw APIError.invalidRequest }
        self.market = market; self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID; self.revision = revision
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        context.market == market && context.baseURL == baseURL && context.session.namespace == namespace && context.session.accountID == accountID
    }
}

public struct MerchantPredictionInboxRound: Decodable, Equatable, Identifiable {
    public struct Option: Decodable, Equatable, Identifiable {
        public let key: String
        public let label: String
        public var id: String { key }
    }
    public let nodeID: Int
    public let topicID: Int?
    public let playDay: String
    public let nodeName: String
    public let question: String
    public let options: [Option]
    public let betCount: Int
    /// Server natural-day value, not a computed 48-hour countdown or expiry proof.
    public let daysLeft: Int
    public var id: String { "\(nodeID):\(playDay)" }
    private enum CodingKeys: String, CodingKey { case nodeId, topicId, playDay, nodeName, question, options, betCount, daysLeft }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let node = c.merchantInteger(.nodeId), node > 0 else { throw APIError.malformedResponse }
        nodeID = node
        if try c.decodeNil(forKey: .topicId) { topicID = nil }
        else {
            guard let topic = c.merchantInteger(.topicId), topic > 0 else { throw APIError.malformedResponse }
            topicID = topic
        }
        playDay = try c.decode(String.self, forKey: .playDay)
        guard Self.validDay(playDay) else { throw APIError.malformedResponse }
        // Source predict/index.js shapeRound: a missing name falls back to "未命名点位" in the view.
        nodeName = try c.decodeIfPresent(String.self, forKey: .nodeName) ?? ""
        question = try c.decode(String.self, forKey: .question)
        options = try c.decode([Option].self, forKey: .options)
        guard options.allSatisfy({ !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(options.map(\.key)).count == options.count else { throw APIError.malformedResponse }
        betCount = try c.decode(Int.self, forKey: .betCount)
        daysLeft = try c.decode(Int.self, forKey: .daysLeft)
        guard betCount >= 0, daysLeft >= 0 else { throw APIError.malformedResponse }
    }
    private static func validDay(_ value: String) -> Bool {
        guard value.utf8.count == 10 else { return false }
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].utf8.count == 4, pieces[1].utf8.count == 2, pieces[2].utf8.count == 2,
              pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(pieces[0]), year > 0, let month = Int(pieces[1]), let day = Int(pieces[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == year && checked.month == month && checked.day == day
    }
}

/// There is deliberately no settle method and no invented pending-to-success readback.
public struct MerchantPredictionReadService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func inbox(access: MerchantAccess, token: String) async throws -> [MerchantPredictionInboxRound] {
        guard access.allows(.projects), (access.merchantID ?? 0) > 0 else { throw MerchantReadError.accessDenied }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/merchant/predict/inbox"),
            fields: [:], token: token, includesBody: false)
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw MerchantReadError.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard Set(envelope.rows.map(\.id)).count == envelope.rows.count else { throw APIError.malformedResponse }
        return envelope.rows
    }
    private struct Envelope: Decodable {
        let rows: [MerchantPredictionInboxRound]
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self), code = try c.decode(Int.self, forKey: .code)
            if code == 401 { throw APIError.unauthorized }
            if code == 403 { throw MerchantReadError.accessDenied }
            guard code == 200 else { throw APIError.businessCode(code) }
            rows = try c.decode([MerchantPredictionInboxRound].self, forKey: .data)
        }
    }
}
