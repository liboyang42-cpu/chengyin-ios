import Foundation

/// Narrative preview only. These scene IDs never enter template publish payloads.
public enum PrefabPreviewScene: String, Codable, CaseIterable, Identifiable {
    case prologue, register, boot, walk, hall, birth, dream1, learning, dream2, career, work, dream3, flow
    public var id: String { rawValue }
    public var isDream: Bool { rawValue.hasPrefix("dream") }
}
public struct PrefabPreviewProfile: Codable, Equatable {
    public var name = "", place = "", gender = "", dream = "", avatar = ""
    public init() {}
}
public struct PrefabPreviewObservation: Codable, Equatable { public let `where`: String; public let text: String }
public struct PrefabPreviewSticker: Codable, Equatable { public let label: String; public let x: Double; public let y: Double }
public struct PrefabPreviewCheck: Equatable {
    public let dice: [Int]; public let roll: Int; public let score: Int; public let dc: Int
    public var ok: Bool { score >= dc }
}
public struct PrefabPreviewState: Codable, Equatable {
    public var version = 2
    public var scene: PrefabPreviewScene = .prologue
    public var step = 0
    public var profile = PrefabPreviewProfile()
    public var hp = 10, luck = 2, instability = 0, walkProgress = 0, dreams = 0
    public var skills = ["rule": 2, "window": 2, "heart": 2, "precision": 1]
    public var thoughts: [String] = []
    public var observations: [PrefabPreviewObservation] = []
    public var picks: [String: TemplateAuthoringJSON] = [:]
    public var photos: [String: String] = [:]
    public var note = "", job = ""
    public var sticker: PrefabPreviewSticker?
    public var synced = false
    public init() {}
    public mutating func advance() {
        let scenes = PrefabPreviewScene.allCases
        guard let index = scenes.firstIndex(of: scene), index + 1 < scenes.count else { return }
        scene = scenes[index + 1]; step = 0
    }
    public mutating func setStep(_ next: Int) { step = max(0, next) }
    public mutating func observe(where location: String, text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !observations.contains(where: { $0.text == value }) else { return }
        observations.append(.init(where: location, text: value))
    }
    public mutating func applyProfile(_ incoming: PrefabPreviewProfile) {
        func classify(_ value: String, _ rules: [(String, String)], fallback: String) -> String {
            rules.first { value.range(of: $0.0, options: .regularExpression) != nil }?.1 ?? fallback
        }
        let place = classify(incoming.place, [("想不起|不记得|不知道|忘", "precision"), ("县|镇|村|乡|山|海边", "window"), ("上海|北京|广州|深圳|市|城", "rule")], fallback: "window")
        let dream = classify(incoming.dream, [("宇航|科学|侦探|工程|程序|研究|天文|数学|机器|发明|电脑", "precision"), ("画|作家|写|音乐|歌|演|导演|诗|摄影|设计|跳舞", "heart"), ("医生|老师|警察|律师|第一|公务员|军|会计|老板|法官", "rule"), ("旅行|环游|酒吧|自由|流浪|远方|海|山|不知道|没想|很远", "window")], fallback: "heart")
        for key in [place, dream] {
            let current = skills[key] ?? 0; skills[key] = current == Int.max ? Int.max : current + 1
        }
        profile = incoming
    }
    public func check(skill: String, dc: Int, rolls: [Int]) -> PrefabPreviewCheck {
        var dice = rolls.prefix(2).map { min(6, max(1, $0)) }
        while dice.count < 2 { dice.append(1) }
        let roll = dice.reduce(0, +); let added = roll.addingReportingOverflow(skills[skill] ?? 0)
        return .init(dice: dice, roll: roll, score: added.overflow ? Int.max : added.partialValue, dc: dc)
    }
    public mutating func gain(hp: Int = 0, luck: Int = 0, dreams: Int = 0, thought: String? = nil) {
        func sum(_ current: Int, _ delta: Int) -> Int {
            let value = current.addingReportingOverflow(delta)
            return value.overflow ? (delta < 0 ? Int.min : Int.max) : value.partialValue
        }
        self.hp = min(10, max(0, sum(self.hp, hp))); self.luck = min(4, max(0, sum(self.luck, luck))); self.dreams = max(0, sum(self.dreams, dreams))
        if let thought, !thought.isEmpty, !thoughts.contains(thought) { thoughts.append(thought) }
    }
    public var photoCount: Int { photos.values.filter { !$0.isEmpty }.count }
    /// Explicit v1/v2 import; defaults fill absent source fields. No legacy bucket is read.
    public static func restore(_ data: Data) -> Self {
        guard let value = try? JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: data),
              let version = value["version"]?.integer, [1, 2].contains(version),
              let name = value["scene"]?.string, let scene = PrefabPreviewScene(rawValue: name) else { return .init() }
        var state = Self(); state.scene = scene; state.step = version == 1 ? 0 : value["step"]?.integer ?? 0
        state.hp = value["hp"]?.integer ?? 10; state.luck = value["luck"]?.integer ?? 2
        state.instability = value["instability"]?.integer ?? 0; state.walkProgress = value["walkProgress"]?.integer ?? 0; state.dreams = value["dreams"]?.integer ?? 0
        if let fields = value["profile"]?.object {
            state.profile.name = fields["name"]?.string ?? ""; state.profile.place = fields["place"]?.string ?? ""
            state.profile.gender = fields["gender"]?.string ?? ""; state.profile.dream = fields["dream"]?.string ?? ""; state.profile.avatar = fields["avatar"]?.string ?? ""
        }
        for (key, raw) in value["skills"]?.object ?? [:] { if let number = raw.integer { state.skills[key] = number } }
        state.thoughts = value["thoughts"]?.array?.compactMap(\.string) ?? []
        state.observations = (value["observations"]?.array ?? []).compactMap { raw in
            guard let row = raw.object else { return nil }; return .init(where: row["where"]?.string ?? "", text: row["text"]?.string ?? "")
        }
        state.picks = value["picks"]?.object ?? [:]; state.photos = (value["photos"]?.object ?? [:]).mapValues { $0.string ?? "" }
        state.note = value["note"]?.string ?? ""; state.job = value["job"]?.string ?? ""; state.synced = value["synced"]?.bool ?? false
        if let sticker = value["sticker"]?.object { state.sticker = .init(label: sticker["label"]?.string ?? "", x: sticker["x"]?.number ?? 150, y: sticker["y"]?.number ?? 388) }
        return state
    }
    public static func isPrefabTopic(name: String?) -> Bool {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^预制人生(?:\\s*·.*)?$", options: .regularExpression) != nil
    }
}
/// Different source activity/topic IDs are not interchangeable, even when numeric values match.
public enum PrefabPreviewIdentity: Codable, Equatable {
    case preview, local(UUID), activity(Int), topic(Int)
    public var isValid: Bool { switch self { case .preview, .local: return true; case .activity(let id), .topic(let id): return id > 0 } }
    public var storageComponent: String {
        switch self { case .preview: return "preview"; case .local(let id): return "preview:" + id.uuidString; case .activity(let id): return "activity:\(id)"; case .topic(let id): return "topic:\(id)" }
    }
}
@MainActor public final class PrefabPreviewStore {
    private let storage: any TemplateAuthoringStorage
    public init(storage: any TemplateAuthoringStorage) { self.storage = storage }
    private struct Envelope: Codable { let version: Int; let owner: String; let identity: PrefabPreviewIdentity; let state: PrefabPreviewState }
    private func key(_ identity: PrefabPreviewIdentity, _ session: TemplateAuthoringSession) -> String {
        "prefab-preview.v1." + Data((session.ownerKey + ":" + identity.storageComponent).utf8).base64EncodedString()
    }
    public func save(_ state: PrefabPreviewState, identity: PrefabPreviewIdentity, session: TemplateAuthoringSession) throws {
        guard identity.isValid else { throw TemplateAuthoringError.invalidContract }
        try storage.write(JSONEncoder().encode(Envelope(version: 1, owner: session.ownerKey, identity: identity, state: state)), key: key(identity, session))
    }
    public func load(identity: PrefabPreviewIdentity, session: TemplateAuthoringSession) throws -> PrefabPreviewState? {
        guard identity.isValid else { throw TemplateAuthoringError.invalidContract }
        guard let data = try storage.read(key(identity, session)) else { return nil }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        guard value.version == 1, value.owner == session.ownerKey, value.identity == identity else { throw TemplateAuthoringError.invalidContract }
        return value.state
    }
}
