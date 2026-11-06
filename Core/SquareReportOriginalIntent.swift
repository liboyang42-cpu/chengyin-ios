import Foundation
import CryptoKit

/// Minimal durable original intent, never a current permission or a stored report description.
/// Epoch is deliberately not persisted: a later login may read its own original request, but
/// each in-flight read still checks the caller's current full identity including epoch.
struct SquareReportOriginalIntent: Codable, Equatable {
    let format: Int
    let namespace: String
    let accountID: Int
    let targetType: String
    let targetID: Int
    let requestID: String
    let semanticSHA256: String
    init(_ review: SquareReportReview) throws {
        format = 1; namespace = review.snapshot.identity.namespace; accountID = review.snapshot.identity.accountID
        targetType = review.snapshot.target.type; targetID = review.snapshot.target.id; requestID = review.requestID
        semanticSHA256 = try Self.digest(requestID: requestID, type: targetType, id: targetID,
            reason: review.reason.id, policy: review.snapshot.policy.version, description: review.description)
    }
    func validate(target: SquareReportTarget, identity: SquareGovernanceIdentity) throws {
        guard format == 1, identity.valid, namespace == identity.namespace, accountID == identity.accountID,
              targetType == target.type, targetID == target.id, validRequest,
              semanticSHA256.count == 64, semanticSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SquareReportFailure.unknown
        }
    }
    var validRequest: Bool {
        let prefix = "square-report-"
        guard requestID.hasPrefix(prefix), let uuid = UUID(uuidString: String(requestID.dropFirst(prefix.count))) else { return false }
        return requestID == prefix + uuid.uuidString
    }
    func matches(_ receipt: SquareReportReceipt) throws -> Bool {
        guard receipt.targetType == targetType, receipt.targetID == targetID else { return false }
        return try semanticSHA256 == Self.digest(requestID: requestID, type: receipt.targetType, id: receipt.targetID,
            reason: receipt.reasonCode, policy: receipt.policyVersion, description: receipt.description)
    }
    private static func digest(requestID: String, type: String, id: Int, reason: String, policy: String, description: String) throws -> String {
        // JSON array has unambiguous UTF-8 field boundaries. Attachments are forbidden by this writer.
        let data = try JSONEncoder().encode(["square-report-original-v1", requestID, type, String(id), reason, policy, description])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
