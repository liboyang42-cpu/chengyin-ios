import Foundation

/// Personal new-template subset of the original-template-author-request-v1 producer.
/// Preserves the donor wire identity; owner edits, merchant, adoption, market and copy
/// branches are deliberately unavailable until their own original contexts are integrated.
public enum TemplateAuthoringRequestReceipt {
    public static let protocolVersion = "original-template-author-request-v1"
    public static let submitPath = "api/template/author-requests/submit"
    public static let readPath = "api/template/author-requests/read"

    public struct Command: Codable, Equatable {
        public let originalPath: String
        public let fields: [String: TemplateAuthoringJSON]
        public init(request: TemplateAuthoringRequest) throws {
            guard TemplateAuthoringContract.permitsRemoteConfiguration(request), request.mutates,
                  ["/api/template/draft", "/api/template/publish"].contains(request.path),
                  case .json(let fields) = request.body else { throw TemplateAuthoringError.invalidContract }
            originalPath = String(request.path.dropFirst()); self.fields = fields
        }
        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        private enum CodingKeys: String, CodingKey { case originalPath, fields }
        public init(from decoder: Decoder) throws {
            // Do not silently erase unsupported command bindings on decode.
            let all = try decoder.container(keyedBy: Key.self)
            guard Set(all.allKeys.map(\.stringValue)) == Set(["originalPath", "fields"]) else {
                throw TemplateAuthoringError.invalidContract
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            originalPath = try c.decode(String.self, forKey: .originalPath)
            fields = try c.decode([String: TemplateAuthoringJSON].self, forKey: .fields)
            guard valid else { throw TemplateAuthoringError.invalidContract }
        }
        public var descriptor: TemplateAuthoringRequest {
            .init(path: "/" + originalPath, body: .json(fields), mutates: true)
        }
        public var valid: Bool { (try? Command(request: descriptor)) == self }
    }
    public struct Submit: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let payloadBase64Chunks: [String]
        public init(id: UUID, command: Command) throws {
            guard command.valid else { throw TemplateAuthoringError.invalidContract }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(command)
            guard !bytes.isEmpty, bytes.count <= 2_097_152 else { throw TemplateAuthoringError.invalidContract }
            protocolVersion = TemplateAuthoringRequestReceipt.protocolVersion
            requestId = id.uuidString.lowercased(); payloadSHA256 = ProjectEditRequestContract.digest(bytes)
            let text = Array(bytes.base64EncodedString().utf8)
            payloadBase64Chunks = stride(from: 0, to: text.count, by: 32_768).map {
                String(decoding: text[$0..<min($0 + 32_768, text.count)], as: UTF8.self)
            }
        }
        public var command: Command? {
            guard protocolVersion == TemplateAuthoringRequestReceipt.protocolVersion,
                  UUID(uuidString: requestId)?.uuidString.lowercased() == requestId,
                  !payloadBase64Chunks.isEmpty, payloadBase64Chunks.count <= 86,
                  payloadBase64Chunks.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32_768 }),
                  let bytes = Data(base64Encoded: payloadBase64Chunks.joined()), !bytes.isEmpty, bytes.count <= 2_097_152,
                  ProjectEditRequestContract.digest(bytes) == payloadSHA256,
                  let value = try? JSONDecoder().decode(Command.self, from: bytes), value.valid else { return nil }
            return value
        }
        /// Validate preserved wire bytes; never rebuild a request identity from a legacy UUID.
        public func matches(operationID: UUID, request: TemplateAuthoringRequest) -> Bool {
            guard requestId == operationID.uuidString.lowercased(), let command,
                  let expected = ProjectEditPendingMaterials.exactData(request) else { return false }
            return ProjectEditPendingMaterials.exactData(command.descriptor) == expected
        }
    }
    public struct Read: Codable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public init(_ value: Submit) {
            protocolVersion = value.protocolVersion; requestId = value.requestId; payloadSHA256 = value.payloadSHA256
        }
    }
    public struct Processing: Codable, Equatable {
        public let protocolVersion: String
        public let requestID: String
        public let payloadSHA256: String
        public let contentSHA256: String
        public let media: [ProjectEditPostProcessingReceipt.Media]
        public let canResume: Bool
    }
    public struct Receipt: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        /// Opaque unsupported branch marker: any non-null merchant value is rejected.
        public var merchant: TemplateAuthoringJSON? = nil
        public let state: String
        public let originalResult: TemplateAuthoringJSON?
        public let postProcessing: String?
        public let processing: Processing?
        public let auditState: String?
        public let auditActions: [String]?
        public var memberTemplateID: MemberPlayTemplateID? {
            originalResult?.object?["memberTemplateId"]?.integer.flatMap(MemberPlayTemplateID.init(rawValue:))
        }
        public var committed: Bool { state == "COMMITTED" && memberTemplateID != nil }
        public var terminal: Bool { committed || state == "REJECTED" }
        public func matches(_ value: Submit) -> Bool {
            value.command != nil && merchant == nil && protocolVersion == value.protocolVersion &&
            requestId == value.requestId && payloadSHA256 == value.payloadSHA256 &&
            ["NOT_FOUND", "RUNNING", "COMMITTED", "REJECTED"].contains(state) &&
            (processing == nil || (processing?.protocolVersion == "original-template-author-media-v1" &&
                processing?.requestID == requestId && processing?.payloadSHA256 == payloadSHA256)) &&
            (state != "COMMITTED" || memberTemplateID != nil)
        }
    }
}
