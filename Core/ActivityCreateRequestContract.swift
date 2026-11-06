import Foundation

public enum ActivityCreateRequestContract {
    public static let protocolVersion = "original-activity-create-request-v1"
    public static let submitPath = "api/activity/create-requests/submit"
    public static let readPath = "api/activity/create-requests/read"
    public static let resumePath = "api/activity/create-requests/resume-post-processing"
    public struct Submit: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let payloadBase64Chunks: [String]
        public let merchantId: Int?
        public let ownerId: Int?
        public let actorId: Int?
        public init(id: UUID, fields: [String: ProjectEditJSON]) throws {
            guard fields["id"] == nil, fields["scope"] == nil, fields["requestId"] == nil else { throw PublishModesError.invalidContract }
            let bytes = try ProjectEditRequestContract.payloadBytes(fields)
            guard !bytes.isEmpty, bytes.count <= 2_097_152 else { throw PublishModesError.invalidContract }
            merchantId = nil; ownerId = nil; actorId = nil
            protocolVersion = ActivityCreateRequestContract.protocolVersion; requestId = id.uuidString.lowercased()
            payloadSHA256 = ProjectEditRequestContract.digest(bytes)
            let encoded = Array(bytes.base64EncodedString().utf8)
            payloadBase64Chunks = stride(from: 0, to: encoded.count, by: 32_768).map { String(decoding: encoded[$0..<min($0 + 32_768, encoded.count)], as: UTF8.self) }
        }
        public var submitPath: String { ActivityCreateRequestContract.submitPath }
        public var readPath: String { ActivityCreateRequestContract.readPath }
        public var resumePath: String { ActivityCreateRequestContract.resumePath }
        public var valid: Bool {
            guard protocolVersion == ActivityCreateRequestContract.protocolVersion, UUID(uuidString: requestId)?.uuidString.lowercased() == requestId,
                  !payloadBase64Chunks.isEmpty, payloadBase64Chunks.count <= 86,
                  payloadBase64Chunks.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32_768 }),
                  let bytes = Data(base64Encoded: payloadBase64Chunks.joined()), !bytes.isEmpty, bytes.count <= 2_097_152,
                  ProjectEditRequestContract.digest(bytes) == payloadSHA256,
                  let fields = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: bytes) else { return false }
            return merchantId == nil && ownerId == nil && actorId == nil && fields["id"] == nil && fields["scope"] == nil && fields["requestId"] == nil
        }
    }
    public struct Read: Codable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let merchantId: Int?
        public let ownerId: Int?
        public let actorId: Int?
        public init(_ value: Submit) { actorId = value.actorId; merchantId = value.merchantId; ownerId = value.ownerId; protocolVersion = value.protocolVersion; requestId = value.requestId; payloadSHA256 = value.payloadSHA256 }
    }
    public struct Processing: Codable, Equatable {
        public let protocolVersion: String
        public let requestID: String
        public let payloadSHA256: String
        public let spotCheckState: String
        public let audits: [ProjectEditPostProcessingReceipt.Audit]
        public let media: [ProjectEditPostProcessingReceipt.Media]
        public let canResume: Bool
    }
    public struct Receipt: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let state: String
        public let merchantId: Int?
        public let ownerId: Int?
        public let actorId: Int?
        public let originalResult: ProjectEditJSON?
        public let auditState: String?
        public let auditActions: [String]?
        public let postProcessing: String?
        public let processing: Processing?
        public var activityID: Int? { originalResult?.object?["activityId"]?.integer.flatMap { $0 > 0 ? $0 : nil } }
        public var committed: Bool { state == "COMMITTED" && activityID != nil }
        public var terminal: Bool { committed || state == "REJECTED" }
        public func matches(_ submit: Submit) -> Bool {
            submit.valid && (state != "COMMITTED" || committed) && protocolVersion == submit.protocolVersion && merchantId == submit.merchantId && ownerId == submit.ownerId && actorId == submit.actorId && requestId == submit.requestId && payloadSHA256 == submit.payloadSHA256 && ["NOT_FOUND", "RUNNING", "COMMITTED", "REJECTED"].contains(state)
                && (processing == nil || (processing?.protocolVersion == "original-activity-create-postprocess-v1" && processing?.requestID == requestId && processing?.payloadSHA256 == payloadSHA256))
        }
    }
    public struct Saved: Codable, Equatable {
        public let ownerKey: String
        public let submit: Submit
        public let receipt: Receipt?
        public init(ownerKey: String, submit: Submit, receipt: Receipt? = nil) { self.ownerKey = ownerKey; self.submit = submit; self.receipt = receipt }
    }
}
