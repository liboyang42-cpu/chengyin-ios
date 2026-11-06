import Foundation

/// Port of the mini-program merchant station projection (pages/merchant/utils/game-session-merchant.js
/// normalizeMerchantProjection / summarizeMerchantProjection). Rejection reasons keep the source codes.
public enum MerchantGameNodeRejection: String, Error, Equatable {
    case empty = "EMPTY", forbiddenProjection = "FORBIDDEN_PROJECTION", invalidMerchantView = "INVALID_MERCHANT_VIEW"
    case invalidSession = "INVALID_SESSION", invalidFallbackOptions = "INVALID_FALLBACK_OPTIONS", invalidStation = "INVALID_STATION"
}

enum MerchantGameNodeWire {
    static let maxSafe = 9_007_199_254_740_991
    static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    static func isBlank(_ value: MerchantContentValue) -> Bool { value == .null || value == .string("") }
    /// JS Number(value) restricted to integral JSON numbers and plain decimal strings.
    static func number(_ value: MerchantContentValue) -> Int? {
        switch value {
        case .integer(let n): return (-maxSafe...maxSafe).contains(n) ? n : nil
        case .decimal(let d):
            var source = d, rounded = Decimal(); NSDecimalRound(&rounded, &source, 0, .plain)
            guard rounded == d else { return nil }
            let n = NSDecimalNumber(decimal: d)
            guard n.compare(NSDecimalNumber(value: maxSafe)) != .orderedDescending,
                  n.compare(NSDecimalNumber(value: -maxSafe)) != .orderedAscending else { return nil }
            return n.intValue
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }
            guard matches(t, "^[+-]?[0-9]+$"), let n = Int(t), (-maxSafe...maxSafe).contains(n) else { return nil }
            return n
        default: return nil
        }
    }
    static func positiveID(_ value: MerchantContentValue) -> Int { number(value).map { $0 > 0 ? $0 : 0 } ?? 0 }
    static func nullablePositiveID(_ value: MerchantContentValue) -> Int? {
        if isBlank(value) { return nil }; let id = positiveID(value); return id > 0 ? id : nil
    }
    static func nonNegative(_ value: MerchantContentValue) -> Int? {
        if isBlank(value) { return nil }; return number(value).flatMap { $0 >= 0 ? $0 : nil }
    }
    /// JS safeText: strings only, trimmed, sliced by UTF-16 length.
    static func text(_ value: MerchantContentValue, _ max: Int = 500) -> String {
        guard case .string(let s) = value else { return "" }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.utf16.count > max else { return t }
        return String(decoding: Array(t.utf16.prefix(max)), as: UTF16.self)
    }
    /// game-session-client validActivityId: /^\d+$/ on the wire value and > 0.
    static func validID(_ value: MerchantContentValue) -> Bool {
        guard let d = value.display, matches(d, "^[0-9]+$"), let n = Int(d) else { return false }
        return n > 0 && n <= maxSafe
    }
    /// game-session-client validRevision: a JSON number that is a safe integer >= 0.
    static func revision(_ value: MerchantContentValue) -> Int? {
        if case .integer(let n) = value, n >= 0, n <= maxSafe { return n }; return nil
    }
    static func sameID(_ left: MerchantContentValue, _ right: Int) -> Bool { left.display == String(right) }
    static let unsafeMessage = #"(?:/api/|exception|\.java\b|\bselect\b)"#
    /// safeMessage: at most 80 characters and no internal detail; nil means use the page fallback.
    static func safeMessage(_ message: String?) -> String? {
        let t = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.utf16.count <= 80,
              t.range(of: unsafeMessage, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return t
    }
    static func safeReason(_ message: String?) -> String? {
        let t = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.utf16.count <= 300,
              t.range(of: unsafeMessage, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return t
    }
    /// validDateTime: 'YYYY-MM-DD HH:mm' or 'YYYY-MM-DD HH:mm:ss' with a real calendar date.
    static func validDateTime(_ value: String) -> Bool {
        guard matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2} (?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?$") else { return false }
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(secondsFromGMT: 0) else { return false }
        calendar.timeZone = zone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2]
    }
    static func timeKey(_ value: String) -> String { String(value.prefix(16)) }
}

