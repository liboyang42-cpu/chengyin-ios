import Foundation

/// Command builders ported from game-session-merchant.js. A request ID is generated once when a command
/// is prepared and travels with it through confirmation, dispatch, readback and an explicit retry.
public enum MerchantGameNodeCommandError: Error, Equatable { case notAllowed, inputInvalid }

public enum MerchantGameNodeRequestID {
    public static let pattern = "^[A-Za-z0-9_-]{8,64}$"
    public static func isValid(_ value: String) -> Bool { MerchantGameNodeWire.matches(value, pattern) }
    public static func shortName(_ action: MerchantStationAction) -> String {
        switch action {
        case .accept: return "accept"; case .decline: return "decline"; case .ready: return "ready"
        case .pause: return "pause"; case .resume: return "resume"; case .verify: return "verify"
        }
    }
    /// ['game', action, activityId, nodeId, Date.now(), rand6].join('_').slice(0, 64)
    public static func make(action: MerchantStationAction, activityID: Int, nodeID: Int, milliseconds: Int64, random: String) -> String {
        String(["game", shortName(action), String(activityID), String(nodeID), String(milliseconds), random].joined(separator: "_").prefix(64))
    }
    public static func random6() -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }
    public static func generate(action: MerchantStationAction, activityID: Int, nodeID: Int, now: Date = Date()) -> String {
        make(action: action, activityID: activityID, nodeID: nodeID, milliseconds: Int64((now.timeIntervalSince1970 * 1000).rounded(.down)), random: random6())
    }
}

/// Fixed reason codes. `serverLabel` is the source's Chinese label sent as the free-text reason.
public struct MerchantGameNodeReason: Equatable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String, serverLabel: String, labelKey: String
    public static let pause = [
        Self(code: "CAPACITY", serverLabel: "现场满员", labelKey: "merchantGameNode.pauseReason.CAPACITY"),
        Self(code: "STAFF", serverLabel: "人员暂时离岗", labelKey: "merchantGameNode.pauseReason.STAFF"),
        Self(code: "EQUIPMENT", serverLabel: "设备或道具异常", labelKey: "merchantGameNode.pauseReason.EQUIPMENT"),
        Self(code: "EMERGENCY", serverLabel: "现场突发情况", labelKey: "merchantGameNode.pauseReason.EMERGENCY"),
    ]
    public static let decline = [
        Self(code: "SCHEDULE_CONFLICT", serverLabel: "档期冲突", labelKey: "merchantGameNode.declineReason.SCHEDULE_CONFLICT"),
        Self(code: "RESOURCE_UNAVAILABLE", serverLabel: "现场资源不足", labelKey: "merchantGameNode.declineReason.RESOURCE_UNAVAILABLE"),
        Self(code: "LOCATION_UNSUITABLE", serverLabel: "本站暂不适合承接", labelKey: "merchantGameNode.declineReason.LOCATION_UNSUITABLE"),
    ]
    public static let reject = [
        Self(code: "ANSWER_MISMATCH", serverLabel: "答案不匹配", labelKey: "merchantGameNode.rejectReason.ANSWER_MISMATCH"),
        Self(code: "EVIDENCE_UNCLEAR", serverLabel: "凭证无法辨认", labelKey: "merchantGameNode.rejectReason.EVIDENCE_UNCLEAR"),
        Self(code: "DUPLICATE_SUBMISSION", serverLabel: "重复提交", labelKey: "merchantGameNode.rejectReason.DUPLICATE_SUBMISSION"),
    ]
}

