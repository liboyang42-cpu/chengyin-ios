import Foundation

public enum ProjectStateRequestContract {
    public static let protocolVersion = "original-project-state-request-v1"
    public static let contextPath = "api/project/state-requests/context"
    public static let submitPath = "api/project/state-requests/submit"
    public static let readPath = "api/project/state-requests/read"
    public struct Context: Codable, Equatable {
        public let protocolVersion: String
        public let kind: String
        public let resourceId: Int
        public let title: String
        public let online: Bool
        public let baselineHash: String
        public func matches(_ project: PublishingProject) -> Bool {
            protocolVersion == ProjectStateRequestContract.protocolVersion && kind == project.resource.kind.rawValue && resourceId == project.resource.value && title == project.title && online == project.online && baselineHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
        }
    }
    public struct Command: Codable, Equatable {
        public let originalPath: String
        public let resourceId: Int
        public let baselineHash: String
        public let expectedOnline: Bool
        public let fields: [String: ProjectEditJSON]
        public var valid: Bool {
            guard resourceId > 0, baselineHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
                  let kind = ProjectStateRequestContract.resourceKind(originalPath) else { return false }
            var expected: [String: ProjectEditJSON] = [kind == "template" ? "template_id" : "id": .string(String(resourceId))]
            if originalPath == "api/topic/update_user_status" { expected["expectedUserStatus"] = .string(expectedOnline ? "1" : "0") }
            if originalPath == "api/template/updateLibraryStatus" { expected["publish_status"] = .string(expectedOnline ? "0" : "1") }
            return fields == expected
        }
    }
    public struct Submit: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let payloadBase64Chunks: [String]
        public init(id: UUID, request: PublishingRequest, project: PublishingProject, context: Context) throws {
            guard context.matches(project), request.encoding == .form else { throw PublishModesError.conflict }
            let command = Command(originalPath: request.path, resourceId: project.resource.value, baselineHash: context.baselineHash, expectedOnline: context.online, fields: request.fields)
            guard command.valid, ProjectStateRequestContract.resourceKind(command.originalPath) == project.resource.kind.rawValue else { throw PublishModesError.invalidContract }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(command); guard !bytes.isEmpty, bytes.count <= 2_097_152 else { throw PublishModesError.invalidContract }
            protocolVersion = ProjectStateRequestContract.protocolVersion; requestId = id.uuidString.lowercased(); payloadSHA256 = ProjectEditRequestContract.digest(bytes)
            let encoded = Array(bytes.base64EncodedString().utf8)
            payloadBase64Chunks = stride(from: 0, to: encoded.count, by: 32_768).map { String(decoding: encoded[$0..<min($0 + 32_768, encoded.count)], as: UTF8.self) }
        }
        public var command: Command? {
            guard protocolVersion == ProjectStateRequestContract.protocolVersion, UUID(uuidString: requestId)?.uuidString.lowercased() == requestId,
                  !payloadBase64Chunks.isEmpty, payloadBase64Chunks.count <= 86, payloadBase64Chunks.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32_768 }),
                  let bytes = Data(base64Encoded: payloadBase64Chunks.joined()), !bytes.isEmpty, bytes.count <= 2_097_152,
                  ProjectEditRequestContract.digest(bytes) == payloadSHA256 else { return nil }
            guard let command = try? JSONDecoder().decode(Command.self, from: bytes), command.valid else { return nil }; return command
        }
    }
    public struct Read: Codable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let originalPath: String
        public let resourceId: Int
        public let baselineHash: String
        public let expectedOnline: Bool
        public init(_ submit: Submit) throws {
            guard let command = submit.command else { throw PublishModesError.invalidContract }
            protocolVersion = submit.protocolVersion; requestId = submit.requestId; payloadSHA256 = submit.payloadSHA256
            originalPath = command.originalPath; resourceId = command.resourceId; baselineHash = command.baselineHash; expectedOnline = command.expectedOnline
        }
    }
    public struct Receipt: Codable, Equatable {
        public let protocolVersion: String
        public let requestId: String
        public let payloadSHA256: String
        public let originalPath: String
        public let kind: String
        public let resourceId: Int
        public let state: String
        public let originalResult: ProjectEditJSON?
        public var applied: Bool { state == "COMMITTED" && originalResult?.object?["applied"] == .bool(true) }
        public var terminal: Bool { (state == "COMMITTED" && (originalResult?.object?["applied"] == .bool(true) || originalResult?.object?["applied"] == .bool(false))) || state == "REJECTED" }
        public func matches(_ submit: Submit) -> Bool {
            guard let command = submit.command else { return false }
            return (state != "COMMITTED" || terminal) && protocolVersion == ProjectStateRequestContract.protocolVersion && requestId == submit.requestId && payloadSHA256 == submit.payloadSHA256 && originalPath == command.originalPath && kind == ProjectStateRequestContract.resourceKind(command.originalPath) && resourceId == command.resourceId && ["NOT_FOUND", "RUNNING", "COMMITTED", "REJECTED"].contains(state)
        }
    }
    static func resourceKind(_ path: String) -> String? {
        switch path {
        case "api/template/delete", "api/template/updateLibraryStatus": return "template"
        case "api/topic/delete", "api/topic/update_user_status": return "topic"
        case "api/activity/delete", "api/activity/update_publish_status": return "activity"
        default: return nil
        }
    }
    public struct Saved: Codable, Equatable, Identifiable {
        public var id: String { submit.requestId }
        public let ownerKey: String
        public let title: String
        public let resource: PublishedResource
        public let action: PublishingProjectAction
        public let submit: Submit
        public let receipt: Receipt?
        public init(ownerKey: String, title: String, resource: PublishedResource, action: PublishingProjectAction, submit: Submit, receipt: Receipt? = nil) {
            self.ownerKey = ownerKey; self.title = title; self.resource = resource; self.action = action; self.submit = submit; self.receipt = receipt
        }
        public var valid: Bool {
            guard let command = submit.command,
                  command.resourceId == resource.value,
                  ProjectStateRequestContract.resourceKind(command.originalPath) == resource.kind.rawValue,
                  (action == .remove) == command.originalPath.hasSuffix("/delete") else { return false }
            return receipt == nil || receipt?.matches(submit) == true
        }
        public var targetKey: String { "publishModes:\(resource.kind.rawValue):\(resource.value)" }
    }
}
