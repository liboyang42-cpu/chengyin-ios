import Foundation

/// Mini-program `pages/merchant/decor/ai-npc` (AI 店铺角色) contracts. Every route is a JSON POST.
public enum StoreCharacterEndpoint {
    public static let access = "api/merchant/access/me"
    public static let profile = "api/merchant/npc/profile"
    public static let save = "api/merchant/npc/save"
    public static let voiceStatus = "api/merchant/npc/voice/status"
    public static let voiceEnroll = "api/merchant/npc/voice/enroll"
    public static let consent = "api/compliance/consents"
    public static let mapPointRead = "api/merchant/coop-profile"
    public static let mapPointSave = "api/merchant/decor/save"
    public static let reads: [String] = [access, profile, voiceStatus, mapPointRead]
    public static let writes: [String] = [save, consent, voiceEnroll, mapPointSave]
    /// Required by the page gate (`need="canWriteProfile"`) and by every npc route on the server.
    public static let requiredPermission = "merchant:profile:write"
}

/// JavaScript String.prototype.trim(), which the source applies before every save.
public enum StoreCharacterText {
    static let whitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    public static func trim(_ value: String) -> String { value.trimmingCharacters(in: whitespace) }
    /// Source `maxlength` and counters use JavaScript length, i.e. UTF-16 code units.
    public static func length(_ value: String) -> Int { value.utf16.count }
    /// `maxlength` behaviour: keep whole characters until the UTF-16 limit is reached.
    public static func clamp(_ value: String, limit: Int) -> String {
        guard length(value) > limit else { return value }
        var result = "", used = 0
        for character in value {
            let size = String(character).utf16.count
            guard used + size <= limit else { break }
            result.append(character); used += size
        }
        return result
    }
}

public enum StoreCharacterField: String, CaseIterable, Identifiable, Sendable {
    case name, greeting, persona, knowledge
    public var id: String { rawValue }
    public var limit: Int {
        switch self { case .name: return 32; case .greeting: return 60; case .persona: return 500; case .knowledge: return 2000 }
    }
    public var multiline: Bool { self == .persona || self == .knowledge }
}

public enum StoreCharacterAvatar: Equatable, Sendable {
    case preset(String)
    case photo(String)
    public static let defaultPresetID = "p01"
    public static var presetIDs: [String] { MerchantNPCPresetAvatar.all.map(\.id) }
    /// Mirrors server NpcAvatar.isAllowed: a known preset code, a site path or an http(s) URL.
    public init?(code: String) {
        guard !code.isEmpty else { return nil }
        if let preset = MerchantNPCPresetAvatar.matching(code: code) { self = .preset(preset.id); return }
        guard !code.hasPrefix("px1:"), code.hasPrefix("/") || code.hasPrefix("https://") || code.hasPrefix("http://") else { return nil }
        self = .photo(code)
    }
    public var code: String {
        switch self { case .preset(let id): return "px1:" + id; case .photo(let url): return url }
    }
    public var preset: MerchantNPCPresetAvatar? {
        if case .preset(let id) = self { return MerchantNPCPresetAvatar.matching(id: id) }
        return nil
    }
}

public enum StoreCharacterBadge: Equatable, Sendable { case online, rejected, reviewing }

public struct StoreCharacterProfile: Equatable, Sendable {
    public var name = ""
    public var avatar = ""
    public var greeting = ""
    public var persona = ""
    public var knowledge = ""
    public var auditStatus: Int?
    public var auditReason = ""
    /// nil when the reader cannot confirm the voice status (never shown as configured).
    public var voiceStatus: Int?
    public init() {}
    public static let empty = StoreCharacterProfile()
    public var hasProfile: Bool { !avatar.isEmpty }
    public var badge: StoreCharacterBadge? {
        guard hasProfile else { return nil }
        switch auditStatus { case 1?: return .online; case 2?: return .rejected; default: return .reviewing }
    }
    public var rejectionReason: String? { auditStatus == 2 && !auditReason.isEmpty ? auditReason : nil }
    public subscript(field: StoreCharacterField) -> String {
        get {
            switch field { case .name: return name; case .greeting: return greeting; case .persona: return persona; case .knowledge: return knowledge }
        }
        set {
            switch field { case .name: name = newValue; case .greeting: greeting = newValue; case .persona: persona = newValue; case .knowledge: knowledge = newValue }
        }
    }
    public func sameText(_ other: StoreCharacterProfile) -> Bool {
        StoreCharacterField.allCases.allSatisfy { self[$0] == other[$0] }
    }
    /// The source `persistProfile` body: all five fields, the avatar from the caller.
    public func payload(avatar: String) -> StoreCharacterSavePayload {
        .init(name: name, greeting: greeting, persona: persona, knowledge: knowledge, avatar: avatar)
    }
    /// The state the source shows after an acknowledged save (audit resets to reviewing).
    public static func acknowledged(_ payload: StoreCharacterSavePayload, voiceStatus: Int?) -> Self {
        var value = Self()
        value.name = payload.name; value.greeting = payload.greeting; value.persona = payload.persona
        value.knowledge = payload.knowledge; value.avatar = payload.avatar; value.auditStatus = 0; value.voiceStatus = voiceStatus
        return value
    }
}

