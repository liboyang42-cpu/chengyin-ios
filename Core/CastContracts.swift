import Foundation

/// Cast (角色) contract v1 · 2026-11-19 (hengyin docs/design/cast-contract-1119.md).
/// Player-side decoding only. Every field is tolerant: a missing or malformed
/// `castConfig` means the feature is off and existing themes render unchanged.
public enum CastVoiceMode: String, Equatable, Sendable { case preset, record, none }

public struct CastIdentity: Equatable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let sub: String?
    public var id: String { key }
}

public struct CastClue: Equatable, Sendable {
    public let text: String
    /// Nil means always known.
    public let chapterID: Int?
}

public enum CastTrustBand: String, Equatable, Sendable { case low, mid, high }

public struct CastMember: Equatable, Identifiable, Sendable {
    public static let palette = ["#E8604C", "#3D8BFD", "#2FB57A", "#B98AF0", "#F2B33D", "#8E8E93"]
    public static let neutralColor = "#8E8E93"
    public let id: String
    public let name: String
    public let identity: String?
    /// https or `media-asset:N`; nil shows a coloured initial.
    public let avatarURL: String?
    /// Always one of `palette`.
    public let color: String
    public let voiceMode: CastVoiceMode
    public let voicePreset: String?
    /// Clue texts the server chose to send. Locked clue text is never expected here.
    public let clues: [CastClue]
    /// Server-side count of clues whose text was withheld.
    public let lockedCount: Int
    public let endingLines: [CastTrustBand: String]

    public var initial: String { name.first.map { String($0) } ?? "?" }
    /// E5 route detail: the first clause of the identity (「主唱，三年前先走的人」 → 「主唱」).
    public var identityLead: String? {
        guard let identity else { return nil }
        let lead = identity.split(whereSeparator: { "，,、;；。.".contains($0) }).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return lead?.isEmpty == false ? lead : identity
    }
    /// A line can be voiced by an author recording or a preset TTS voice.
    public var hasPresetVoice: Bool { voiceMode == .preset && voicePreset != nil }

    /// E4: clues with no chapter, or whose chapter the run has reached, are known.
    /// Any clue text tied to an unreached chapter is counted, never shown.
    public func knownClues(reachedChapters: Set<Int>) -> [CastClue] {
        clues.filter { $0.chapterID.map(reachedChapters.contains) ?? true }
    }
    public func remainingClueCount(reachedChapters: Set<Int>) -> Int {
        lockedCount + clues.count - knownClues(reachedChapters: reachedChapters).count
    }
    public func endingLine(trust: Int) -> String? { endingLines[CastTrust.band(trust)] }

