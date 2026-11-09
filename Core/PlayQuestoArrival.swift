import Foundation

// Arrival reasons and reading (spec U05-01, §23.2, §27.3) and client capability declaration
// (U04-03, §27.2). Sources on integrate/questo-ui-20261110: PlayBasicCommandApplication
// .arriveRejected / arrivalReading, PlayCommandErrorContract, ArriveLocationGuard,
// ContentCapabilityRequirements.Declaration / compatibility.

// MARK: - Arrival

/// Stable reason codes. The message is mirrored verbatim; logic never parses Chinese text.
public enum PlayArrivalReason: Equatable {
    case locationMissing, locationInvalid, accuracyMissing, accuracyInvalid, accuracyLow
    case tooFar, locationStale, notRecorded, coordinateNotConfigured, arriveFirst
    case other(String)
    public init(code: String) {
        switch code {
        case "ARRIVE_LOCATION_MISSING": self = .locationMissing
        case "ARRIVE_LOCATION_INVALID": self = .locationInvalid
        case "ARRIVE_ACCURACY_MISSING": self = .accuracyMissing
        case "ARRIVE_ACCURACY_INVALID": self = .accuracyInvalid
        case "ARRIVE_ACCURACY_LOW": self = .accuracyLow
        case "ARRIVE_TOO_FAR": self = .tooFar
        case "ARRIVE_LOCATION_STALE": self = .locationStale
        case "ARRIVE_NOT_RECORDED": self = .notRecorded
        case "ARRIVE_COORD_NOT_CONFIGURED": self = .coordinateNotConfigured
        case "ARRIVE_FIRST": self = .arriveFirst
        default: self = .other(code)
        }
    }
    /// Localisation suffix for the reason title; `.other` falls back to the server message.
    public var key: String? {
        switch self {
        case .locationMissing: return "locationMissing"; case .locationInvalid: return "locationInvalid"
        case .accuracyMissing: return "accuracyMissing"; case .accuracyInvalid: return "accuracyInvalid"
        case .accuracyLow: return "accuracyLow"; case .tooFar: return "tooFar"; case .locationStale: return "locationStale"
        case .notRecorded: return "notRecorded"; case .coordinateNotConfigured: return "coordinateNotConfigured"
        case .arriveFirst: return "arriveFirst"; case .other: return nil
        }
    }
}

/// A refused `/api/play/arrive`. The next step is decided by server flags only.
public struct PlayArrivalRefusal: Equatable {
    public let reason: PlayArrivalReason
    public let message: String?
    /// `canRetry` (= `retryable`): 重新定位 may retry the ORIGINAL intent.
    public let canRetry: Bool
    /// Only server-approved real nodes; never author `fallbackMode`. Node ids, not labels.
    public let approvedFallbackNodeIDs: [String]
    public let refreshRequired: Bool
    public let newActionIDRequired: Bool