public struct MerchantGameNodeChecklistItem: Equatable, Hashable {
    public let code: String, label: String
    public var checked: Bool
    public init(code: String, label: String, checked: Bool) { self.code = code; self.label = label; self.checked = checked }
}
public struct MerchantGameNodeTask: Equatable {
    public let taskCode: String, prompt: String, inputType: String, verificationRequired: Bool
}
public struct MerchantGameNodeRecap: Equatable {
    public static let fields = ["arrivedPlayers", "submissionCount", "approvedCount", "rejectedCount", "recordedCount",
                                "normalCompletedCount", "fallbackCompletedCount", "pauseEventCount", "authorizedContentCount"]
    public let arrivedPlayers: Int, submissionCount: Int, approvedCount: Int, rejectedCount: Int, recordedCount: Int
    public let normalCompletedCount: Int, fallbackCompletedCount: Int, pauseEventCount: Int, authorizedContentCount: Int
    public let contentPolicy = "NO_PUBLIC_CONTENT"
    init?(_ raw: MerchantContentValue) {
        guard raw.object != nil, raw["contentPolicy"].text == "NO_PUBLIC_CONTENT" else { return nil }
        var counts: [Int] = []
        for field in Self.fields { guard let n = MerchantGameNodeWire.nonNegative(raw[field]) else { return nil }; counts.append(n) }
        guard counts[8] == 0 else { return nil }
        arrivedPlayers = counts[0]; submissionCount = counts[1]; approvedCount = counts[2]; rejectedCount = counts[3]
        recordedCount = counts[4]; normalCompletedCount = counts[5]; fallbackCompletedCount = counts[6]
        pauseEventCount = counts[7]; authorizedContentCount = counts[8]
    }
}
public struct MerchantGameNodeFallbackOption: Equatable, Hashable {
    public let sourceNodeID: Int, planCode: String, planVersion: Int, nodeID: Int, nodeName: String, playerMessage: String
}
public enum MerchantGameNodePlayMode: String, Equatable { case route = "ROUTE", story = "STORY" }

public struct MerchantGameNodeStation: Equatable, Identifiable {
    public var id: Int { nodeID }
    public let stationID: Int, nodeID: Int, nodeName: String, stationCode: String, status: String, revision: Int
    public let preparationChecklist: [MerchantGameNodeChecklistItem]
    public let playerTask: MerchantGameNodeTask?
    public let merchantInstruction: String, hiddenInfoReminder: String
    public let capacity: Int?
    public let serviceStartAt: String, serviceEndAt: String
    public let pauseReasonCode: String, pauseReason: String, resumeEta: String
    public let fallbackNodeID: Int?, fallbackPlanCode: String, fallbackPlanVersion: Int?
    public let pendingVerificationCount: Int
    public let recap: MerchantGameNodeRecap?
    public let playable: Bool
    public let canAccept: Bool, canDecline: Bool, canReady: Bool, canPause: Bool, canResume: Bool, canVerify: Bool
    public var statusTextKey: String {
        switch status {
        case "INVITED": return "merchantGameNode.status.INVITED"
        case "ACCEPTED": return "merchantGameNode.status.ACCEPTED"
        case "READY": return "merchantGameNode.status.READY"
        case "ACTIVE": return "merchantGameNode.status.ACTIVE"
        case "PAUSED": return "merchantGameNode.status.PAUSED"
        case "CLOSED": return "merchantGameNode.status.CLOSED"
        default: return "merchantGameNode.status.unknown"
        }
    }
}

public struct MerchantGameNodeProjection: Equatable {
    static let sessionStates: Set<String> = ["PREPARING", "READY", "RUNNING", "FINISHED", "CANCELLED"]
    static let stationStates: Set<String> = ["INVITED", "ACCEPTED", "READY", "ACTIVE", "PAUSED", "CLOSED"]
    public let sessionID: Int, activityID: Int, status: String, revision: Int
    /// Present only when the server sent a non-null authorityEpoch; echoed on every command.
    public let authorityEpoch: MerchantContentValue?
    public let playMode: MerchantGameNodePlayMode
    public let currentChapterID: Int?
    public let availableActions: [String]
    public let stations: [MerchantGameNodeStation]
    public let fallbackOptions: [MerchantGameNodeFallbackOption]