public struct MerchantGameNodeReadyDraft: Equatable {
    public var checklist: [MerchantGameNodeChecklistItem]
    public var capacity: String, serviceDate: String, serviceStartTime: String, serviceEndTime: String, note: String
    public init(checklist: [MerchantGameNodeChecklistItem] = [], capacity: String = "", serviceDate: String = "",
                serviceStartTime: String = "", serviceEndTime: String = "", note: String = "") {
        self.checklist = checklist; self.capacity = capacity; self.serviceDate = serviceDate
        self.serviceStartTime = serviceStartTime; self.serviceEndTime = serviceEndTime; self.note = note
    }
    /// splitServiceDateTime: only 'YYYY-MM-DD HH:mm' seeds the pickers (seconds-bearing server values do not).
    public init(station: MerchantGameNodeStation) {
        func split(_ value: String) -> (String, String)? {
            guard MerchantGameNodeWire.matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$") else { return nil }
            return (String(value.prefix(10)), String(value.suffix(5)))
        }
        let start = split(station.serviceStartAt), end = split(station.serviceEndAt)
        self.init(checklist: station.preparationChecklist, capacity: station.capacity.map(String.init) ?? "",
                  serviceDate: start?.0 ?? end?.0 ?? "", serviceStartTime: start?.1 ?? "", serviceEndTime: end?.1 ?? "")
    }
    public var serviceStartAt: String { [serviceDate, serviceStartTime].filter { !$0.isEmpty }.joined(separator: " ") }
    public var serviceEndAt: String { [serviceDate, serviceEndTime].filter { !$0.isEmpty }.joined(separator: " ") }
}
public struct MerchantGameNodeDeclineDraft: Equatable {
    public var reason: MerchantGameNodeReason?
    public init(reason: MerchantGameNodeReason? = nil) { self.reason = reason }
}
public struct MerchantGameNodePauseDraft: Equatable {
    public var reason: MerchantGameNodeReason?
    public var resumeDate = "", resumeTime = ""
    public var fallback: MerchantGameNodeFallbackOption?
    public init() {}
    public var resumeEta: String { [resumeDate, resumeTime].filter { !$0.isEmpty }.joined(separator: " ") }
    /// Matches the source button gate: a reason and a resume date are required.
    public var canSubmit: Bool { reason != nil && !resumeDate.isEmpty }
}
public struct MerchantGameNodeVerifyDraft: Equatable {
    public var submissionID: String
    public var approve = true
    public var rejectReason: MerchantGameNodeReason?
    public init(submissionID: String = "") { self.submissionID = submissionID }
}

public struct MerchantGameNodeCommand: Codable, Equatable {
    public let activityID: Int, nodeID: Int, requestID: String, expectedRevision: Int
    public let authorityEpoch: Int?
    public let action: MerchantStationAction
    public let payload: [String: MerchantContentValue]
    /// write-action-workflow business key: action:nodeId[:submissionId]
    public var lockKey: String {
        var key = action.rawValue + ":" + String(nodeID)
        if let submission = payload["submissionId"]?.text, !submission.isEmpty { key += ":" + submission }
        return key
    }
    public var pausesWithoutFallback: Bool { action == .pause && payload["fallbackPlanCode"] == nil }
    public var pendingIndex: MerchantGameNodePendingIndex {
        .init(activityID: activityID, requestID: requestID, action: action, nodeID: nodeID, expectedRevision: expectedRevision)
    }
    /// submitAction body: { activityId, nodeId, requestId, expectedRevision, action, payload, authorityEpoch? }
    public func body() throws -> [String: MerchantContentValue] {
        guard activityID > 0, nodeID > 0, expectedRevision >= 0, MerchantGameNodeRequestID.isValid(requestID),
              authorityEpoch.map({ (1...2_147_483_647).contains($0) }) ?? true else { throw MerchantGameNodeCommandError.inputInvalid }
        var fields: [String: MerchantContentValue] = ["activityId": .integer(activityID), "nodeId": .integer(nodeID),
            "requestId": .string(requestID), "expectedRevision": .integer(expectedRevision),
            "action": .string(action.rawValue), "payload": .object(payload)]
        if let authorityEpoch { fields["authorityEpoch"] = .integer(authorityEpoch) }
        return fields
    }

