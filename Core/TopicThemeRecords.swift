import Foundation

/// Mini-program "我的游玩记录" sheet on `pages/topic/index` (`utils/theme-records.js`).
/// Read-only: `GET api/play/theme/history` and `GET api/play/theme/card`. Replay is not offered here.
public struct TopicThemeRecord: Decodable, Equatable, Identifiable {
    public enum Title: Equatable { case server(String), completed, ended, playing }
    public let sessionID: Int
    public var id: Int { sessionID }
    public let topicID: Int?
    public let scope: String?
    public let sceneName: String?
    public let title: Title
    public let summary: String?
    public let endedAt: String?
    public init(from decoder: Decoder) throws {
        let v = try SquareValue(from: decoder)
        guard let session = v["sessionId"].integer, session > 0 else { throw APIError.malformedResponse }
        sessionID = session; topicID = v["topicId"].integer; scope = v["scope"].nonempty; sceneName = v["sceneName"].nonempty
        let result = v["result"]
        if let text = result["title"].nonempty { title = .server(text) }
        else if result["success"].truthy || result["success"].string == "true" { title = .completed }
        else if result["reason"].nonempty != nil { title = .ended }
        else { title = .playing }
        summary = result["summary"].nonempty; endedAt = result["endedAt"].nonempty
    }
}

public struct TopicThemeCard: Decodable, Equatable {
    public struct Quantity: Equatable { public let name: String; public let quantity: Int? }
    public let title: String?
    public let summary: String?
    public let scene: String?
    public let values: [(label: String?, kind: String, value: Int)]
    public let items: [Quantity]
    public let medals: [Quantity]
    public let epilogues: [(name: String, line: String?)]
    public let nextScene: String?
    public static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.summary == b.summary && a.scene == b.scene && a.items == b.items && a.medals == b.medals &&
        a.nextScene == b.nextScene && a.values.map { "\($0.label ?? "")|\($0.kind)|\($0.value)" } == b.values.map { "\($0.label ?? "")|\($0.kind)|\($0.value)" } &&
        a.epilogues.map { $0.name + "|" + ($0.line ?? "") } == b.epilogues.map { $0.name + "|" + ($0.line ?? "") }
    }
    public init(from decoder: Decoder) throws {
        let v = try SquareValue(from: decoder)
        guard v.object != nil else { throw APIError.malformedResponse }
        title = v["title"].nonempty; summary = v["summary"].nonempty; scene = v["scene"].nonempty
        // Source value rows; server-supplied names win over the default labels.
        var rows: [(String?, String, Int)] = []
        for (kind, name) in [("hp", "hpName"), ("luck", "luckName"), ("actions", ""), ("rescues", "")] {
            if let value = v[kind].integer { rows.append((name.isEmpty ? nil : v[name].nonempty, kind, value)) }
        }
        values = rows.map { (label: $0.0, kind: $0.1, value: $0.2) }
        func quantities(_ key: String) -> [Quantity] {
            (v[key].array ?? []).compactMap { row in row["name"].nonempty.map { Quantity(name: $0, quantity: row["quantity"].integer) } }
        }
        items = quantities("items"); medals = quantities("medals")
        epilogues = (v["epilogues"].array ?? []).compactMap { row in row["name"].nonempty.map { (name: $0, line: row["line"].nonempty) } }
        nextScene = v["nextScene"]["name"].nonempty
    }
}

public struct TopicThemeHistoryPage: Equatable {
    public let rows: [TopicThemeRecord]
    /// Source: another page may exist when exactly `limit` rows came back.
    public let hasMore: Bool
    public var nextBefore: Int? { hasMore ? rows.last?.sessionID : nil }
}

@MainActor public protocol TopicThemeRecordsReading: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    func themeHistory(topicID: Int, beforeSessionID: Int?) async throws -> TopicThemeHistoryPage
    func themeCard(sessionID: Int) async throws -> TopicThemeCard
}