extension StoreCharacterProfile: Decodable {
    private enum CodingKeys: String, CodingKey { case name, avatar, greeting, persona, knowledge, auditStatus, auditReason, voiceStatus }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar)) ?? ""
        greeting = (try? c.decodeIfPresent(String.self, forKey: .greeting)) ?? ""
        persona = (try? c.decodeIfPresent(String.self, forKey: .persona)) ?? ""
        knowledge = (try? c.decodeIfPresent(String.self, forKey: .knowledge)) ?? ""
        auditStatus = c.merchantInteger(.auditStatus)
        auditReason = (try? c.decodeIfPresent(String.self, forKey: .auditReason)) ?? ""
        voiceStatus = c.merchantInteger(.voiceStatus) ?? 0
    }
}

public enum StoreCharacterBlocker: String, CaseIterable, Sendable {
    case nameRequired, nameTooLong, greetingTooLong, personaTooLong, knowledgeTooLong, avatarRequired, avatarUnsupported
}

/// Exact `npc/save` JSON body. Values are trimmed once at construction.
public struct StoreCharacterSavePayload: Equatable, Sendable {
    public let name: String
    public let greeting: String
    public let persona: String
    public let knowledge: String
    public let avatar: String
    public init(name: String, greeting: String, persona: String, knowledge: String, avatar: String) {
        self.name = StoreCharacterText.trim(name); self.greeting = StoreCharacterText.trim(greeting)
        self.persona = StoreCharacterText.trim(persona); self.knowledge = StoreCharacterText.trim(knowledge)
        self.avatar = StoreCharacterText.trim(avatar)
    }
    public var blocker: StoreCharacterBlocker? {
        if name.isEmpty { return .nameRequired }
        if StoreCharacterText.length(name) > StoreCharacterField.name.limit { return .nameTooLong }
        if StoreCharacterText.length(greeting) > StoreCharacterField.greeting.limit { return .greetingTooLong }
        if StoreCharacterText.length(persona) > StoreCharacterField.persona.limit { return .personaTooLong }
        if StoreCharacterText.length(knowledge) > StoreCharacterField.knowledge.limit { return .knowledgeTooLong }
        if avatar.isEmpty { return .avatarRequired }
        if StoreCharacterAvatar(code: avatar) == nil || avatar.utf16.count > 255 { return .avatarUnsupported }
        return nil
    }
    public var fields: [String: String] {
        ["name": name, "greeting": greeting, "persona": persona, "knowledge": knowledge, "avatar": avatar]
    }
    public func jsonBody() throws -> Data {
        guard blocker == nil else { throw APIError.invalidRequest }
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
    /// Authoritative readback check after an uncertain save.
    public func matches(_ profile: StoreCharacterProfile) -> Bool {
        profile.name == name && profile.greeting == greeting && profile.persona == persona
            && profile.knowledge == knowledge && profile.avatar == avatar
    }
}

/// `npc/voice/status` and `npc/voice/enroll` put `voiceStatus`/`voiceSample` at the TOP level.
public struct StoreCharacterVoiceState: Equatable, Sendable {
    public enum Status: Int, Sendable { case none = 0, pending = 1, ready = 2, failed = 3 }
    public let status: Status
    public let sample: String?
    public init(status: Status, sample: String?) { self.status = status; self.sample = sample }
}

/// Map point projection from coop-profile. The judge is coordinates, never the address alone.
public struct StoreCharacterMapPointState: Equatable, Sendable {
    public let hasPoint: Bool
    public let address: String
    public init(hasPoint: Bool, address: String) { self.hasPoint = hasPoint; self.address = address }
    public static let unset = StoreCharacterMapPointState(hasPoint: false, address: "")
    /// nil means "show 已选择地图位置"; `.unset` (and every read error) means "尚未选择地图位置".
    public var displayAddress: String? { hasPoint && !address.isEmpty ? address : nil }
}

extension StoreCharacterMapPointState: Decodable {
    private enum CodingKeys: String, CodingKey { case locationLat, locationLng, address }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func present(_ key: CodingKeys) -> Bool {
            guard c.contains(key), (try? c.decodeNil(forKey: key)) == false else { return false }
            if let text = try? c.decode(String.self, forKey: key) { return !text.isEmpty }
            return (try? c.decode(Double.self, forKey: key)) != nil
        }
        hasPoint = present(.locationLat) && present(.locationLng)
        address = (try? c.decodeIfPresent(String.self, forKey: .address)) ?? ""
    }
}

