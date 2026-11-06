import Foundation
import CryptoKit

public enum IMVideoFailure: Error { case unavailable, invalid, unsafe, unknown, stale, expired, unsupported }
/// Formal duration is known. Byte limits must come from the current, explicitly configured original video policy.
public struct IMVideoPolicy: Codable, Equatable {
    public let source: String
    public let maximumSourceBytes: Int
    public let maximumOutputBytes: Int
    public let maximumDurationMS: Int
    public let outputMIME: String
    public func validate() throws {
        guard source == "original-im-video-policy-v1", maximumSourceBytes > 0, maximumSourceBytes <= 64 * 1024 * 1024, maximumOutputBytes > 0, maximumOutputBytes <= 64 * 1024 * 1024,
              maximumDurationMS == 30_000, outputMIME == "video/mp4" else { throw IMVideoFailure.invalid }
    }
}
public struct IMVideoSelection: Equatable {
    public static let maximumBytes = 64 * 1024 * 1024 // implementation resource ceiling, never an enabled policy
    public let name: String
    public let bytes: Data
    public let policy: IMVideoPolicy
    public var sha256: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public init(name: String, bytes: Data, policy: IMVideoPolicy) throws {
        try policy.validate()
        guard !bytes.isEmpty, bytes.count <= policy.maximumSourceBytes, !name.isEmpty, name.utf8.count <= 240,
              !name.contains("/"), !name.contains("\\"), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw IMVideoFailure.invalid }
        self.name = name; self.bytes = bytes; self.policy = policy
    }
}
/// Original normalized video + persistent cover identities. A reference is not a moderation decision.
public struct IMVideoReference: Codable, Equatable {
    public let uploadRequestID: String
    public let attachmentID: String
    public let sha256: String
    public let coverSHA256: String
    public let size: Int
    public let coverSize: Int
    public let durationMS: Int
    public let width: Int
    public let height: Int
    public func validate() throws {
        guard let request = UUID(uuidString: uploadRequestID), request.uuidString.lowercased() == uploadRequestID,
              let id = Int64(attachmentID), id > 0, String(id) == attachmentID,
              size > 0, size <= 64 * 1024 * 1024, coverSize > 0, coverSize <= 10 * 1024 * 1024, durationMS > 0, durationMS <= 30_000, width > 0, height > 0,
              [sha256, coverSHA256].allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) else { throw IMVideoFailure.invalid }
    }
    public func wireFields() throws -> [String: String] {
        try validate()
        let reference = try JSONEncoder().encode(self)
        guard var object = try JSONSerialization.jsonObject(with: reference) as? [String: Any] else { throw IMVideoFailure.invalid }
        object["source"] = "original-im-video-v1"
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let extra = String(data: bytes, encoding: .utf8) else { throw IMVideoFailure.invalid }
        return ["msg_type": "11", "content": "[视频]", "extra_json": extra]
    }
    public static func read(_ message: MessagingMessage) -> Self? {
        guard message.type == 11, message.isPayloadVisible, message.content == "[视频]",
              let bytes = message.extraJSON?.data(using: .utf8), bytes.count <= 4096,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], object["source"] as? String == "original-im-video-v1",
              let value = try? JSONDecoder().decode(Self.self, from: bytes), (try? value.validate()) != nil else { return nil }
        return value
    }
}

public struct IMVideoUploadReceipt: Decodable {
    public let source: String
    public let ownerMemberID: String
    public let conversationID: String
    public let requestID: String
    public let sourceSHA256: String
    public let state: String
    public let videoReviewState: String?
    public let coverReviewState: String?
    public let reference: IMVideoReference?
    enum CodingKeys: String, CodingKey {
        case source,state,reference
        case ownerMemberID="owner_member_id",conversationID="conversation_id",requestID="upload_request_id",sourceSHA256="source_sha256"
        case videoReviewState="video_review_state",coverReviewState="cover_review_state"
    }
    public var ready: Bool { state == "UPLOADED" && videoReviewState == "APPROVED" && coverReviewState == "APPROVED" && reference != nil }
    public func validate(scope: IMScope, requestID: String, hash: String) throws {
        guard source == "original-im-video-upload-v1",ownerMemberID == String(scope.identity.accountID),conversationID == String(scope.conversationID),
              self.requestID == requestID,sourceSHA256 == hash,["NOT_FOUND","RESERVED","UPLOADED"].contains(state) else { throw IMVideoFailure.invalid }
        if let reference { try reference.validate(); guard reference.uploadRequestID == requestID else { throw IMVideoFailure.invalid } }
        if state != "NOT_FOUND" {
            guard reference != nil, let videoReviewState, let coverReviewState,
                  ["HOLD","APPROVED","REJECTED"].contains(videoReviewState),["HOLD","APPROVED","REJECTED"].contains(coverReviewState) else { throw IMVideoFailure.invalid }
        }
    }
}
