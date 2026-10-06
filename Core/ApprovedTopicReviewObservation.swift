import Foundation

/// An as-read task row, never an approved preparation or immutable release receipt.
public struct ApprovedTopicReviewObservation: Equatable, Sendable {
    public enum Status: Int, Equatable, Sendable { case pending = 0, approved = 1, rejected = 2, escalated = 3, cancelled = 4 }
    public let topicID: Int, auditTaskID: Int, submittedTaskVersion: Int, observedTaskVersion: Int
    public let requestID: String, submittedSnapshotHash: String, observedSnapshotHash: String
    public let status: Status
    public let matchesSubmittedCapture: Bool
    public static func decode(_ value: ProjectEditJSON, record: ApprovedTopicReviewJournal.Record) throws -> Self {
        guard let receipt = record.receipt, let root = value.object,
              Set(root.keys) == ["contract", "topicId", "auditTaskId", "requestId", "submittedTaskVersion", "observedTaskVersion", "observedTaskStatus", "submittedSnapshotHash", "observedSnapshotHash", "matchesSubmittedCapture", "approvalProof", "releaseAllocated"],
              root["contract"]?.text == "questify.topic-release.review-observation.v1",
              root["approvalProof"] == .bool(false), root["releaseAllocated"] == .bool(false),
              root["topicId"]?.integer == receipt.topicID, root["auditTaskId"]?.integer == receipt.auditTaskID,
              root["requestId"]?.text == receipt.requestID, root["submittedTaskVersion"]?.integer == receipt.submittedTaskVersion,
              root["submittedSnapshotHash"]?.text == receipt.snapshotHash,
              let version = root["observedTaskVersion"]?.integer, version >= receipt.submittedTaskVersion, version <= Int(Int32.max),
              let status = root["observedTaskStatus"]?.integer.flatMap(Status.init(rawValue:)),
              let hash = root["observedSnapshotHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash),
              case .bool(let matches)? = root["matchesSubmittedCapture"], matches == (hash == receipt.snapshotHash) else { throw ApprovedTopicReleaseError.invalidResponse }
        return .init(topicID: receipt.topicID, auditTaskID: receipt.auditTaskID, submittedTaskVersion: receipt.submittedTaskVersion, observedTaskVersion: version,
            requestID: receipt.requestID, submittedSnapshotHash: receipt.snapshotHash, observedSnapshotHash: hash, status: status, matchesSubmittedCapture: matches)
    }
}

@MainActor public protocol ApprovedTopicReviewObserving: AnyObject {
    func canObserve(session: ProjectEditSession) -> Bool
    func observe(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewObservation
}
