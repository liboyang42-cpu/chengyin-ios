import Foundation

/// Read-only projection of the mini-program theme backpack (`pages/play/theme-backpack.wxml`,
/// `utils/theme-backpack.js present`). Source: `GET api/play/theme/state {topicId, activityId?}`.
/// Use, discard, receive, plan, trade and zero-HP recovery are live writes and are not ported;
/// the 任务 tab therefore shows an explicit unavailable state.
public struct PlayThemeBackpack: Equatable, Sendable {
    public enum ValueName: Equatable, Sendable {
        case server(String)
        /// 生命值 / 幸运值 / 行动次数 fallbacks (`theme-gameplay.js labels`)
        case hp, luck, actions
        /// 数值 (`counter.*`) / 物资
        case genericNumber, genericSupply
    }
    public struct Value: Equatable, Sendable {
        public let key: String
        public let name: ValueName
        public let value: String
        public let max: String?
        /// 已归零
        public let zero: Bool
    }
    public struct Item: Equatable, Sendable, Identifiable {
        public enum Effect: Equatable, Sendable {
            /// `<stat name> +delta`
            case stat(name: ValueName, delta: Int)
            case text(String)
            /// 随身物资
            case carried
        }
        public let id: String
        public let name: ValueName
        public let effect: Effect
        public let quantity: Int?
        public let slotCost: Int?
    }
    public struct Pending: Equatable, Sendable, Identifiable {
        public let id: String
        /// nil → 待领奖励
        public let name: String?
        public let quantity: Int?
        public let slots: Int?
    }
    public struct Clue: Equatable, Sendable, Identifiable {
        public enum Scope: Equatable, Sendable { case none, publicAll, team }
        public struct Block: Equatable, Sendable { public let source: String?; public let text: String?; public let imageCount: Int }
        public let id: String
        /// nil → 线索
        public let name: String?
        public let scope: Scope
        public let content: String?
        public let blocks: [Block]
    }
    public struct ZeroHP: Equatable, Sendable {
        /// WAIT / CHALLENGE / STEPS / BLOCK_HP_COST / BLOCK_PAID / THEME_FAIL; nil → 归零状态
        public let policy: String?
        public let phase: String
        public let progress: Int?
        public let required: Int?
        public let message: String?
    }

    public let sessionID: Int?
    public let used: Int
    public let capacity: Int
    public let values: [Value]
    public let items: [Item]
    public let pending: [Pending]
    public let clues: [Clue]
    /// 本局已结束，仅可领取待领奖励
    public let claimOnly: Bool
    public let isTeam: Bool
    public let zeroHP: ZeroHP?
    public let hasResult: Bool

    public init(_ view: PlayWireValue) throws {
        guard view.object != nil else { throw PlayExperienceError.malformed }
        sessionID = view["sessionId"].tolerantInteger.flatMap { $0 > 0 ? $0 : nil }
        isTeam = view["scope"].text == "TEAM"
        used = max(0, view["used"].tolerantInteger ?? 0)
        capacity = max(0, view["capacity"].tolerantInteger ?? 6)
        hasResult = view["result"].object != nil
        claimOnly = view["claimOnly"].bool == true || view["status"].text == "COMPLETED" || hasResult || view["naturallyCompleted"].bool == true
        let labels = Self.labels(view)
        func number(_ value: PlayWireValue) -> String? {
            guard let double = value.double, double.isFinite else { return value.text.flatMap(PlayThemeText.clean) }
            return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : String(double)
        }
        let zeroPhase = view["zeroHp"]["phase"].text
        var values: [Value] = []
        if view["hpEnabled"].bool == true {
            values.append(Value(key: "hp", name: labels.hp, value: number(view["hp"]) ?? "", max: number(view["hpMax"]),
                                zero: view["awaitingChallenge"].bool == true || (zeroPhase != nil && zeroPhase != "HEALTHY")))
        }
        if view["luckEnabled"].bool == true { values.append(Value(key: "luck", name: labels.luck, value: number(view["luck"]) ?? "", max: number(view["luckMax"]), zero: false)) }
        if (view["actionLimit"].double ?? 0) > 0 { values.append(Value(key: "actions", name: labels.action, value: number(view["actions"]) ?? "", max: number(view["actionLimit"]), zero: false)) }
        for row in view["attributes"].array ?? [] where row["visible"].bool != false {
            guard let key = row["key"].text, !key.hasPrefix("sys."), let label = PlayThemeText.clean(row["label"].text) else { continue }
            values.append(Value(key: key, name: .server(label), value: number(row["value"]) ?? "", max: number(row["max"]), zero: false))
        }
        self.values = values
        let contents = view["contents"].array ?? []
        items = contents.filter { $0["kind"].text == "ITEM" }.compactMap { row in
            guard let id = PlayThemeText.clean(row["id"].text ?? row["id"].tolerantInteger.map(String.init)) else { return nil }
            let stat = row["statKey"].text ?? row["stat"].text
            let effect: Item.Effect
            if let stat, let delta = row["delta"].tolerantInteger { effect = .stat(name: Self.valueName(stat, view), delta: delta) }
            else if let text = PlayThemeText.clean(row["content"].text) { effect = .text(text) }
            else { effect = .carried }
            return Item(id: id, name: PlayThemeText.clean(row["name"].text).map(ValueName.server) ?? Self.valueName(id, view),
                        effect: effect, quantity: row["quantity"].tolerantInteger, slotCost: row["slotCost"].tolerantInteger)
        }
        pending = (view["pending"].object ?? [:]).sorted { $0.key < $1.key }.map { key, row in
            Pending(id: key, name: PlayThemeText.clean(row["name"].text), quantity: row["quantity"].tolerantInteger, slots: row["slots"].tolerantInteger)
        }
        var clues: [Clue] = contents.filter { $0["kind"].text != "ITEM" && $0["stat"] == .null && $0["statKey"] == .null }.enumerated().map { index, row in
            Clue(id: "content:" + (row["id"].text ?? String(index)), name: PlayThemeText.clean(row["name"].text), scope: .none, content: PlayThemeText.clean(row["content"].text), blocks: [])
        }
        clues += (view["events"].array ?? []).enumerated().map { index, row in
            Clue(id: "event:" + (row["id"].text ?? row["id"].tolerantInteger.map(String.init) ?? String(index)), name: PlayThemeText.clean(row["name"].text), scope: .none, content: PlayThemeText.clean(row["content"].text), blocks: [])
        }
        clues += (view["clues"].array ?? []).enumerated().map { index, row in
            let blocks = (row["sources"].array ?? []).flatMap { source in
                (source["blocks"].array ?? []).map { block in
                    Clue.Block(source: PlayThemeText.clean(source["title"].text), text: PlayThemeText.clean(block["text"].text),
                               imageCount: (block["images"].array ?? []).compactMap(\.text).filter { !$0.isEmpty }.count)
                }
            }
            let scope: Clue.Scope = row["scope"].text == "PUBLIC" ? .publicAll : .team
            return Clue(id: "clue:" + (row["id"].text ?? row["id"].tolerantInteger.map(String.init) ?? String(index)) + ":" + (row["scope"].text ?? ""),
                        name: PlayThemeText.clean(row["name"].text), scope: scope, content: nil, blocks: blocks)
        }
        self.clues = clues
        if let phase = zeroPhase, phase != "HEALTHY" {
            let zero = view["zeroHp"]
            zeroHP = ZeroHP(policy: zero["effectivePolicy"].text ?? zero["policy"].text, phase: phase,
                            progress: zero["progress"].integer, required: zero["required"].integer.flatMap { $0 > 0 ? $0 : nil },
                            message: PlayThemeText.clean(zero["message"].text))
        } else { zeroHP = nil }
    }