    /// Envelope = whole AjaxResult body (`code != 200`). Returns nil if it is not an arrival refusal.
    public init?(envelope: PlayWireValue) {
        guard let code = envelope["arrivalReasonCode"].text ?? envelope["errorCode"].text, !code.isEmpty else { return nil }
        reason = PlayArrivalReason(code: code); message = envelope["msg"].text
        canRetry = envelope["canRetry"].bool ?? (envelope["retryable"].bool == true)
        var seen = Set<String>()
        approvedFallbackNodeIDs = (envelope["approvedFallbacks"].array ?? []).compactMap { $0.text ?? $0.integer.map({ String($0) }) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        refreshRequired = envelope["refreshRequired"].bool == true
        newActionIDRequired = envelope["newActionIdRequired"].bool == true
    }
}

/// `data.arrivalReading{level 0..3, log}` on a real arrival success only.
public struct PlayArrivalReading: Equatable {
    public let level: Int
    public let log: String
    public init?(data: PlayWireValue) {
        let raw = data["arrivalReading"]
        guard let level = raw["level"].integer, (0...3).contains(level), let log = raw["log"].text,
              !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.level = level; self.log = log
    }
}

/// Plays an arrival reading once per arrival receipt. An unknown result re-read with the same
/// receipt never replays it; a skip produces no reading at all.
public struct PlayArrivalReadingLedger: Equatable {
    private var played: Set<String> = []
    public init() {}
    /// Returns true exactly once for a given (run, node, receipt) key.
    public mutating func shouldPlay(runID: String, nodeID: Int, receipt: String) -> Bool {
        played.insert(runID + "|" + String(nodeID) + "|" + receipt).inserted
    }
    public mutating func reset() { played = [] }
}

/// `locationTimestamp`: epoch milliseconds string of the location sample, only sent when known.
public enum PlayArrivalFields {
    public static func locationTimestamp(_ sampledAt: Date?) -> [String: String] {
        guard let sampledAt, sampledAt.timeIntervalSince1970 > 0 else { return [:] }
        return ["locationTimestamp": String(Int64((sampledAt.timeIntervalSince1970 * 1000).rounded()))]
    }
}

// MARK: - Capability declaration

/// What this iOS build really renders. Missing (nil) means undeclared, which the server treats as
/// "unconfirmed" and never blocks; an explicit declaration that lacks a required capability IS
/// refused at start. So the list below names only renderers that exist in this app.
public struct PlayClientCapabilityDeclaration: Equatable {
    public let platform: String
    public let clientVersion: String
    public let capabilities: [String: Int]
    public init(platform: String = "ios", clientVersion: String, capabilities: [String: Int]) {
        self.platform = platform; self.clientVersion = clientVersion
        self.capabilities = capabilities.filter { !$0.key.isEmpty && $0.value > 0 && !$0.key.contains(",") && !$0.key.contains("@") }
    }
    /// `key@version,key@version`, sorted for a stable request fingerprint.
    public var wireValue: String { capabilities.keys.sorted().map { $0 + "@" + String(capabilities[$0]!) }.joined(separator: ",") }
    /// Form/query fields for orient prepare/start.
    public var fields: [String: String] { ["clientPlatform": platform, "clientVersion": clientVersion, "supportedCapabilities": wireValue] }
    /// JSON fields for advanced start.
    public var json: [String: PlayWireValue] {
        ["clientPlatform": .string(platform), "clientVersion": .string(clientVersion), "supportedCapabilities": .string(wireValue)]
    }

    /// Keys from ContentCapabilityRequirements that this app has native renderers for.
    /// Gameplay sections follow PlayKitActionCatalog plus the Questo renderers in this lane.
    /// Deliberately absent: answer.hiddenObject, game.accusation until its view is mounted in the
    /// advanced flow, media.photo upload, sensors without device acceptance.
    public static let renderedByThisBuild: [String: Int] = [
        "chapter.blocks": 1, "chapter.blocks.text": 1, "chapter.blocks.image": 1, "chapter.blocks.audio": 1,
        "station.list": 1, "answer.arrive": 1, "answer.text": 1, "answer.choice": 1, "answer.scan": 1,
        "answer.gps": 1, "location.gps": 1, "media.image": 1, "media.audio": 1,
        "game.qa": 1, "game.sort": 1, "game.match": 1, "game.classify": 1, "game.branch": 1, "game.hangman": 1
    ]
}

/// `/api/play/nodes` `compatibility`. `supported == nil` (UNDECLARED / MALFORMED) is "未确认兼容":
/// it neither blocks nor claims support. Only an explicit `supported == false` names what is missing.
public struct PlayContentCompatibility: Equatable {
    public enum Verdict: Equatable { case supported, unsupported, unconfirmed }
    public struct Missing: Equatable, Identifiable { public let key: String; public let minVersion: Int; public let declaredVersion: Int?; public var id: String { key } }
    public let verdict: Verdict
    public let source: String
    public let missing: [Missing]
    public init?(data: PlayWireValue) {
        let raw = data["compatibility"]
        guard raw.object != nil, let source = raw["source"].text else { return nil }
        self.source = source
        missing = (raw["missingCapabilities"].array ?? []).compactMap {
            guard let key = $0["key"].text, let min = $0["minVersion"].integer else { return nil }
            return Missing(key: key, minVersion: min, declaredVersion: $0["declaredVersion"].integer)
        }
        switch raw["supported"].bool {
        case .some(true) where source == "DECLARED": verdict = .supported
        case .some(false): verdict = .unsupported
        default: verdict = .unconfirmed // UNDECLARED, MALFORMED, DECLARED_MALFORMED: never "supported"
        }
    }
    /// Payment and start explain the gap before money or a run is committed.
    public var blocksStart: Bool { verdict == .unsupported }
}