    private static func base(_ projection: MerchantGameNodeProjection, _ station: MerchantGameNodeStation, _ requestID: String,
                             _ action: MerchantStationAction, allowed: Bool, payload: [String: MerchantContentValue]) throws -> Self {
        guard projection.contains(station), allowed else { throw MerchantGameNodeCommandError.notAllowed }
        guard MerchantGameNodeRequestID.isValid(requestID) else { throw MerchantGameNodeCommandError.inputInvalid }
        var epoch: Int?
        if let raw = projection.authorityEpoch {
            guard case .integer(let n) = raw, (1...2_147_483_647).contains(n) else { throw MerchantGameNodeCommandError.inputInvalid }
            epoch = n
        }
        return .init(activityID: projection.activityID, nodeID: station.nodeID, requestID: requestID,
                     expectedRevision: projection.revision, authorityEpoch: epoch, action: action, payload: payload)
    }
    private static func code(_ value: String) -> String { MerchantGameNodeWire.text(.string(value), 64).uppercased() }
    private static let codePattern = "^[A-Z][A-Z0-9_]{1,63}$"

    public static func accept(_ p: MerchantGameNodeProjection, _ s: MerchantGameNodeStation, requestID: String) throws -> Self {
        try base(p, s, requestID, .accept, allowed: s.canAccept, payload: [:])
    }
    public static func resume(_ p: MerchantGameNodeProjection, _ s: MerchantGameNodeStation, requestID: String) throws -> Self {
        try base(p, s, requestID, .resume, allowed: s.canResume, payload: [:])
    }
    public static func decline(_ p: MerchantGameNodeProjection, _ s: MerchantGameNodeStation, draft: MerchantGameNodeDeclineDraft, requestID: String) throws -> Self {
        let command = try base(p, s, requestID, .decline, allowed: s.canDecline, payload: [:])
        let reasonCode = code(draft.reason?.code ?? ""), reason = MerchantGameNodeWire.text(.string(draft.reason?.serverLabel ?? ""), 200)
        guard MerchantGameNodeWire.matches(reasonCode, codePattern), !reason.isEmpty else { throw MerchantGameNodeCommandError.inputInvalid }
        return command.with(["reasonCode": .string(reasonCode), "reason": .string(reason)])
    }
    public static func ready(_ p: MerchantGameNodeProjection, _ s: MerchantGameNodeStation, draft: MerchantGameNodeReadyDraft, requestID: String) throws -> Self {
        let command = try base(p, s, requestID, .ready, allowed: s.canReady, payload: [:])
        var checked: [String: Bool] = [:]
        for item in draft.checklist where !item.code.isEmpty { checked[item.code] = item.checked }
        let checklist = s.preparationChecklist.map { (code: $0.code, checked: checked[$0.code] == true) }
        let capacity = MerchantGameNodeWire.positiveID(.string(draft.capacity))
        let start = MerchantGameNodeWire.text(.string(draft.serviceStartAt), 32), end = MerchantGameNodeWire.text(.string(draft.serviceEndAt), 32)
        let note = MerchantGameNodeWire.text(.string(draft.note), 200)
        guard p.playMode == .route || !checklist.isEmpty, checklist.allSatisfy({ $0.checked }), capacity > 0,
              MerchantGameNodeWire.validDateTime(start), MerchantGameNodeWire.validDateTime(end),
              MerchantGameNodeWire.timeKey(start) < MerchantGameNodeWire.timeKey(end) else { throw MerchantGameNodeCommandError.inputInvalid }
        return command.with(["checklist": .array(checklist.map { .object(["code": .string($0.code), "checked": .bool($0.checked)]) }),
                          "capacity": .integer(capacity), "serviceStartAt": .string(start), "serviceEndAt": .string(end), "note": .string(note)])
    }
    /// R9-38: the fallback is optional, but when present it must be this station's approved option.
    public static func pause(_ p: MerchantGameNodeProjection, _ s: MerchantGameNodeStation, draft: MerchantGameNodePauseDraft, requestID: String) throws -> Self {
        let command = try base(p, s, requestID, .pause, allowed: s.canPause, payload: [:])
        let reasonCode = code(draft.reason?.code ?? ""), reason = MerchantGameNodeWire.text(.string(draft.reason?.serverLabel ?? ""), 200)
        let resumeEta = MerchantGameNodeWire.text(.string(draft.resumeEta), 64)
        let planCode = code(draft.fallback?.planCode ?? ""), planVersion = draft.fallback?.planVersion ?? 0
        let withFallback = draft.fallback != nil
        let approved = p.fallbackOptions.contains { $0.sourceNodeID == s.nodeID && $0.planCode == planCode && $0.planVersion == planVersion }
        guard MerchantGameNodeWire.matches(reasonCode, codePattern), !resumeEta.isEmpty,
              !withFallback || (MerchantGameNodeWire.matches(planCode, codePattern) && planVersion > 0 && approved) else {
            throw MerchantGameNodeCommandError.inputInvalid
        }
        var payload: [String: MerchantContentValue] = ["reasonCode": .string(reasonCode), "resumeEta": .string(resumeEta)]
        if withFallback { payload["fallbackPlanCode"] = .string(planCode); payload["fallbackPlanVersion"] = .integer(planVersion) }
        if !reason.isEmpty { payload["reason"] = .string(reason) }
        return command.with(payload)
    }
    public static func verify(_ p: MerchantGameNodeProjection, _ s: MerchantGameNodeStation, draft: MerchantGameNodeVerifyDraft, requestID: String) throws -> Self {
        let command = try base(p, s, requestID, .verify, allowed: s.canVerify, payload: [:])
        let submission = MerchantGameNodeWire.text(.string(draft.submissionID), 64)
        let reasonCode = draft.approve ? "" : code(draft.rejectReason?.code ?? "")
        guard MerchantGameNodeWire.matches(submission, "^[1-9][0-9]{0,18}$"), draft.approve || !reasonCode.isEmpty else {
            throw MerchantGameNodeCommandError.inputInvalid
        }
        var payload: [String: MerchantContentValue] = ["submissionId": .string(submission), "decision": .string(draft.approve ? "APPROVE" : "REJECT")]
        if !reasonCode.isEmpty { payload["reasonCode"] = .string(reasonCode) }
        return command.with(payload)
    }
    private func with(_ payload: [String: MerchantContentValue]) -> Self {
        .init(activityID: activityID, nodeID: nodeID, requestID: requestID, expectedRevision: expectedRevision,
              authorityEpoch: authorityEpoch, action: action, payload: payload)
    }
}