    public init(_ raw: MerchantContentValue) throws {
        typealias W = MerchantGameNodeWire
        guard raw.object != nil else { throw MerchantGameNodeRejection.empty }
        guard (raw["perspective"].display ?? "").uppercased() == "MERCHANT" else { throw MerchantGameNodeRejection.forbiddenProjection }
        let merchant = raw["merchant"]
        guard merchant.object != nil, let rawStations = merchant["stations"].array else { throw MerchantGameNodeRejection.invalidMerchantView }
        let sessionID = W.positiveID(raw["sessionId"]), activityID = W.positiveID(raw["activityId"])
        let revision = W.nonNegative(raw["revision"])
        let status = W.text(raw["status"], 32).uppercased()
        let actions = raw["availableActions"].array.map { items in
            items.map { W.text($0, 64).uppercased() }.filter { W.matches($0, "^[A-Z][A-Z0-9_]{2,63}$") }
        }
        let fallbacks = Self.fallbackOptions(merchant["fallbackOptions"])
        guard sessionID > 0, activityID > 0, let revision, Self.sessionStates.contains(status), let actions else {
            throw MerchantGameNodeRejection.invalidSession
        }
        guard let fallbacks else { throw MerchantGameNodeRejection.invalidFallbackOptions }
        self.sessionID = sessionID; self.activityID = activityID; self.status = status; self.revision = revision
        authorityEpoch = raw["authorityEpoch"] == .null ? nil : raw["authorityEpoch"]
        playMode = merchant["playMode"].text == "ROUTE" ? .route : .story
        currentChapterID = W.nullablePositiveID(raw["currentChapterId"])
        availableActions = actions; fallbackOptions = fallbacks
        var stations: [MerchantGameNodeStation] = []
        for item in rawStations {
            guard let station = Self.station(item, status: status, playMode: playMode, actions: Set(actions)) else {
                throw MerchantGameNodeRejection.invalidStation
            }
            stations.append(station)
        }
        self.stations = stations
    }

    static func fallbackOptions(_ value: MerchantContentValue) -> [MerchantGameNodeFallbackOption]? {
        typealias W = MerchantGameNodeWire
        if value == .null { return [] }
        guard let items = value.array else { return nil }
        let rows = items.map { item in
            MerchantGameNodeFallbackOption(sourceNodeID: W.positiveID(item["sourceNodeId"]), planCode: W.text(item["planCode"], 64).uppercased(),
                planVersion: W.positiveID(item["planVersion"]), nodeID: W.positiveID(item["nodeId"]),
                nodeName: W.text(item["nodeName"], 120), playerMessage: W.text(item["playerMessage"], 500))
        }
        guard !rows.contains(where: { $0.sourceNodeID == 0 || !W.matches($0.planCode, "^[A-Z][A-Z0-9_]{1,63}$") || $0.planVersion == 0
            || $0.nodeID == 0 || $0.nodeID == $0.sourceNodeID || $0.nodeName.isEmpty || $0.playerMessage.isEmpty }) else { return nil }
        guard Set(rows.map { "\($0.sourceNodeID):\($0.planCode):\($0.planVersion)" }).count == rows.count else { return nil }
        return rows
    }

    static func checklist(_ value: MerchantContentValue) -> [MerchantGameNodeChecklistItem]? {
        guard let items = value.array else { return nil }
        let rows = items.map { MerchantGameNodeChecklistItem(code: MerchantGameNodeWire.text($0["code"], 64),
            label: MerchantGameNodeWire.text($0["label"], 120), checked: $0["checked"].flag == true) }
        guard !rows.contains(where: { $0.code.isEmpty || $0.label.isEmpty }), Set(rows.map(\.code)).count == rows.count else { return nil }
        return rows
    }

