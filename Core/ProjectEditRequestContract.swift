import Foundation
import CryptoKit

/// New paired technical request producer around the original four project writers.
/// Not a replacement editor/publish endpoint, and never inferred for an old local-only UUID.
public enum ProjectEditRequestContract {
    public static let protocolVersion = "original-project-edit-request-v1"
    public static let submitPath = "api/topic/edit-requests/submit"
    public static let readPath = "api/topic/edit-requests/read"
    public static let resumePostProcessingPath = "api/topic/edit-requests/resume-post-processing"
    public static let originalPaths: Set<String> = ["api/topic/create", "api/topic/update", "api/topic/v2/create", "api/topic/v2/update"]
    public static func payloadBytes(_ payload: [String: ProjectEditJSON]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
    public static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    public struct Submit: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let originalPath: String
        public let payloadSHA256: String
        public let payloadBase64Chunks: [String]
        /// Validate preserved bytes without re-encoding on an upgraded OS or after process restart.
        public func matches(operationID: UUID, originalPath: String, payload: [String: ProjectEditJSON]) -> Bool {
            guard protocolVersion == ProjectEditRequestContract.protocolVersion,
                  requestId == operationID.uuidString.lowercased(), self.originalPath == originalPath,
                  ProjectEditRequestContract.originalPaths.contains(originalPath),
                  !payloadBase64Chunks.isEmpty, payloadBase64Chunks.count <= 86,
                  payloadBase64Chunks.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32_768 }),
                  let bytes = Data(base64Encoded: payloadBase64Chunks.joined()), !bytes.isEmpty, bytes.count <= 2_097_152,
                  ProjectEditRequestContract.digest(bytes) == payloadSHA256,
                  let decoded = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: bytes) else { return false }
            guard let original = ProjectEditPendingMaterials.exactData(payload),
                  let restored = ProjectEditPendingMaterials.exactData(decoded) else { return false }
            return original == restored
        }
        public init(operationID: UUID, originalPath: String, payload: [String: ProjectEditJSON]) throws {
            guard ProjectEditRequestContract.originalPaths.contains(originalPath) else { throw ProjectEditError.invalidContract }
            let bytes = try ProjectEditRequestContract.payloadBytes(payload)
            guard !bytes.isEmpty, bytes.count <= 2_097_152 else { throw ProjectEditError.invalidContract }
            self.protocolVersion = ProjectEditRequestContract.protocolVersion
            requestId = operationID.uuidString.lowercased(); self.originalPath = originalPath
            payloadSHA256 = ProjectEditRequestContract.digest(bytes)
            let encoded = Array(bytes.base64EncodedString().utf8)
            payloadBase64Chunks = stride(from: 0, to: encoded.count, by: 32_768).map { start in
                String(decoding: encoded[start..<min(start + 32_768, encoded.count)], as: UTF8.self)
            }
        }
    }
    public struct Read: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let originalPath: String
        public let payloadSHA256: String
        public let scope: String
        public init(envelope: Submit, scope: String) {
            protocolVersion = envelope.protocolVersion; requestId = envelope.requestId
            originalPath = envelope.originalPath; payloadSHA256 = envelope.payloadSHA256; self.scope = scope
        }
    }

}
