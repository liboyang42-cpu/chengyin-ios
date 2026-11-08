import Foundation

extension PlayExperienceService {
    /// Source: AdvancedActionReceiptReader at hengyin 147754ba8740abf208bda75cf86ed5901cac4c02.
    /// GET only, under the existing read lifetime and authentication gates.
    public func qaTextReceipt(_ pending: PlayAdvancedPending, activityID: Int,
                              topicID: Int, nodeID: Int, token: String) async throws -> PlayQATextActionReceipt {
        let query = try PlayQATextActionReceipt.query(for: pending)
        let raw = try await request("api/play/advanced/receipt", query: query, capability: .reads, token: token)
        return try PlayQATextActionReceipt(raw, pending: pending, activityID: activityID, topicID: topicID, nodeID: nodeID)
    }
}
