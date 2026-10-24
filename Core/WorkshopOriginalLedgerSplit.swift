import Foundation

/// Three original ledgers stay separate. A game-session APPLIED command is not
/// an H5 server pass. Advanced play provenance is not that receipt. A native
/// artifact freeze is not an H5 loader, and the SDK version stays nil.
public enum WorkshopOriginalLedgerError: Error, Equatable {
    case invalid
    case mixed
    case unknown
}

public struct WorkshopGameSessionFact: Equatable, Sendable {
    public let receiptID: Int64?
    public let activityID: Int64
    public let memberID: Int64
    public let requestID: String
    public let action: String?
    public let outcome: String
    public let reasonCode: String?
    public let revision: Int64?
    public let replayed: Bool
    public let confirmed: Bool
    /// APPLIED only means the command was applied. It never grants an H5 pass.
    public var grantsServerPass: Bool { false }
}

public struct WorkshopAdvancedProvenance: Equatable, Sendable {
    public let sourceHash: String
    public let runHash: String
    public let sessionID: Int64
    public let topicID: Int64
    public let nodeID: Int64
    public let memberID: Int64
    public var isCommandReceipt: Bool { false }
    public var grantsServerPass: Bool { false }
}

public struct WorkshopNativeArtifactFreeze: Equatable, Sendable {
    public let moduleID: String
    public let releaseID: String
    public let contentHash: String
    public let memberID: Int64
    public var h5Admitted: Bool { false }
    /// SDK version identity is not this native registry.
    public var sdkVersion: String? { nil }
}

public protocol WorkshopOriginalLedgerReading: Sendable {
    func gameSession(activityID: Int64, memberID: Int64, requestID: String) async throws -> Data?
    func advancedState(sessionID: Int64, memberID: Int64) async throws -> Data?
}

public struct WorkshopOriginalLedgerSplit: Sendable {
    public init() {}

    public func readGameSession(activityID: Int64, memberID: Int64, requestID: String,
                                source: any WorkshopOriginalLedgerReading) async throws -> WorkshopGameSessionFact {
        guard activityID > 0, memberID > 0, !requestID.isEmpty else { throw WorkshopOriginalLedgerError.invalid }
        guard let data = try await source.gameSession(activityID: activityID, memberID: memberID, requestID: requestID) else {
            return WorkshopGameSessionFact(receiptID: nil, activityID: activityID, memberID: memberID,
                                           requestID: requestID, action: nil, outcome: "PENDING",
                                           reasonCode: nil, revision: nil, replayed: false, confirmed: false)
        }
        guard let object = jsonObject(data), !mixes(object, foreign: ["sourceHash", "runHash", "moduleId", "contentHash"]) else {
            throw WorkshopOriginalLedgerError.mixed
        }
        guard exactLong(object["activityId"]) == activityID, object["requestId"] as? String == requestID else {
            throw WorkshopOriginalLedgerError.unknown
        }
        let outcome = object["outcome"] as? String
        guard outcome == "PENDING" || outcome == "APPLIED" || outcome == "FAILED" else {
            throw WorkshopOriginalLedgerError.unknown
        }
        let replayed = jsonBool(object["replayed"])
        guard let replayed else { throw WorkshopOriginalLedgerError.unknown }
        let receiptID: Int64?
        if object["receiptId"] != nil {
            guard let parsed = exactLong(object["receiptId"]) else { throw WorkshopOriginalLedgerError.unknown }
            receiptID = parsed
        } else {
            receiptID = nil
        }
        if outcome == "PENDING" {
            guard receiptID == nil, replayed == false else { throw WorkshopOriginalLedgerError.unknown }
            return WorkshopGameSessionFact(receiptID: nil, activityID: activityID, memberID: memberID,
                                           requestID: requestID, action: nil, outcome: "PENDING",
                                           reasonCode: nil, revision: nil, replayed: false, confirmed: false)
        }
        guard let receiptID, let action = object["action"] as? String, !action.isEmpty else {
            throw WorkshopOriginalLedgerError.unknown
        }
        let reasonCode = object["reasonCode"] as? String
        if outcome == "FAILED" {
            guard let reasonCode, !reasonCode.isEmpty else { throw WorkshopOriginalLedgerError.unknown }
        }
        return WorkshopGameSessionFact(receiptID: receiptID, activityID: activityID, memberID: memberID,
                                       requestID: requestID, action: action, outcome: outcome!,
                                       reasonCode: reasonCode,
                                       revision: exactLong(object["revision"]), replayed: replayed, confirmed: true)
    }

