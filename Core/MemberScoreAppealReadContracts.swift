import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MemberScoreListFailure: Error, Equatable { case disabled, denied, malformed, unavailable, stale }
public enum MemberScoreReadCapability: String, Hashable { case list, sessionDetail, reputation }
public enum MemberScoreAppealFilter: String, CaseIterable, Identifiable {
    case all, active, decided
    public var id: String { rawValue }
    public var queryValue: String? { self == .all ? nil : self == .active ? "open" : "closed" }
}
public enum MemberScoreAppealKind: String, Decodable { case appeal, dispute }
public enum MemberScoreAppealStatus: String, Decodable { case open, accepted, rejected }
public enum MemberScoreReputation: String, Decodable { case normal, restricted }

public struct MemberScoreAppealRow: Decodable, Equatable, Identifiable {
    public let recordID: Int64
    public let sessionID: Int64?
    public let topicID: Int64?
    public let kind: MemberScoreAppealKind
    public let status: MemberScoreAppealStatus
    public let title: String?
    public let nodeID: Int64?
    public let createTime: String?
    public var id: String { "\(kind.rawValue):\(recordID)" }
    public var canReadSession: Bool { sessionID != nil && topicID != nil }
    enum CodingKeys: String, CodingKey { case recordID = "id", sessionID = "sessionId", topicID = "topicId", kind, status, title = "topicName", nodeID = "nodeId", createTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try c.decode(Int64.self, forKey: .recordID)
        sessionID = try c.decodeIfPresent(Int64.self, forKey: .sessionID)
        topicID = try c.decodeIfPresent(Int64.self, forKey: .topicID)
        nodeID = try c.decodeIfPresent(Int64.self, forKey: .nodeID)
        kind = try c.decode(MemberScoreAppealKind.self, forKey: .kind)
        status = try c.decode(MemberScoreAppealStatus.self, forKey: .status)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
        guard recordID > 0, [sessionID, topicID, nodeID].allSatisfy({ $0 == nil || $0! > 0 }) else { throw MemberScoreListFailure.malformed }
    }
}
public struct MemberScoreAppealPage: Decodable {
    public let rows: [MemberScoreAppealRow]
    public let total: Int
    func validate() throws {
        guard rows.count <= MemberScoreReadRoute.pageSize, total >= 0,
              Set(rows.map(\.id)).count == rows.count else { throw MemberScoreListFailure.malformed }
        // rows and total are separate source queries, not an atomic snapshot.
    }
}
public struct MemberScoreAppealDetail: Equatable {
    public let status: MemberScoreAppealStatus
    public let resolutionNote: String?
    public let totalCenti: Int64
}
/// C6 OrientPlayerWire emits decimal strings for IDs and totalCenti; never round through Double.
struct MemberScoreWireInteger: Decodable {
    let value: Int64
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Int64(raw), String(value).utf8.elementsEqual(raw.utf8) else { throw MemberScoreListFailure.malformed }
        self.value = value
    }
}
struct MemberScoreSessionWire: Decodable {
    struct Record: Decodable {
        let id: MemberScoreWireInteger
        let memberId: MemberScoreWireInteger
        let sessionId: MemberScoreWireInteger
        let status: Int
        let resolutionNote: String?
    }
    let sessionId: MemberScoreWireInteger
    let topicId: MemberScoreWireInteger
    let totalCenti: MemberScoreWireInteger
    let appeals: [Record]
    let disputes: [Record]
    func detail(for row: MemberScoreAppealRow, account: Int) throws -> MemberScoreAppealDetail {
        guard row.sessionID == sessionId.value, row.topicID == topicId.value,
              sessionId.value > 0, topicId.value > 0 else { throw MemberScoreListFailure.malformed }
        let records = row.kind == .appeal ? appeals : disputes
        let matches = records.filter { $0.id.value == row.recordID }
        guard matches.count == 1, let match = matches.first, match.memberId.value == Int64(account),
              match.sessionId.value == sessionId.value, (0...2).contains(match.status) else { throw MemberScoreListFailure.malformed }
        return .init(status: [.open, .accepted, .rejected][match.status], resolutionNote: match.resolutionNote, totalCenti: totalCenti.value)
    }
}
public enum MemberScoreReadScope {
    public static func matches(_ current: RuntimeDependencyContext?, _ captured: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(current, captured) &&
            current?.session.role.utf8.elementsEqual(captured.session.role.utf8) == true &&
            captured.role.utf8.elementsEqual(captured.session.role.utf8)
    }
}
public enum MemberScoreReadRoute: Equatable {
    case list(page: Int, filter: MemberScoreAppealFilter)
    case detail(sessionID: Int64)
    case reputation
    public static let pageSize = 50
    public static let maximumPage = Int(Int32.max) / pageSize + 1
    public var capability: MemberScoreReadCapability {
        switch self { case .list: return .list; case .detail: return .sessionDetail; case .reputation: return .reputation }
    }
    public var path: String {
        switch self {
        case .list: return "api/orient/scoring/mine"
        case .detail(let id): return "api/orient/scoring/session/\(id)"
        case .reputation: return "api/member/reputation"
        }
    }
    public var query: [URLQueryItem] {
        guard case let .list(page, filter) = self else { return [] }
        return [.init(name: "pageNum", value: String(page)), .init(name: "pageSize", value: String(Self.pageSize))] +
            (filter.queryValue.map { [.init(name: "status", value: $0)] } ?? [])
    }
    public var isValid: Bool {
        switch self { case .list(let page, _): return (1...Self.maximumPage).contains(page); case .detail(let id): return id > 0; case .reputation: return true }
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        let query = parts.queryItems ?? []; parts.query = nil
        guard Set(query.map(\.name)).count == query.count else { return nil }
        if parts.url == baseURL.appendingPathComponent("api/orient/scoring/mine") {
            let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
            guard Set(values.keys) == ["pageNum", "pageSize"] || Set(values.keys) == ["pageNum", "pageSize", "status"],
                  values["pageSize"] == "50", let text = values["pageNum"], let page = Int(text), String(page) == text else { return nil }
            let filter: MemberScoreAppealFilter
            switch values["status"] { case nil: filter = .all; case "open": filter = .active; case "closed": filter = .decided; default: return nil }
            self = .list(page: page, filter: filter)
        } else if parts.url == baseURL.appendingPathComponent("api/member/reputation"), query.isEmpty {
            self = .reputation
        } else {
            guard query.isEmpty, let raw = parts.url?.lastPathComponent, let id = Int64(raw), String(id) == raw,
                  parts.url == baseURL.appendingPathComponent("api/orient/scoring/session/\(id)") else { return nil }
            self = .detail(sessionID: id)
        }
        guard isValid else { return nil }
    }
}
