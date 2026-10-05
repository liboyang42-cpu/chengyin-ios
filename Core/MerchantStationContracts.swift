import Foundation

public enum MerchantStationAction: String, Codable, CaseIterable, Identifiable {
    case accept = "STATION_ACCEPT", decline = "STATION_DECLINE", ready = "STATION_READY"
    case pause = "STATION_PAUSE", resume = "STATION_RESUME", verify = "VERIFY_SUBMISSION"
    public var id: String { rawValue }
}
public struct MerchantStationProjection: Equatable {
    public let sessionID: Int, activityID: Int, revision: Int
    public let status: String
    public let availableActions: Set<String>
    public let stations: [MerchantContentValue]
    public let fallbackOptions: [MerchantContentValue]
    public init(_ raw: MerchantContentValue) throws {
        guard raw["perspective"].text?.uppercased() == "MERCHANT", let session = raw["sessionId"].safeInteger, session > 0,
              let activity = raw["activityId"].safeInteger, activity > 0, let revision = raw["revision"].safeInteger, revision >= 0,
              let status = raw["status"].text, ["PREPARING", "READY", "RUNNING", "FINISHED", "CANCELLED"].contains(status),
              let stations = raw["merchant"]["stations"].array else { throw MerchantContentFailure.malformed }
        self.sessionID = session; self.activityID = activity; self.revision = revision; self.status = status
        availableActions = Set((raw["availableActions"].array ?? []).compactMap { $0.text?.uppercased() })
        self.stations = stations; fallbackOptions = raw["merchant"]["fallbackOptions"].array ?? []
        var stationIDs = Set<Int>(), nodeIDs = Set<Int>()
        for station in stations {
            guard let id = station["stationId"].safeInteger, id > 0, stationIDs.insert(id).inserted,
                  let node = station["nodeId"].safeInteger, node > 0, nodeIDs.insert(node).inserted,
                  let rev = station["revision"].safeInteger, rev >= 0,
                  let state = station["status"].text, ["INVITED", "ACCEPTED", "READY", "ACTIVE", "PAUSED", "CLOSED"].contains(state),
                  let checklist = station["preparationChecklist"].array,
                  let pending = station["pendingVerificationCount"].safeInteger, pending >= 0 else { throw MerchantContentFailure.malformed }
            var codes = Set<String>()
            for item in checklist {
                guard let code = item["code"].text, !code.isEmpty, codes.insert(code).inserted,
                      let label = item["label"].text, !label.isEmpty, item["checked"].flag != nil else { throw MerchantContentFailure.malformed }
            }
            if let recap = station["recap"].object, recap["contentPolicy"]?.text == "NO_PUBLIC_CONTENT" {
                for key in ["arrivedPlayers", "submissionCount", "approvedCount", "rejectedCount", "recordedCount", "normalCompletedCount", "fallbackCompletedCount", "pauseEventCount", "authorizedContentCount"] {
                    guard let n = recap[key]?.safeInteger, n >= 0 else { throw MerchantContentFailure.malformed }
                }
                guard recap["authorizedContentCount"]?.safeInteger == 0 else { throw MerchantContentFailure.malformed }
            }
        }
        for fallback in fallbackOptions {
            guard let source = fallback["sourceNodeId"].safeInteger, source > 0,
                  let target = fallback["nodeId"].safeInteger, target > 0, source != target,
                  let version = fallback["planVersion"].safeInteger, version > 0,
                  !(fallback["planCode"].text ?? "").isEmpty, !(fallback["nodeName"].text ?? "").isEmpty,
                  !(fallback["playerMessage"].text ?? "").isEmpty else { throw MerchantContentFailure.malformed }
        }
    }
    public func station(nodeID: Int) -> MerchantContentValue? { stations.first { $0["nodeId"].safeInteger == nodeID } }
    public func allows(_ action: MerchantStationAction, nodeID: Int) -> Bool {
        guard availableActions.contains(action.rawValue), let station = station(nodeID: nodeID) else { return false }
        let state = station["status"].text
        switch action {
        case .accept, .decline: return ["PREPARING", "READY"].contains(status) && state == "INVITED"
        case .ready: return ["PREPARING", "READY"].contains(status) && state == "ACCEPTED"
        case .pause, .verify: return status == "RUNNING" && state == "ACTIVE"
        case .resume: return status == "RUNNING" && state == "PAUSED"
        }
    }
    public func allowsLiveCode(nodeID: Int) -> Bool {
        guard let s = station(nodeID: nodeID), s["playable"].flag == true,
              ["READY", "RUNNING"].contains(status), ["READY", "ACTIVE"].contains(s["status"].text ?? ""),
              (s["capacity"].safeInteger ?? 0) > 0, let checklist = s["preparationChecklist"].array, !checklist.isEmpty,
              checklist.allSatisfy({ $0["checked"].flag == true }), let start = s["serviceStartAt"].text, let end = s["serviceEndAt"].text else { return false }
        return MerchantStationCommand.validTime(start) && MerchantStationCommand.validTime(end) && start < end
    }
}
public struct MerchantStationCommand: Codable, Equatable {
    public let activityID: Int, nodeID: Int, expectedRevision: Int
    public let requestID: String
    public let action: MerchantStationAction
    public let payload: [String: MerchantContentValue]
    public init(activityID: Int, nodeID: Int, expectedRevision: Int, requestID: String = UUID().uuidString, action: MerchantStationAction, payload: [String: MerchantContentValue] = [:]) {
        self.activityID = activityID; self.nodeID = nodeID; self.expectedRevision = expectedRevision
        self.requestID = requestID; self.action = action; self.payload = payload
    }
    public func fields() throws -> [String: MerchantContentValue] {
        guard activityID > 0, nodeID > 0, expectedRevision >= 0,
              activityID <= 9_007_199_254_740_991, nodeID <= 9_007_199_254_740_991, expectedRevision <= 9_007_199_254_740_991,
              requestID.range(of: #"^[A-Za-z0-9_-]{8,64}$"#, options: .regularExpression) != nil else { throw MerchantContentFailure.invalid }
        let keys = Set(payload.keys)
        func required(_ required: Set<String>, optional: Set<String> = []) throws {
            guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw MerchantContentFailure.invalid }
        }
        switch action {
        case .accept, .resume: try required([])
        case .decline:
            try required(["reasonCode", "reason"])
            guard ["SCHEDULE_CONFLICT", "RESOURCE_UNAVAILABLE", "LOCATION_UNSUITABLE"].contains(payload["reasonCode"]?.text ?? ""),
                  !(payload["reason"]?.text ?? "").isEmpty else { throw MerchantContentFailure.invalid }
        case .ready:
            try required(["checklist", "capacity", "serviceStartAt", "serviceEndAt", "note"])
            guard (payload["capacity"]?.safeInteger ?? 0) > 0, let start = payload["serviceStartAt"]?.text,
                  let end = payload["serviceEndAt"]?.text, Self.validTime(start), Self.validTime(end), start < end,
                  payload["note"]?.text != nil, let items = payload["checklist"]?.array, !items.isEmpty,
                  items.allSatisfy({ Set($0.object?.keys.map { $0 } ?? []) == Set(["code", "checked"]) && $0["checked"].flag == true && !($0["code"].text ?? "").isEmpty }) else { throw MerchantContentFailure.invalid }
        case .pause:
            try required(["reasonCode", "reason", "resumeEta", "fallbackPlanCode", "fallbackPlanVersion"])
            guard ["CAPACITY", "STAFF", "EQUIPMENT", "EMERGENCY"].contains(payload["reasonCode"]?.text ?? ""),
                  !(payload["reason"]?.text ?? "").isEmpty, Self.validTime(payload["resumeEta"]?.text ?? ""),
                  !(payload["fallbackPlanCode"]?.text ?? "").isEmpty, (payload["fallbackPlanVersion"]?.safeInteger ?? 0) > 0 else { throw MerchantContentFailure.invalid }
        case .verify:
            try required(["submissionId", "decision"], optional: ["reasonCode"])
            guard (payload["submissionId"]?.text ?? "").range(of: #"^[1-9]\d{0,18}$"#, options: .regularExpression) != nil else { throw MerchantContentFailure.invalid }
            if payload["decision"]?.text == "APPROVE" { guard payload["reasonCode"] == nil else { throw MerchantContentFailure.invalid } }
            else { guard payload["decision"]?.text == "REJECT", ["ANSWER_MISMATCH", "EVIDENCE_UNCLEAR", "DUPLICATE_SUBMISSION"].contains(payload["reasonCode"]?.text ?? "") else { throw MerchantContentFailure.invalid } }
        }
        return ["activityId": .integer(activityID), "nodeId": .integer(nodeID), "requestId": .string(requestID),
                "expectedRevision": .integer(expectedRevision), "action": .string(action.rawValue), "payload": .object(payload)]
    }
    public func validate(projection: MerchantStationProjection) throws {
        _ = try fields()
        guard projection.activityID == activityID, projection.revision == expectedRevision, projection.allows(action, nodeID: nodeID),
              let s = projection.station(nodeID: nodeID) else { throw MerchantContentFailure.conflict }
        if action == .ready {
            let expected = (s["preparationChecklist"].array ?? []).compactMap { $0["code"].text }
            let submitted = (payload["checklist"]?.array ?? []).compactMap { $0["code"].text }
            guard !expected.isEmpty, expected == submitted else { throw MerchantContentFailure.invalid }
        }
        if action == .pause {
            guard projection.fallbackOptions.contains(where: { $0["sourceNodeId"].safeInteger == nodeID && $0["planCode"].text == payload["fallbackPlanCode"]?.text && $0["planVersion"].safeInteger == payload["fallbackPlanVersion"]?.safeInteger }) else { throw MerchantContentFailure.invalid }
        }
    }
    /// Validates civil strings without inventing a service timezone or converting them to local instants.
    public static func validTime(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2} (?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return false }
        let parts = value.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).compactMap { Int($0) }
        guard parts.count == 5, parts[0] > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])
        guard let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2] && actual.hour == parts[3] && actual.minute == parts[4]
    }
}
public struct MerchantStationReceipt: Equatable {
    public let outcome: String, receiptID: Int, revision: Int
    public let reason: String?
    public init(_ raw: MerchantContentValue, command: MerchantStationCommand) throws {
        guard raw["activityId"].safeInteger == command.activityID, raw["requestId"].text == command.requestID,
              raw["action"].text == command.action.rawValue, let revision = raw["revision"].safeInteger, revision >= 0,
              let receipt = raw["receiptId"].safeInteger, receipt > 0,
              let outcome = raw["outcome"].text, ["APPLIED", "FAILED"].contains(outcome) else { throw MerchantContentFailure.unknown }
        self.outcome = outcome; receiptID = receipt; self.revision = revision
        let reason = raw["result"]["reason"].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.reason = !reason.isEmpty && reason.utf16.count <= 300 && reason.range(of: #"(?:/api/|exception|\.java\b|\bselect\b)"#, options: [.regularExpression, .caseInsensitive]) == nil ? reason : nil
    }
}