    public func readAdvanced(sessionID: Int64, memberID: Int64,
                             source: any WorkshopOriginalLedgerReading) async throws -> WorkshopAdvancedProvenance {
        guard sessionID > 0, memberID > 0 else { throw WorkshopOriginalLedgerError.invalid }
        guard let data = try await source.advancedState(sessionID: sessionID, memberID: memberID),
              let object = jsonObject(data),
              !mixes(object, foreign: ["outcome", "requestId", "moduleId", "contentHash", "session", "topic", "node"]) else {
            throw WorkshopOriginalLedgerError.mixed
        }
        guard object["schema"] as? String == "mod-installation-native-runtime-v1",
              object["status"] as? String == "SUPPORTED",
              let sourceHash = object["sourceHash"] as? String, WorkshopModuleImportGate.sha256Hex(sourceHash),
              let runHash = object["runHash"] as? String, WorkshopModuleImportGate.sha256Hex(runHash),
              exactLong(object["sessionId"]) == sessionID,
              let topicID = exactLong(object["topicId"]),
              let nodeID = exactLong(object["nodeId"]),
              exactLong(object["activityId"]) != nil else {
            throw WorkshopOriginalLedgerError.unknown
        }
        let kind = object["kind"] as? String
        guard kind == "CHOICE" || kind == "QA_PICK" else { throw WorkshopOriginalLedgerError.unknown }
        return WorkshopAdvancedProvenance(sourceHash: sourceHash, runHash: runHash, sessionID: sessionID,
                                          topicID: topicID, nodeID: nodeID, memberID: memberID)
    }

    /// Public `ArtifactReceipt` from the authorized register response.
    /// There is no module/release read, and `status` or `template` are not this receipt.
    public func acceptRegisteredArtifact(_ data: Data, moduleID: String, releaseID: String) throws -> WorkshopNativeArtifactFreeze {
        guard WorkshopModuleImportGate.idOK(moduleID), WorkshopModuleImportGate.idOK(releaseID),
              let object = jsonObject(data) else { throw WorkshopOriginalLedgerError.invalid }
        if mixes(object, foreign: ["status", "template", "outcome", "sourceHash", "serverPass"]) {
            throw WorkshopOriginalLedgerError.mixed
        }
        let schemas = ["w18-native-text-template-v1", "w18-qmod-choice-topic-v1", "w18-qmod-qa-pick-topic-v1"]
        guard object["moduleId"] as? String == moduleID,
              object["releaseId"] as? String == releaseID,
              let schema = object["schema"] as? String, schemas.contains(schema),
              let title = object["title"] as? String, !title.isEmpty,
              let approval = object["contentApprovalReference"] as? String, !approval.isEmpty,
              let contentHash = object["contentHash"] as? String, WorkshopModuleImportGate.sha256Hex(contentHash),
              bindings(object["requiredBindings"]) else {
            throw WorkshopOriginalLedgerError.unknown
        }
        return WorkshopNativeArtifactFreeze(moduleID: moduleID, releaseID: releaseID,
                                            contentHash: contentHash, memberID: 0)
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func mixes(_ object: [String: Any], foreign: [String]) -> Bool {
        foreign.contains { object[$0] != nil }
    }

    private func bindings(_ value: Any?) -> Bool {
        guard let rows = value as? [Any] else { return false }
        for row in rows {
            guard let item = row as? [String: Any],
                  let key = item["key"] as? String, !key.isEmpty,
                  let kind = item["kind"] as? String, !kind.isEmpty else { return false }
        }
        return true
    }

    private func jsonBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private func exactLong(_ value: Any?) -> Int64? {
        if let text = value as? String {
            guard text.count <= 19, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  !(text.count > 1 && text.hasPrefix("0")),
                  let number = Int64(text), String(number) == text, number > 0 else { return nil }
            return number
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        switch CFNumberGetType(number) {
        case .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type, .charType, .shortType, .intType,
             .longType, .longLongType, .cfIndexType, .nsIntegerType:
            let parsed = number.int64Value
            return parsed > 0 ? parsed : nil
        default:
            return nil
        }
    }
}
