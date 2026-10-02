import Foundation

/// Source: my_project.dart. IDs are scoped by business type, never globally by integer.
public struct CreatorContentProject: Decodable, Equatable, Identifiable {
    public let sourceID: Int
    public let bizType: String
    public var id: String { "\(bizType):\(sourceID)" }
    public let title: String
    public let cover: String?
    public let projectTypeText: String?
    public let state: String?
    public let stateText: String?
    public let publishStatus: String?
    public let signupCount: Int
    public let viewCount: Int
    public let ownerType: String?
    public let clubID: Int?
    public let acceptStatus: String?
    public let acceptStatusText: String?
    public let startTime: String?
    public let endTime: String?
    public var destination: CreatorContentDestination? {
        guard sourceID > 0 else { return nil }
        switch bizType {
        case "topic": return .topic(sourceID)
        case "activity": return .activity(sourceID)
        // Source MyProject.detailRoute explicitly maps this bizType to /template/:id,
        // whose TemplateDetailPage calls /api/template/info (PlayTemplate). This is not
        // TopicTemplate from /api/template/topic-template/list, which has no detail API.
        case "template": return .playTemplate(sourceID)
        default: return nil
        }
    }
    private enum CodingKeys: String, CodingKey {
        case id, bizType, title, cover, projectTypeText, state, stateText, publishStatus, signupCount, viewCount, ownerType, clubId, acceptStatus, acceptStatusText, startTime, endTime
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try c.decode(Int.self, forKey: .id)
        guard sourceID > 0 else { throw APIError.malformedResponse }
        bizType = try c.decode(String.self, forKey: .bizType)
        title = (try c.decodeIfPresent(String.self, forKey: .title) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        projectTypeText = try c.decodeIfPresent(String.self, forKey: .projectTypeText)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        stateText = try c.decodeIfPresent(String.self, forKey: .stateText)
        publishStatus = try c.decodeIfPresent(String.self, forKey: .publishStatus)
        signupCount = try c.decodeIfPresent(Int.self, forKey: .signupCount) ?? 0
        viewCount = try c.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0
        ownerType = try c.decodeIfPresent(String.self, forKey: .ownerType)
        clubID = try c.decodeIfPresent(Int.self, forKey: .clubId)
        acceptStatus = try c.decodeIfPresent(String.self, forKey: .acceptStatus)
        acceptStatusText = try c.decodeIfPresent(String.self, forKey: .acceptStatusText)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
    }
}
public enum CreatorContentDestination: Equatable { case topic(Int), activity(Int), playTemplate(Int) }
public struct CreatorContentProjectPage: Decodable, Equatable {
    public let rows: [CreatorContentProject]
    public let total: Int
    public var isTruncated: Bool { total > rows.count }
    public init(rows: [CreatorContentProject], total: Int) { self.rows = rows; self.total = total }
    private enum CodingKeys: String, CodingKey { case rows, total }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([CreatorContentProject].self, forKey: .rows) ?? []
        var seen = Set<String>()
        rows = raw.filter { seen.insert($0.id).inserted }
        let number = (try? c.decode(Int.self, forKey: .total)) ?? (try? c.decode(String.self, forKey: .total)).flatMap(Int.init)
        total = number.map { $0 >= 0 ? $0 : raw.count } ?? raw.count
    }
}
public struct CreatorContentQuery: Equatable, Hashable {
    public var type: String
    public var state: String
    public var ownerType: String
    public init(type: String = "all", state: String = "all", ownerType: String = "all") {
        self.type = type; self.state = state; self.ownerType = ownerType
    }
    public var isValid: Bool {
        ["all", "topic", "activity", "template"].contains(type) &&
        ["all", "draft", "pending", "notStarted", "running", "completed", "offline", "rejected"].contains(state) &&
        ["all", "member", "club", "merchant"].contains(ownerType)
    }
}
public enum CreatorContentApplyStatus: String, Decodable { case notApplied = "not_applied", pending, approved, rejected, unknown }
public struct CreatorContentCenter: Decodable, Equatable {
    public let status: CreatorContentApplyStatus
    public let creatorName: String?
    public let bio: String?
    public let rejectReason: String?
    public let metric: CreatorContentMetric?
    public let recentIncome: [CreatorContentIncome]
    private enum CodingKeys: String, CodingKey { case applyStatus, profile, rejectReason, metric, recentIncome }
    private struct Profile: Decodable { let creatorName: String?; let bio: String?; let rejectReason: String? }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .applyStatus) ?? ""
        status = CreatorContentApplyStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .unknown
        let profile = try c.decodeIfPresent(Profile.self, forKey: .profile)
        creatorName = profile?.creatorName; bio = profile?.bio
        rejectReason = try profile?.rejectReason ?? c.decodeIfPresent(String.self, forKey: .rejectReason)
        metric = try c.decodeIfPresent(CreatorContentMetric.self, forKey: .metric)
        recentIncome = try c.decodeIfPresent([CreatorContentIncome].self, forKey: .recentIncome) ?? []
    }
}
public struct CreatorContentMetric: Decodable, Equatable { public let contentCount: Int?; public let viewCount: Int?; public let likeCount: Int? }
public struct CreatorContentIncome: Decodable, Equatable {
    public let date: String?; public let amount: String?; public let source: String?
    private enum CodingKeys: String, CodingKey { case date, amount, source }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        // Never attach a currency or reformat a server-supplied monetary string.
        if let text = try? c.decode(String.self, forKey: .amount) { amount = text }
        else if let number = try? c.decode(Decimal.self, forKey: .amount) { amount = NSDecimalNumber(decimal: number).stringValue }
        else { amount = nil }
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

public enum CreatorContentReadFailure: Error, Equatable {
    case unavailable
    case rejected(code: Int, message: String?)
}
public enum CreatorContentIssue: Equatable {
    case login, notConfigured, unavailable, network, failure, server(String)
    public init(_ error: Error) {
        switch error {
        case APIError.unauthorized: self = .login
        case APIError.notConfigured: self = .notConfigured
        case CreatorContentReadFailure.unavailable: self = .unavailable
        case CreatorContentReadFailure.rejected(_, let message): self = message.map(Self.server) ?? .failure
        case is URLError: self = .network
        default: self = .failure
        }
    }
    public var localizationKey: String {
        switch self {
        case .login: return "creatorContent.signInRequired"
        case .notConfigured: return "creatorContent.notConfigured"
        case .unavailable: return "creatorContent.unavailable"
        case .network: return "creatorContent.network"
        case .failure, .server: return "creatorContent.failed"
        }
    }
}
