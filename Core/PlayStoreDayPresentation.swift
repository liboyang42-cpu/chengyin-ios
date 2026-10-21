import Foundation

/// Mini-program pages/play/merchant projection of one shop-day (mode 2) node row from
/// /api/play/nodes, or of that row merged with a checkin/photo receipt (source Object.assign).
/// Missing facts stay unknown; nothing here invents coordinates, waits or rewards.
public struct PlayStoreDayNode: Equatable, Identifiable {
    public let raw: [String: PlayWireValue]
    public let id: Int
    public let name: String?
    public let address: String?
    public let heroImage: String?
    public let merchantID: Int?
    public let latitude: Double?
    public let longitude: Double?
    public let businessTime: String?
    public let openStatus: String?
    public let crowded: Bool?
    public let inStoreLoad: Int?
    public let servicePerHour: Double?
    public let expectedWaitMinutes: Int?
    public let quantityUnavailable: Bool
    public let rule: String?
    public let photoDescription: String?
    public let arrived: Bool
    public let selfReported: Bool
    public let done: Bool
    public let gameDone: Bool
    public let hasGame: Bool
    public let hasAdvanced: Bool
    public let validationMethod: Int
    public let gameTitle: String?
    public let question: String?
    /// Server option keys (A-D) in key order; nil means free-text answer.
    public let options: [PlayStoreDayOption]?

    public init?(row: PlayWireValue) {
        guard let object = row.object else { return nil }
        self.init(raw: object)
    }
    init?(raw: [String: PlayWireValue]) {
        guard let id = raw["nodeId"]?.tolerantInteger, id > 0 else { return nil }
        func text(_ keys: String...) -> String? {
            for key in keys { if let value = raw[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value } }
            return nil
        }
        func flag(_ key: String) -> Bool { raw[key]?.bool == true }
        self.raw = raw; self.id = id
        name = text("name"); address = text("address")
        heroImage = text("imgUrl").flatMap { $0.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } }.flatMap { $0.isEmpty ? nil : $0 }
        merchantID = raw["merchantId"]?.tolerantInteger.flatMap { $0 > 0 ? $0 : nil }
        latitude = Self.coordinate(raw["latitude"] ?? raw["lat"]); longitude = Self.coordinate(raw["longitude"] ?? raw["lng"])
        businessTime = text("businessTime"); openStatus = text("openStatus")
        crowded = raw["crowded"]?.bool
        inStoreLoad = raw["inStoreLoad"]?.tolerantInteger
        servicePerHour = raw["serviceCapacity"]?["perHour"].double
        expectedWaitMinutes = raw["expectedWaitMinutes"]?.tolerantInteger ?? raw["expectedWaitMinutes"]?.double.map { Int($0.rounded()) }
        quantityUnavailable = flag("quantityUnavailable")
        // Receipt names (rule/photoDesc) win over list names, like the source merge.
        rule = text("rule", "ruleInstructions"); photoDescription = text("photoDesc", "photoRequireDesc")
        arrived = flag("arrived"); selfReported = flag("selfReported"); done = flag("done"); gameDone = flag("gameDone")
        hasGame = flag("hasGame")
        validationMethod = raw["validationMethod"]?.tolerantInteger ?? raw["vm"]?.tolerantInteger ?? 0
        hasAdvanced = flag("hasAdvanced") || Self.advancedEnabled(raw["advancedConfigJson"])
        gameTitle = text("gameTitle"); question = text("question")
        if let object = raw["options"]?.object {
            let rows = object.keys.sorted().compactMap { key in object[key]?.text.map { PlayStoreDayOption(key: key, text: $0) } }
            options = rows.isEmpty ? nil : rows
        } else { options = nil }
    }
    private static func coordinate(_ value: PlayWireValue?) -> Double? {
        guard let value else { return nil }
        if let number = value.double { return number.isFinite ? number : nil }
        return value.text.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
    }
    private static func advancedEnabled(_ value: PlayWireValue?) -> Bool {
        let config: PlayWireValue?
        if let text = value?.text, let data = text.data(using: .utf8) { config = try? JSONDecoder().decode(PlayWireValue.self, from: data) }
        else { config = value?.object == nil ? nil : value }
        guard let object = config?.object else { return false }
        return object.contains { key, segment in key != "schemaVersion" && segment["enabled"].bool == true }
    }
    /// Source `Object.assign({}, node, response.data)`; nodeId cannot be rebound.
    public func merging(_ patch: PlayWireValue) -> PlayStoreDayNode {
        guard var incoming = patch.object else { return self }
        incoming["nodeId"] = raw["nodeId"]
        return PlayStoreDayNode(raw: raw.merging(incoming) { _, new in new }) ?? self
    }
    /// Source landed check after an uncertain proof write.
    public func proofLanded(after fresh: PlayStoreDayNode) -> Bool {
        (fresh.done && !done) || (fresh.arrived && !arrived) || (fresh.selfReported && !selfReported)
    }
    public var hasCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        return latitude != 0 && longitude != 0 && abs(latitude) <= 90 && abs(longitude) <= 180
    }
    public var isPreferenceGame: Bool { validationMethod == 6 }
}
public struct PlayStoreDayOption: Equatable, Identifiable {
    public let key: String
    public let text: String
    public var id: String { key }
}