    static func labels(_ view: PlayWireValue) -> (hp: ValueName, luck: ValueName, action: ValueName) {
        (PlayThemeText.clean(view["hpName"].text).map(ValueName.server) ?? .hp,
         PlayThemeText.clean(view["luckName"].text).map(ValueName.server) ?? .luck,
         PlayThemeText.clean(view["actionName"].text).map(ValueName.server) ?? .actions)
    }
    /// `theme-gameplay.js valueName`.
    static func valueName(_ key: String, _ view: PlayWireValue) -> ValueName {
        let words = labels(view)
        if key == "HP" || key == "sys.hp" { return words.hp }
        if key == "LUCK" || key == "sys.luck" { return words.luck }
        if key == "sys.actions" { return words.action }
        if let label = (view["attributes"].array ?? []).first(where: { $0["key"].text == key }).flatMap({ PlayThemeText.clean($0["label"].text) }) { return .server(label) }
        let catalog = view["itemCatalog"].array ?? view["world"]["itemCatalog"].array ?? []
        if let name = (catalog + (view["contents"].array ?? [])).first(where: { $0["id"].text == key }).flatMap({ PlayThemeText.clean($0["name"].text) }) { return .server(name) }
        return key.hasPrefix("counter.") ? .genericNumber : .genericSupply
    }
}

extension PlayExperienceService {
    /// `GET api/play/theme/state` with `topicId` plus the play scope (`_sessionParams`).
    public func themeState(scope: PlaySessionScope, topicID: Int, token: String) async throws -> PlayWireValue {
        guard topicID > 0 else { throw APIError.invalidRequest }
        var query = try scopeFields(scope); query["topicId"] = String(topicID)
        return try await request("api/play/theme/state", query: query, capability: .reads, token: token)
    }
}

public protocol PlayThemeBackpackReading: AnyObject {
    @MainActor func state() async throws -> PlayWireValue
}

@available(macOS 14.0, *)
@MainActor @Observable public final class PlayThemeBackpackCoordinator {
    public enum Phase: Equatable { case idle, loading, ready, failed(message: String?), unavailable }
    public private(set) var phase: Phase
    public private(set) var backpack: PlayThemeBackpack?
    private let reader: (any PlayThemeBackpackReading)?
    private var generation: UInt64 = 0
    public init(reader: (any PlayThemeBackpackReading)?) { self.reader = reader; phase = reader == nil ? .unavailable : .idle }

    /// Read on open and on explicit refresh only (the mini-program's 10/30 s poll is not ported).
    public func refresh() async {
        guard let reader, phase != .loading else { return }
        generation &+= 1; let request = generation
        phase = .loading
        do {
            let value = try PlayThemeBackpack(await reader.state())
            guard request == generation else { return }
            if let current = backpack?.sessionID, let next = value.sessionID, current != next { backpack = nil }
            backpack = value; phase = .ready
        } catch {
            guard request == generation else { return }
            if case PlayExperienceError.rejected(_, let message) = error { phase = .failed(message: message) } else { phase = .failed(message: nil) }
        }
    }
}
