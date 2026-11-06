import Foundation

/// Mini-program `utils/theme-records.js` + `components/cy/theme-records` (我的游玩记录 and
/// 本局结果). Reads only: `GET api/play/theme/history {topicId, limit:20, beforeSessionId?}` and
/// `GET api/play/theme/card {sessionId}`. 再玩一次 (`POST api/play/theme/replay`) is a live
/// write that also clears the server run session; it is not ported.
public struct PlayThemeHistoryRow: Equatable, Identifiable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Server-authored result title.
        case titled(String)
        /// 本局完成
        case completed
        /// 本局结束
        case ended
        /// 游玩中
        case inProgress
    }
    public let sessionID: Int
    public let topicID: Int?
    public let isTeam: Bool
    public let sceneName: String?
    public let outcome: Outcome
    public let summary: String?
    public let endedAt: Date?
    /// A card can be opened only when the server returned a result.
    public let hasCard: Bool
    public var id: Int { sessionID }

    public init?(_ raw: PlayWireValue) {
        guard let session = raw["sessionId"].tolerantInteger, session > 0 else { return nil }
        sessionID = session
        topicID = raw["topicId"].tolerantInteger.flatMap { $0 > 0 ? $0 : nil }
        isTeam = raw["scope"].text == "TEAM"
        sceneName = PlayThemeText.clean(raw["sceneName"].text)
        let result = raw["result"]
        hasCard = result.object != nil
        if let title = PlayThemeText.clean(result["title"].text) { outcome = .titled(title) }
        else if result["success"].bool == true { outcome = .completed }
        else if PlayThemeText.clean(result["reason"].text) != nil { outcome = .ended }
        else { outcome = .inProgress }
        summary = PlayThemeText.clean(result["summary"].text)
        endedAt = result["endedAt"].double.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
    }
}

public struct PlayThemeResultCard: Equatable, Sendable {
    public enum ValueName: Equatable, Sendable {
        case server(String)
        /// 生命值 / 幸运值 / 行动次数 / 获救次数
        case hp, luck, actions, rescues
    }
    public struct Value: Equatable, Sendable { public let name: ValueName; public let value: String }
    public struct Count: Equatable, Sendable { public let name: String; public let quantity: Int }
    public struct Epilogue: Equatable, Sendable { public let name: String; public let line: String }

    public let sessionID: Int
    /// nil → 本局结果
    public let title: String?
    public let coverURL: String?
    public let summary: String?
    public let scene: String?
    public let values: [Value]
    public let items: [Count]
    public let medals: [Count]
    public let epilogues: [Epilogue]
    public let exhibits: [String]
    /// 已发现的结局
    public let knownEndings: [String]
    /// 下次场景：
    public let nextScene: String?

    /// `resultCard(card, view)`; name fallbacks come from the card, then the history view.
    public init(_ card: PlayWireValue, sessionID: Int, view: PlayWireValue = .null) {
        self.sessionID = sessionID
        title = PlayThemeText.clean(card["title"].text)
        coverURL = PlayThemeText.clean(card["cover"].text)
        summary = PlayThemeText.clean(card["summary"].text)
        scene = PlayThemeText.clean(card["scene"].text)
        func number(_ value: PlayWireValue) -> String? {
            guard let double = value.double, double.isFinite else { return nil }
            return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : String(double)
        }
        func name(_ primary: String, _ secondary: String, _ fallback: ValueName) -> ValueName {
            (PlayThemeText.clean(card[primary].text) ?? PlayThemeText.clean(view[secondary].text)).map(ValueName.server) ?? fallback
        }
        var values: [Value] = []
        if let hp = number(card["hp"]) { values.append(Value(name: name("hpName", "hpName", .hp), value: hp)) }
        if let luck = number(card["luck"]) { values.append(Value(name: name("luckName", "luckName", .luck), value: luck)) }
        if let actions = number(card["actions"]) {
            values.append(Value(name: PlayThemeText.clean(view["actionName"].text).map(ValueName.server) ?? .actions, value: actions))
        }
        if let rescues = number(card["rescues"]) { values.append(Value(name: .rescues, value: rescues)) }
        self.values = values
        func counts(_ key: String) -> [Count] {
            (card[key].array ?? []).compactMap { row in
                guard let name = PlayThemeText.clean(row["name"].text), let quantity = row["quantity"].tolerantInteger, quantity >= 0 else { return nil }
                return Count(name: name, quantity: quantity)
            }
        }
        items = counts("items"); medals = counts("medals")
        epilogues = (card["epilogues"].array ?? []).compactMap { row in
            guard let name = PlayThemeText.clean(row["name"].text), let line = PlayThemeText.clean(row["line"].text) else { return nil }
            return Epilogue(name: name, line: line)
        }
        exhibits = (card["exhibits"].array ?? []).compactMap { PlayThemeText.clean($0.text) }
        knownEndings = (card["unlocks"]["known"].array ?? []).compactMap { PlayThemeText.clean($0["title"].text) }
        nextScene = PlayThemeText.clean(card["nextScene"]["name"].text)
    }
}