/// Source play-open-state.js: server tri-state wins, then a businessTime window, else hidden.
public enum PlayStoreDayOpenText: Equatable {
    case server(String), open, closed
    public static func resolve(openStatus: String?, businessTime: String?, nowMinutes: Int) -> Self? {
        if let openStatus, !openStatus.isEmpty { return .server(openStatus) }
        guard let window = businessWindow(businessTime, nowMinutes: nowMinutes) else { return nil }
        return window ? .open : .closed
    }
    /// Port of utils/geo.js bizWindowState; nil when the text has no HH:MM-HH:MM window.
    public static func businessWindow(_ text: String?, nowMinutes: Int) -> Bool? {
        guard let text, let regex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})\s*[-~—至]\s*(\d{1,2}):(\d{2})"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges == 5 else { return nil }
        let parts = (1...4).compactMap { index -> Int? in Range(match.range(at: index), in: text).flatMap { Int(text[$0]) } }
        guard parts.count == 4 else { return nil }
        let start = parts[0] * 60 + parts[1], end = parts[2] * 60 + parts[3]
        return end >= start ? (nowMinutes >= start && nowMinutes <= end) : (nowMinutes >= start || nowMinutes <= end)
    }
}

public enum PlayStoreDayHeaderTag: String, Equatable {
    case redeemed, photoRecorded, arrived, pending
    public init(_ node: PlayStoreDayNode) {
        self = node.done ? .redeemed : node.selfReported ? .photoRecorded : node.arrived ? .arrived : .pending
    }
}
public enum PlayStoreDayCrowd: String, Equatable {
    case queue, go, unknown
    public init(_ node: PlayStoreDayNode) { self = node.crowded == true ? .queue : node.crowded == false ? .go : .unknown }
}
public enum PlayStoreDayReceipt: String, Equatable {
    case ready, submitting, confirmed, unknown, failed
    public var holdsLock: Bool { self == .submitting || self == .unknown }
}
/// Bottom primary button priority, exactly as the source wx:if chain.
public enum PlayStoreDayPrimaryAction: String, Equatable {
    case confirmPending, scan, photo, verify, redeemed
    public static func resolve(_ node: PlayStoreDayNode, receipt: PlayStoreDayReceipt) -> Self {
        if receipt == .unknown { return .confirmPending }
        if !node.arrived { return .scan }
        if !node.selfReported { return .photo }
        return node.done ? .redeemed : .verify
    }
}
/// Experience layer after arrival: advanced → play host, vm6 → play host, quiz → sheet, else task card.
public enum PlayStoreDayPopup: Equatable {
    case none, advancedHandoff, preferenceHandoff, quiz, taskCard
    public static func resolve(_ node: PlayStoreDayNode) -> Self {
        guard node.arrived, !node.done else { return .none }
        if node.hasAdvanced { return .advancedHandoff }
        if node.hasGame && node.isPreferenceGame { return .preferenceHandoff }
        if node.hasGame && node.question != nil { return .quiz }
        return .taskCard
    }
}
public enum PlayStoreDayConsentState: String, Equatable {
    case unknown = "UNKNOWN", none = "NONE", agree = "AGREE", revoke = "REVOKE", unavailable = "UNAVAILABLE"
}
public enum PlayStoreDayConsent {
    public static func subject(merchantID: Int) -> ComplianceSubject { .merchantOnsite(authoritativeMerchantID: merchantID) }
    /// Source `merchant-${eventType.toLowerCase()}-${merchantId}-${Date.now()}`.
    public static func requestID(event: ComplianceEvent, merchantID: Int, milliseconds: Int64) -> String? {
        guard merchantID > 0, milliseconds >= 0 else { return nil }
        let id = "merchant-\(event.rawValue.lowercased())-\(merchantID)-\(milliseconds)"
        return id.count <= 64 ? id : nil
    }
    /// Empty latest data means NONE; a record must match doc, scene, MERCHANT scope and merchant.
    public static func state(latest: ComplianceConsent?, merchantID: Int) -> PlayStoreDayConsentState {
        guard let latest else { return .none }
        let subject = subject(merchantID: merchantID)
        guard latest.docType == subject.docType, latest.scopeType == subject.scopeType, latest.scopeId == merchantID else { return .unavailable }
        switch latest.eventType { case "AGREE": return .agree; case "REVOKE": return .revoke; case nil: return .none; default: return .unavailable }
    }
}
/// Answer receipt display: reward only on first completion (firstTime !== false).
public struct PlayStoreDayAnswerResult: Equatable {
    public let message: String?
    public let firstTime: Bool
    public let experience: Int?
    /// Authoritative /nodes gameDone after an uncertain answer: state only, no reward detail.
    public let confirmedByReadback: Bool
    public init(message: String?, data: PlayWireValue) {
        self.message = message.flatMap { $0.isEmpty ? nil : $0 }
        firstTime = data["firstTime"].bool != false
        let xp = data["xp"].tolerantInteger ?? data["score"].tolerantInteger
        experience = firstTime ? xp.flatMap { $0 > 0 ? $0 : nil } : nil
        confirmedByReadback = false
    }
    private init() { message = nil; firstTime = false; experience = nil; confirmedByReadback = true }
    public static var readbackRecorded: Self { Self() }
}
