import Foundation

extension PlayExperienceService {
    /// Source: AdvancedActionReceiptReader at hengyin 147754ba8740abf208bda75cf86ed5901cac4c02.
    /// GET only, under the existing read lifetime and authentication gates.
    public func qaTextReceipt(_ pending: PlayAdvancedPending, activityID: Int,
                              topicID: Int, nodeID: Int, token: String) async throws -> PlayQATextActionReceipt {
        let identity = try PlayQATextReceiptRequest(pending, activityID: activityID, topicID: topicID, nodeID: nodeID)
        return try await qaTextReceipt(identity, token: token)
    }
    /// Relaunch recovery needs only redacted metadata, never a fabricated answer
    /// payload or a replacement session. Shares the exact original GET decoder.
    @MainActor public func qaTextReceipt(_ identity: PlayQATextReceiptRequest, token: String) async throws -> PlayQATextActionReceipt {
        let raw = try await request("api/play/advanced/receipt", query: identity.query, capability: .reads, token: token)
        return try PlayQATextActionReceipt(raw, request: identity)
    }
}

extension PlayExperienceService: PlayQATextReceiptReading {}