enum PlayThemeText {
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.count > 2000 ? nil : text
    }
}

extension PlayExperienceService {
    public static let themeHistoryPageSize = 20
    public func themeHistory(topicID: Int, beforeSessionID: Int?, token: String) async throws -> [PlayWireValue] {
        guard topicID > 0, beforeSessionID.map({ $0 > 0 }) ?? true else { throw APIError.invalidRequest }
        var query = ["topicId": String(topicID), "limit": String(Self.themeHistoryPageSize)]
        if let beforeSessionID { query["beforeSessionId"] = String(beforeSessionID) }
        let raw = try await request("api/play/theme/history", query: query, capability: .reads, token: token)
        guard let rows = raw.array else { throw PlayExperienceError.malformed }
        return rows
    }
    public func themeCard(sessionID: Int, token: String) async throws -> PlayWireValue {
        guard sessionID > 0 else { throw APIError.invalidRequest }
        let raw = try await request("api/play/theme/card", query: ["sessionId": String(sessionID)], capability: .reads, token: token)
        guard raw.object != nil else { throw PlayExperienceError.malformed }
        return raw
    }
}

public protocol PlayThemeRecordsReading: AnyObject {
    @MainActor func history(topicID: Int, beforeSessionID: Int?) async throws -> [PlayWireValue]
    @MainActor func card(sessionID: Int) async throws -> PlayWireValue
}

@available(macOS 14.0, *)
@MainActor @Observable public final class PlayThemeRecordsCoordinator {
    public enum Issue: Equatable {
        /// 游玩记录暂未加载，请稍后重试 (read failure)
        case historyFailed
        /// 本局结果暂未加载，请稍后重试
        case cardFailed
        /// 本队结果暂未加载，请刷新后重试
        case teamCardMissing
        /// 401 / 403 / code 2: not offered a retry (mini-program `readFailure == false`).
        case refused
    }
    public let topicID: Int
    public private(set) var rows: [PlayThemeHistoryRow] = []
    public private(set) var hasMore = true
    public private(set) var busy = false
    public private(set) var issue: Issue?
    public private(set) var card: PlayThemeResultCard?
    public private(set) var cardSessionID: Int?
    private var rawRows: [Int: PlayWireValue] = [:]
    private let reader: (any PlayThemeRecordsReading)?
    private var epoch: UInt64 = 0

    public init(topicID: Int, reader: (any PlayThemeRecordsReading)?) { self.topicID = topicID; self.reader = reader }
    public var isAvailable: Bool { reader != nil && topicID > 0 }

    public func open() async {
        epoch &+= 1
        rows = []; rawRows = [:]; hasMore = true; busy = false; issue = nil; card = nil; cardSessionID = nil
        await loadMore()
    }

    public func loadMore() async {
        guard let reader, isAvailable, !busy, hasMore else { return }
        let request = epoch
        busy = true; issue = nil
        defer { if request == epoch { busy = false } }
        do {
            let page = try await reader.history(topicID: topicID, beforeSessionID: rows.last?.sessionID)
            guard request == epoch else { return }
            var seen = Set(rows.map(\.sessionID))
            for raw in page {
                guard let row = PlayThemeHistoryRow(raw), seen.insert(row.sessionID).inserted else { continue }
                rows.append(row); rawRows[row.sessionID] = raw
            }
            hasMore = page.count == PlayExperienceService.themeHistoryPageSize
        } catch {
            guard request == epoch else { return }
            issue = Self.refused(error) ? .refused : .historyFailed
        }
    }

    public func openCard(sessionID: Int) async {
        guard let reader, let row = rows.first(where: { $0.sessionID == sessionID }) else { return }
        epoch &+= 1; let request = epoch
        cardSessionID = sessionID; card = nil; issue = nil
        let view = rawRows[sessionID] ?? .null
        if row.isTeam {
            // Team results come with the view itself (`resultCard`); no extra read.
            if view["resultCard"].object != nil { card = PlayThemeResultCard(view["resultCard"], sessionID: sessionID, view: view) }
            else { issue = .teamCardMissing }
            return
        }
        guard row.hasCard else { cardSessionID = nil; return }
        busy = true
        defer { if request == epoch { busy = false } }
        do {
            let raw = try await reader.card(sessionID: sessionID)
            guard request == epoch else { return }
            card = PlayThemeResultCard(raw, sessionID: sessionID, view: view)
        } catch {
            guard request == epoch else { return }
            issue = Self.refused(error) ? .refused : .cardFailed
        }
    }

    public func closeCard() { epoch &+= 1; card = nil; cardSessionID = nil; busy = false; if issue == .cardFailed || issue == .teamCardMissing { issue = nil } }
    public func close() { epoch &+= 1; busy = false; card = nil; cardSessionID = nil }

    private static func refused(_ error: Error) -> Bool {
        if case PlayExperienceError.rejected(let code, _) = error { return [401, 403, 2].contains(code) }
        return error as? PlayExperienceError == .unauthorized
    }
}
