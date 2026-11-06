import Foundation
import CoreFoundation

/// Exact club-post-v1 identity, separate from legacy mutation and current visibility.
struct ClubPostOriginalIdentity {
    static let namespace = "club-post-v1"
    let record: ClubCommunityPendingRecord
    init(_ record: ClubCommunityPendingRecord) throws {
        guard record.receiptNamespace == Self.namespace,
              ["create", "edit"].contains(record.operationKind), record.target.commentID == 0,
              let key = record.requestID, key.range(of: "^[A-Za-z0-9_.:-]{1,64}$", options: .regularExpression) != nil,
              let version = record.postVersion, version >= 0,
              record.operationKind == "create" ? (record.target.postID == 0 && version == 0) : record.target.postID > 0 else {
            throw ClubCommunityFailure.invalid
        }
        self.record = record
    }
    var fields: [String:Any] {
        ["receiptNamespace":Self.namespace,"operationId":record.operationID.uuidString,
         "requestId":record.requestID!,"operationKind":record.operationKind,"clubId":record.target.clubID,
         "postId":record.target.postID,"commentId":0,"version":record.postVersion!]
    }
    func result(_ payload: Any) throws -> ClubCommunityPendingQueryResult {
        guard let raw = payload as? [String:Any] else { throw ClubCommunityFailure.invalid }
        for (key, expected) in fields {
            if let number = expected as? Int {
                guard let actual = raw[key] as? NSNumber, CFGetTypeID(actual) != CFBooleanGetTypeID(), actual.stringValue == String(number) else { throw ClubCommunityFailure.stale }
            } else {
                guard let expected = expected as? String, let actual = raw[key] as? String,
                      actual.utf8.elementsEqual(expected.utf8) else { throw ClubCommunityFailure.stale }
            }
        }
        let identityKeys = Set(fields.keys)
        if raw["status"] as? String == "PENDING" {
            guard Set(raw.keys) == identityKeys.union(["status"]) else { throw ClubCommunityFailure.invalid }
            return .stillPending
        }
        guard let hash = raw["sourceSHA256"] as? String, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ClubCommunityFailure.invalid }
        switch raw["status"] as? String {
        case "ACKNOWLEDGED":
            guard Set(raw.keys) == identityKeys.union(["status","sourceSHA256","resultPostId","resultVersion"]),
                  let post = raw["resultPostId"] as? NSNumber, CFGetTypeID(post) != CFBooleanGetTypeID(),
                  let version = raw["resultVersion"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
                  post.stringValue == String(post.intValue), post.intValue > 0,
                  version.stringValue == String(version.intValue), version.intValue >= record.postVersion!,
                  record.operationKind != "edit" || post.intValue == record.target.postID else { throw ClubCommunityFailure.invalid }
            return .resolved(.acknowledged(operationID:record.operationID))
        case "REJECTED":
            guard Set(raw.keys) == identityKeys.union(["status","sourceSHA256","rejectedCode"]),
                  let code = raw["rejectedCode"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(),
                  code.stringValue == String(code.intValue), code.intValue > 0 else { throw ClubCommunityFailure.invalid }
            return .resolved(.rejected(operationID:record.operationID,code:code.intValue))
        default: throw ClubCommunityFailure.invalid
        }
    }
}