    static func station(_ raw: MerchantContentValue, status session: String, playMode: MerchantGameNodePlayMode, actions: Set<String>) -> MerchantGameNodeStation? {
        typealias W = MerchantGameNodeWire
        guard raw.object != nil else { return nil }
        let stationID = W.positiveID(raw["stationId"]), nodeID = W.positiveID(raw["nodeId"])
        let status = W.text(raw["status"], 32).uppercased()
        let revision = W.nonNegative(raw["revision"])
        let checklist = Self.checklist(raw["preparationChecklist"])
        let pending = W.nonNegative(raw["pendingVerificationCount"])
        var playerTask: MerchantGameNodeTask?
        let taskValue = raw["playerTask"]
        if taskValue != .null {
            guard taskValue.object != nil else { return nil }
            let code = W.text(taskValue["taskCode"], 64), prompt = W.text(taskValue["prompt"], 500)
            let input = W.text(taskValue["inputType"], 16).uppercased()
            guard !code.isEmpty, !prompt.isEmpty, ["TEXT", "SCAN", "PHOTO"].contains(input) else { return nil }
            playerTask = .init(taskCode: code, prompt: prompt, inputType: input, verificationRequired: taskValue["verificationRequired"].flag == true)
        }
        guard stationID > 0, nodeID > 0, Self.stationStates.contains(status), let revision, let checklist, let pending else { return nil }
        let capacity: Int?
        if W.isBlank(raw["capacity"]) { capacity = nil } else {
            guard let n = W.nonNegative(raw["capacity"]) else { return nil }; capacity = n
        }
        let window = raw["serviceWindow"].object != nil ? raw["serviceWindow"] : .object([:])
        let startText = W.text(raw["serviceStartAt"], 32), endText = W.text(raw["serviceEndAt"], 32)
        let start = startText.isEmpty ? W.text(window["start"], 32) : startText
        let end = endText.isEmpty ? W.text(window["end"], 32) : endText
        let configured = (capacity ?? 0) > 0 && (playMode == .route || !checklist.isEmpty) && checklist.allSatisfy(\.checked)
            && W.validDateTime(start) && W.validDateTime(end) && W.timeKey(start) < W.timeKey(end)
        let playable = raw["playable"].flag == true && configured && (status == "READY" || status == "ACTIVE")
            && ["READY", "RUNNING"].contains(session)
        let open = session != "FINISHED" && session != "CANCELLED"
        return MerchantGameNodeStation(stationID: stationID, nodeID: nodeID, nodeName: W.text(raw["nodeName"], 120),
            stationCode: W.text(raw["stationCode"], 64), status: status, revision: revision, preparationChecklist: checklist,
            playerTask: playerTask, merchantInstruction: W.text(raw["merchantInstruction"], 500),
            hiddenInfoReminder: W.text(raw["hiddenInfoReminder"], 500), capacity: capacity, serviceStartAt: start, serviceEndAt: end,
            pauseReasonCode: W.text(raw["pauseReasonCode"], 64), pauseReason: W.text(raw["pauseReason"], 200),
            resumeEta: W.text(raw["resumeEta"], 64), fallbackNodeID: W.nullablePositiveID(raw["fallbackNodeId"]),
            fallbackPlanCode: W.text(raw["fallbackPlanCode"], 64).uppercased(),
            fallbackPlanVersion: W.nullablePositiveID(raw["fallbackPlanVersion"]), pendingVerificationCount: pending,
            recap: MerchantGameNodeRecap(raw["recap"]), playable: playable,
            canAccept: status == "INVITED" && actions.contains("STATION_ACCEPT") && open,
            canDecline: status == "INVITED" && actions.contains("STATION_DECLINE") && open,
            canReady: status == "ACCEPTED" && actions.contains("STATION_READY") && open,
            canPause: (status == "READY" || status == "ACTIVE") && actions.contains("STATION_PAUSE") && open,
            canResume: status == "PAUSED" && actions.contains("STATION_RESUME") && open,
            canVerify: status == "ACTIVE" && playable && pending > 0 && actions.contains("VERIFY_SUBMISSION"))
    }

    public func fallbackOptions(for station: MerchantGameNodeStation) -> [MerchantGameNodeFallbackOption] {
        fallbackOptions.filter { $0.sourceNodeID == station.nodeID }
    }
    public func contains(_ station: MerchantGameNodeStation) -> Bool {
        stations.contains { $0.stationID == station.stationID && $0.nodeID == station.nodeID }
    }
    /// Requested node first, otherwise the previous index clamped to the station count.
    public func stationIndex(requestedNodeID: Int?, previous: Int) -> Int? {
        guard !stations.isEmpty else { return nil }
        if let requestedNodeID, let index = stations.firstIndex(where: { $0.nodeID == requestedNodeID }) { return index }
        return Swift.max(0, Swift.min(previous, stations.count - 1))
    }
}

public struct MerchantGameNodeSummary: Equatable {
    public enum State: String, Equatable { case error, empty, playable, closed, invited, paused, setup }
    public enum Tone: String, Equatable { case error, muted, ready, pending, paused }
    public let state: State, tone: Tone, pendingVerificationCount: Int, stationCount: Int
    public init(_ projection: MerchantGameNodeProjection?) {
        guard let projection else { state = .error; tone = .error; pendingVerificationCount = 0; stationCount = 0; return }
        let stations = projection.stations
        let pending = stations.reduce(0) { $0 + $1.pendingVerificationCount }
        stationCount = stations.count
        if stations.isEmpty { state = .empty; tone = .muted; pendingVerificationCount = 0; return }
        pendingVerificationCount = pending
        if stations.contains(where: \.playable) { state = .playable; tone = .ready }
        else if stations.allSatisfy({ $0.status == "CLOSED" }) { state = .closed; tone = .muted }
        else if stations.contains(where: { $0.status == "INVITED" }) { state = .invited; tone = .pending }
        else if stations.contains(where: { $0.status == "PAUSED" }) { state = .paused; tone = .paused }
        else { state = .setup; tone = .pending }
    }
    /// Format key takes the pending count only for `merchantGameNode.summary.playablePending`.
    public var textKey: String {
        switch state {
        case .error: return "merchantGameNode.summary.unavailable"
        case .empty: return "merchantGameNode.summary.empty"
        case .playable: return pendingVerificationCount > 0 ? "merchantGameNode.summary.playablePending" : "merchantGameNode.summary.playable"
        case .closed: return "merchantGameNode.summary.closed"
        case .invited: return "merchantGameNode.summary.invited"
        case .paused: return "merchantGameNode.summary.paused"
        case .setup: return "merchantGameNode.summary.setup"
        }
    }
}