    init?(raw: PlayWireValue) {
        guard let id = Self.trimmed(raw["id"]), id.count <= 32,
              let name = Self.trimmed(raw["name"]), (1...8).contains(name.count) else { return nil }
        self.id = id; self.name = name
        identity = Self.trimmed(raw["identity"]).map { String($0.prefix(30)) }
        let avatar = Self.trimmed(raw["avatarUrl"])
        avatarURL = avatar.flatMap { $0.hasPrefix("https://") || $0.hasPrefix("media-asset:") ? $0 : nil }
        let color = Self.trimmed(raw["color"])?.uppercased()
        self.color = color.flatMap { Self.palette.contains($0) ? $0 : nil } ?? Self.neutralColor
        voiceMode = Self.trimmed(raw["voice"]["mode"]).flatMap(CastVoiceMode.init(rawValue:)) ?? .none
        let preset = Self.trimmed(raw["voice"]["preset"])
        voicePreset = ["bright_female", "warm_female", "deep_male", "youth", "elder"].contains(preset ?? "") ? preset : nil
        clues = (raw["clues"].array ?? []).prefix(6).compactMap { clue -> CastClue? in
            guard let text = Self.trimmed(clue["text"]), (1...40).contains(text.count) else { return nil }
            let chapter = clue["chapterId"].tolerantInteger
            return CastClue(text: text, chapterID: chapter.flatMap { $0 > 0 ? $0 : nil })
        }
        lockedCount = max(0, min(6, raw["lockedCount"].tolerantInteger ?? 0))
        var lines: [CastTrustBand: String] = [:]
        for band in [CastTrustBand.low, .mid, .high] {
            if let line = Self.trimmed(raw["endingLines"][band.rawValue]) { lines[band] = String(line.prefix(60)) }
        }
        endingLines = lines
    }
    static func trimmed(_ value: PlayWireValue) -> String? {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

public struct CastConfig: Equatable, Sendable {
    public let playerName: Bool
    public let playerIdentity: Bool
    public let identities: [CastIdentity]
    public let cast: [CastMember]

    /// Nil when the value is absent, null, malformed or `enabled` is not true: feature off.
    /// The JSON column may arrive as an object or as its JSON text.
    public init?(raw: PlayWireValue) {
        var value = raw
        if let text = raw.text, let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(PlayWireValue.self, from: data) { value = decoded }
        guard value.object != nil, value["enabled"].bool == true else { return nil }
        playerName = value["playerName"].bool == true
        playerIdentity = value["playerIdentity"].bool == true
        var keys = Set<String>()
        identities = (value["identities"].array ?? []).prefix(4).compactMap { row -> CastIdentity? in
            guard let key = CastMember.trimmed(row["key"]), let title = CastMember.trimmed(row["title"]),
                  keys.insert(key).inserted else { return nil }
            return CastIdentity(key: key, title: title, sub: CastMember.trimmed(row["sub"]))
        }
        var ids = Set<String>(), names = Set<String>()
        cast = (value["cast"].array ?? []).prefix(12).compactMap { row -> CastMember? in
            guard let member = CastMember(raw: row), member.id != "player",
                  ids.insert(member.id).inserted, names.insert(member.name).inserted else { return nil }
            return member
        }
    }
    public func member(_ id: String?) -> CastMember? { id.flatMap { id in cast.first { $0.id == id } } }
    /// Spec C: the identity question is asked only when there are identities to pick.
    public var asksIdentity: Bool { playerIdentity && !identities.isEmpty }
    public var asksPlayer: Bool { playerName || asksIdentity }
    /// The naming step shows once per run: never on resume, never without cast.
    public func needsStartStep(profile: CastPlayerProfile?) -> Bool { asksPlayer && profile == nil }
    public func identity(_ key: String?) -> CastIdentity? { key.flatMap { key in identities.first { $0.key == key } } }
}

/// The run's chosen player name and identity, stored by the server in run state.
public struct CastPlayerProfile: Equatable, Sendable {
    public let name: String?
    public let identityKey: String?
    public init(name: String?, identityKey: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed?.isEmpty == false ? String(trimmed!.prefix(12)) : nil
        let key = identityKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.identityKey = key?.isEmpty == false ? key : nil
    }
    /// A profile object counts as present even when the player kept the empty name,
    /// because 「出发」 with no name is a valid answer.
    public init?(raw: PlayWireValue) {
        guard raw.object != nil else { return nil }
        self.init(name: raw["name"].text, identityKey: raw["identityKey"].text)
    }
    /// Profile carried by a nodes/route/run-session payload, wherever the backend puts it.
    public static func find(in raw: PlayWireValue) -> CastPlayerProfile? {
        for candidate in [raw["playerProfile"], raw["routeState"]["playerProfile"], raw["state"]["playerProfile"], raw["routeState"]["profile"]] {
            if let profile = CastPlayerProfile(raw: candidate) { return profile }
        }
        return nil
    }
}

/// castId → trust. Clients only display trust; they never send it.
public struct CastTrust: Equatable, Sendable {
    public static let tickCount = 5
    public let values: [String: Int]
    public init(values: [String: Int] = [:]) { self.values = values }
    /// Accepts `{castId: n}` or `[{castId, trust|value}]`.
    public init(raw: PlayWireValue) {
        var values: [String: Int] = [:]
        if let object = raw.object {
            for (key, value) in object { if let n = value.tolerantInteger { values[key] = n } }
        } else {
            for row in raw.array ?? [] {
                if let id = CastMember.trimmed(row["castId"]), let n = (row["trust"] == .null ? row["value"] : row["trust"]).tolerantInteger { values[id] = n }
            }
        }
        self.values = values
    }
    public subscript(_ castID: String) -> Int { values[castID] ?? 0 }
    public var isEmpty: Bool { values.values.allSatisfy { $0 == 0 } }
    /// Five ticks: positive trust fills one tick per point; zero and negative fill none.
    public static func filledTicks(_ trust: Int) -> Int { max(0, min(tickCount, trust)) }
    /// Ending-line band. Provisional thresholds until the backend lane publishes its own.
    public static func band(_ trust: Int) -> CastTrustBand { trust < 0 ? .low : (trust >= 3 ? .high : .mid) }
    public static func find(in raw: PlayWireValue) -> CastTrust {
        for candidate in [raw["trust"], raw["routeState"]["trust"], raw["state"]["trust"]] where candidate != .null {
            return CastTrust(raw: candidate)
        }
        return CastTrust()
    }
}

/// D2 / E6: what the run result says about trust and whose ending was reached.
public struct CastEndingResult: Equatable, Sendable {
    public let trust: CastTrust
    public let endingFor: String?
    public let endingCount: Int?
    public init(trust: CastTrust, endingFor: String? = nil, endingCount: Int? = nil) {
        self.trust = trust; self.endingFor = endingFor; self.endingCount = endingCount
    }
    public init(raw: PlayWireValue) {
        trust = CastTrust.find(in: raw)
        endingFor = CastMember.trimmed(raw["endingFor"])
        endingCount = raw["endingCount"].tolerantInteger.flatMap { $0 > 0 ? $0 : nil }
    }
    /// E6 rows: each character with non-zero trust, in cast order.
    public func rows(_ config: CastConfig) -> [CastEndingRow] {
        config.cast.compactMap { member -> CastEndingRow? in
            let value = trust[member.id]
            return value == 0 ? nil : CastEndingRow(member: member, trust: value, line: member.endingLine(trust: value))
        }
    }
}
public struct CastEndingRow: Equatable, Identifiable, Sendable {
    public let member: CastMember
    public let trust: Int
    /// Optional `endingLines` entry for the trust band; nil shows nothing extra.
    public let line: String?
    public var id: String { member.id }
}

/// D2 trust deltas carried by a branch option, clamped to −2…2.
public struct CastTrustDelta: Equatable, Sendable {
    public let castID: String
    public let delta: Int
    public static func read(_ raw: PlayWireValue) -> [CastTrustDelta] {
        (raw.array ?? []).compactMap { row -> CastTrustDelta? in
            guard let id = CastMember.trimmed(row["castId"]), let delta = row["delta"].tolerantInteger, delta != 0 else { return nil }
            return CastTrustDelta(castID: id, delta: max(-2, min(2, delta)))
        }
    }
    /// E3 「{name}会记住这件事」: the cast members an option's trust change touches.
    public static func remembered(_ deltas: [CastTrustDelta], config: CastConfig?) -> [CastMember] {
        guard let config else { return [] }
        var seen = Set<String>()
        return deltas.compactMap { delta in seen.insert(delta.castID).inserted ? config.member(delta.castID) : nil }
    }
}

/// E3: the player's last branch pick, when the backend echoes it in the branch state.
/// Absent echo means nothing extra is shown; the client never infers a pick on its own.
public struct CastBranchEcho: Equatable, Sendable {
    public let label: String
    public let trust: [CastTrustDelta]
    public init?(branch: PlayWireValue) {
        let last = branch["lastChoice"] != .null ? branch["lastChoice"] : (branch["history"].array?.last ?? .null)
        guard let label = CastMember.trimmed(last["label"]) ?? CastMember.trimmed(last["optionLabel"]) else { return nil }
        self.label = label
        trust = CastTrustDelta.read(last["trust"])
    }
}

/// Fills the cast story variables in authored text. Applied only when cast is on.
public enum CastStoryVariables {
    public static let playerFallback = "你"
    public static func fill(_ text: String, profile: CastPlayerProfile?, config: CastConfig) -> String {
        guard text.contains("{玩家}") || text.contains("{身份}") else { return text }
        let identity = config.identity(profile?.identityKey)?.title ?? ""
        return text.replacingOccurrences(of: "{玩家}", with: profile?.name ?? playerFallback)
            .replacingOccurrences(of: "{身份}", with: identity)
    }
}

/// Everything the chapter projection needs to resolve speakers.
public struct CastStoryContext: Equatable, Sendable {
    public let config: CastConfig
    public let profile: CastPlayerProfile?
    public init(config: CastConfig, profile: CastPlayerProfile?) { self.config = config; self.profile = profile }
}