/// `decor/save` body for the roaming map point. Coordinates come only from a picker result.
public struct StoreCharacterMapPointWrite: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let address: String
    public init?(latitude: Double, longitude: Double, address: String) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude),
              address.utf16.count <= 255 else { return nil }
        self.latitude = latitude; self.longitude = longitude; self.address = address
    }
    public func jsonBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["locationLat": latitude, "locationLng": longitude, "address": address], options: [.sortedKeys])
    }
}

/// Separate consent recorded before enrollment (`voice_clone_processing` / `merchant_voice`).
/// The request ID is generated once per prepared enrollment and reused on retry.
public struct StoreCharacterVoiceConsentRecord: Equatable, Sendable {
    public static let docType = "voice_clone_processing"
    public static let scene = "merchant_voice"
    public static let eventType = "AGREE"
    public let requestID: String
    public init(requestID: UUID) { self.requestID = "consent-" + requestID.uuidString.lowercased() }
    public var fields: [String: String] {
        ["docType": Self.docType, "scene": Self.scene, "eventType": Self.eventType, "requestId": requestID]
    }
    public func jsonBody() throws -> Data { try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) }
    /// The source accepts only a row echoing this request with a non-empty document version.
    public func accepts(_ row: StoreCharacterConsentRow?) -> Bool {
        guard let row else { return false }
        return row.requestId == requestID && row.docType == Self.docType && row.scene == Self.scene
            && row.eventType == Self.eventType && !(row.docVersion ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public struct StoreCharacterConsentRow: Decodable, Equatable, Sendable {
    public let requestId: String?
    public let docType: String?
    public let scene: String?
    public let eventType: String?
    public let docVersion: String?
}

/// `npc/voice/enroll` body: `{voiceSample, voiceConsent:true}`. The sample must be an uploaded reference.
public struct StoreCharacterVoiceEnrollment: Equatable, Sendable {
    public let voiceSample: String
    public init?(voiceSample: String) {
        let sample = voiceSample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty, sample.utf8.count <= 4096,
              sample.hasPrefix("https://") || sample.hasPrefix("http://") || sample.hasPrefix("/") || Self.isMediaAsset(sample) else { return nil }
        self.voiceSample = sample
    }
    private static func isMediaAsset(_ value: String) -> Bool {
        guard value.hasPrefix("media-asset:") else { return false }
        let digits = value.dropFirst("media-asset:".count)
        return (1...19).contains(digits.count) && digits.first != "0" && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
    public func jsonBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["voiceSample": voiceSample, "voiceConsent": true], options: [.sortedKeys])
    }
}

public enum StoreCharacterDenyReason: Equatable, Sendable {
    /// 当前账号不是商家成员
    case notMember
    /// 当前岗位没有这项权限
    case missingPermission
    /// 当前账号没有查看权限
    case noViewPermission
}

public enum StoreCharacterAccessDecision: Equatable, Sendable {
    case allow(cooperationManage: Bool)
    case login
    case deny(StoreCharacterDenyReason)
    case unknown

    public static func decide(_ access: MerchantOperationsAccess) -> Self {
        guard access.identity.active else { return .deny(.notMember) }
        guard access.profileWrite else { return .deny(.missingPermission) }
        return .allow(cooperationManage: access.cooperationManage)
    }
    public static func decide(error: Error) -> Self {
        if error as? APIError == .unauthorized || error as? StoreCharacterFailure == .unauthorized { return .login }
        if error as? MerchantOperationsFailure == .accessDenied || error as? StoreCharacterFailure == .accessDenied { return .deny(.noViewPermission) }
        if case .rejected(let code, _)? = error as? StoreCharacterFailure, code == 401 || code == 403 { return .deny(.notMember) }
        return .unknown
    }
}

/// The three source recording prompts (one continuous recording, paused between sentences).
public enum StoreCharacterVoiceScript {
    public static let sentenceCount = 3
    public static let minimumSeconds = 10
    public static let maximumBytes = 10 * 1024 * 1024
}

/// A recording handed in by an approved recorder/uploader. This build never captures audio;
/// only the offline fixture supplies a synthetic, already-uploaded sample reference.
public struct StoreCharacterRecordedSample: Equatable, Sendable {
    public let url: String
    public let durationSeconds: Int
    public let byteCount: Int
    public init?(url: String, durationSeconds: Int, byteCount: Int) {
        guard StoreCharacterVoiceEnrollment(voiceSample: url) != nil, durationSeconds >= StoreCharacterVoiceScript.minimumSeconds,
              byteCount > 0, byteCount <= StoreCharacterVoiceScript.maximumBytes else { return nil }
        self.url = url; self.durationSeconds = durationSeconds; self.byteCount = byteCount
    }
}
