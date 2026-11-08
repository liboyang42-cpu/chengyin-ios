import Foundation

/// Binds a read-only receipt to the original ordinary-text QA request. This is
/// identity evidence only: the server view remains the sole verdict source.
public struct PlayQATextActionReceipt: Equatable {
    public let view: PlayWireValue
    public let request: PlayQATextReceiptRequest

    /// Payload signature alone does not identify a mode. The coordinator must
    /// additionally bind its original server QA segment using matchesTextMode.
    public static func owns(_ pending: PlayAdvancedPending?) -> Bool {
        guard let pending else { return false }
        return pending.action == "SUBMIT_QA" && Set(pending.payload.keys) == ["input"]
    }

    public static func matchesTextMode(_ qa: PlayWireValue) -> Bool {
        qa.object != nil && (qa["mode"].text ?? "TYPE").uppercased() == "TYPE"
    }

    public static func query(for pending: PlayAdvancedPending) throws -> [String: String] {
        guard owns(pending), pending.sessionID > 0, pending.version >= 0,
              !pending.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pending.key.utf16.count <= 64,
              let input = pending.payload["input"]?.text,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.utf16.count <= 4096 else { throw APIError.invalidRequest }
        // Never send the submitted answer again during reconciliation.
        return ["sessionId": String(pending.sessionID), "idempotencyKey": pending.key]
    }

    public init(_ raw: PlayWireValue, pending: PlayAdvancedPending,
                activityID: Int, topicID: Int, nodeID: Int) throws {
        try self.init(raw, request: .init(pending, activityID: activityID, topicID: topicID, nodeID: nodeID))
    }

    public init(_ raw: PlayWireValue, request: PlayQATextReceiptRequest) throws {
        try request.validate()
        let view = raw["view"]
        guard raw["sessionId"].text == String(request.sessionID),
              let key = raw["idempotencyKey"].text, key.utf8.elementsEqual(request.key.utf8),
              view["sessionId"].integer == request.sessionID,
              view["activityId"].integer == request.activityID,
              view["topicId"].integer == request.topicID, view["nodeId"].integer == request.nodeID,
              let version = view["version"].integer, version > request.version,
              let status = view["status"].text, !status.isEmpty else { throw PlayExperienceError.malformed }
        self.view = view; self.request = request
    }

    /// Receipt 404/409, disabled capability, malformed data, cancellation and lost
    /// transport all retain UNKNOWN. None proves the original POST did not run.
    public static func failurePhase(_ error: Error, ownerIsCurrent: Bool) -> String {
        guard ownerIsCurrent else { return "stale" }
        if case PlayExperienceError.unauthorized = error { return "stale" }
        if case APIError.unauthorized = error { return "stale" }
        return "unknown"
    }
}