/// The persisted unknown-write index (never the payload): activityId, requestId, action, nodeId, expectedRevision.
public struct MerchantGameNodePendingIndex: Codable, Equatable {
    public let activityID: Int, requestID: String, action: MerchantStationAction, nodeID: Int, expectedRevision: Int
    public var lockKey: String { action.rawValue + ":" + String(nodeID) }
    public var isValid: Bool {
        activityID > 0 && nodeID > 0 && expectedRevision >= 0 && MerchantGameNodeRequestID.isValid(requestID)
    }
}

/// parseSubmissionId: JSON { submissionId }, a ?/&submissionId= query, or a bare positive decimal.
public enum MerchantGameNodeSubmissionCode {
    public static func parse(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if let decoded = try? JSONDecoder().decode(MerchantContentValue.self, from: Data(text.utf8)), decoded.object != nil,
           decoded["submissionId"] != .null, let inner = decoded["submissionId"].display ?? decoded["submissionId"].flag.map({ String($0) }) {
            return parse(inner)
        }
        if let range = text.range(of: "[?&]submissionId=([1-9][0-9]{0,18})(?:&|$)", options: .regularExpression) {
            let fragment = String(text[range])
            if let digits = fragment.range(of: "[1-9][0-9]{0,18}", options: .regularExpression) { return String(fragment[digits]) }
        }
        return MerchantGameNodeWire.matches(text, "^[1-9][0-9]{0,18}$") ? text : ""
    }
}
