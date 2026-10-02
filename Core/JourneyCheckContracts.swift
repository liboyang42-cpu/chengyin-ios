import Foundation

/// Source: play_check.dart. Optional server numbers never become invented zero readings.
public struct JourneyCheckMod: Equatable {
    public let label: String; public let value: Int?; public let active: Bool
    init(_ raw: PlayWireValue) {
        label = raw["label"].text ?? ""; value = raw["value"].tolerantInteger
        active = raw["held"].journeyBool == true || raw["applied"].journeyBool == true
    }
}
extension PlayWireValue {
    var journeyBool: Bool? { bool ?? text.flatMap { $0 == "true" ? true : ($0 == "false" ? false : nil) } }
    var journeyDouble: Double? { double ?? text.flatMap(Double.init) }
}
public struct JourneyCheckProblem: Equatable {
    public let checkID: String; public let skill: String; public let tier: String
    public let mods: [JourneyCheckMod]; public let advantage: Bool; public let disadvantage: Bool
    public init?(encounter: PlayWireValue) {
        let raw = encounter["check"]
        let id = (raw["checkId"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard encounter["allowedActions"].array?.contains(.string("check")) == true, !id.isEmpty else { return nil }
        checkID = id; skill = raw["skill"].text ?? ""; tier = raw["tier"].text ?? ""
        mods = (raw["mods"].array ?? []).filter { $0.object != nil }.map(JourneyCheckMod.init)
        advantage = raw["advantage"].journeyBool == true; disadvantage = raw["disadvantage"].journeyBool == true
    }
}
public struct JourneyCheckReceipt: Equatable {
    public let tier: String; public let dc: Int?; public let dice: [Int]; public let kept: Int?; public let total: Int?
    public let success: Bool?; public let nat: String; public let rerolled: Bool; public let settled: Bool
    public let text: String; public let failCostLabel: String; public let hp: Int?; public let luck: Int?
    public let exhausted: Bool; public let mods: [JourneyCheckMod]
    public init(_ raw: PlayWireValue) throws {
        guard raw.object != nil, let settled = raw["settled"].journeyBool,
              let rerolled = raw["rerolled"].journeyBool else { throw PlayExperienceError.malformed }
        self.settled = settled; self.rerolled = rerolled
        tier = raw["tier"].text ?? ""; dc = raw["dc"].tolerantInteger
        dice = (raw["dice"].array ?? []).compactMap(\.tolerantInteger)
        kept = raw["kept"].tolerantInteger; total = raw["total"].tolerantInteger
        success = raw["success"].journeyBool; nat = raw["nat"].text ?? ""
        // A premature server field must not leak settlement narrative before settlement.
        text = settled ? (raw["text"].text ?? "") : ""
        failCostLabel = settled ? (raw["failCostLabel"].text ?? "") : ""
        hp = raw["hp"].tolerantInteger; luck = raw["luck"].tolerantInteger
        exhausted = raw["exhausted"].journeyBool == true
        mods = (raw["mods"].array ?? []).filter { $0.object != nil }.map(JourneyCheckMod.init)
    }
    public var canReroll: Bool { !settled && !rerolled && (luck ?? 0) > 0 }
}
public enum JourneyCheckAction: String, CaseIterable { case roll, reroll, settle }
public struct JourneyCheckReview: Equatable, Identifiable {
    public let id: UUID; public let session: PlayExperienceSession; public let topicID: Int; public let nodeID: Int
    public let checkID: String; public let action: JourneyCheckAction; public let receipt: JourneyCheckReceipt?
    init(session: PlayExperienceSession, topicID: Int, nodeID: Int, checkID: String, action: JourneyCheckAction, receipt: JourneyCheckReceipt?) {
        id = UUID(); self.session = session; self.topicID = topicID; self.nodeID = nodeID
        self.checkID = checkID; self.action = action; self.receipt = receipt
    }
}
public struct JourneyEgg: Equatable, Identifiable, Decodable {
    public let id: Int; public let latitude: Double; public let longitude: Double; public let radius: Double; public let text: String
    public init?(raw: PlayWireValue) {
        guard let id = raw["id"].tolerantInteger, id > 0,
              let lat = raw["lat"].journeyDouble, let lng = raw["lng"].journeyDouble,
              lat.isFinite, lng.isFinite, abs(lat) <= 90, abs(lng) <= 180, lat != 0, lng != 0,
              let text = raw["text"].text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let radius = raw["radius"].journeyDouble ?? 120
        guard radius.isFinite else { return nil }
        self.id = id; latitude = lat; longitude = lng; self.radius = min(1000, max(1, radius)); self.text = text
    }
    public init(from decoder: Decoder) throws {
        guard let value = Self(raw: try PlayWireValue(from: decoder)) else { throw APIError.malformedResponse }; self = value
    }
    public static func project(_ raw: PlayWireValue) -> [Self] {
        var ids: Set<Int> = []
        return (raw.array ?? []).compactMap(Self.init(raw:)).filter { ids.insert($0.id).inserted }
    }
}
