import Foundation

public enum ApprovedTopicReviewPath {
    public static let prepare = "api/approved-topic-release/v1/review/prepare"
    public static let submit = "api/approved-topic-release/v1/review/submit"
    public static let status = "api/approved-topic-release/v1/review/status"
    public static let current = "api/approved-topic-release/v1/review/current"
}

/// Current server capture for a new review request. This type cannot be used as an approved release preparation.
public struct ApprovedTopicReviewCapture: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public let id: Int, templateID: Int, nodeTime: Int
        public let templateCategoryID: Int?
        public let name: String?, description: String?, address: String?, longitude: String?, latitude: String?, imageReference: String?
        public let templateTitle: String?, templateCategoryIDs: String?, templateContentHash: String, questionText: String?, ruleInstructions: String?
        public let answerPresent: Bool
    }
    public struct Block: Equatable, Sendable {
        public let type: String, key: String?, content: String?, node: Node?
    }
    public struct Chapter: Equatable, Sendable {
        public let id: Int, name: String?, description: String?, blocks: [Block]
    }
    public let topicID: Int, observedAuditTaskID: Int, observedAuditTaskVersion: Int, sourceConfigVersion: Int
    public let snapshotHash: String
    public let name: String?, description: String?, categoryIDs: String?, coverReference: String?
    public let chapters: [Chapter]
    public let selectedCover: ApprovedTopicSelectedCover?
    public var coverBindingAllowsReview: Bool { selectedCover?.permitsReviewRequest ?? true }
    /// Exact validated safe summary bytes as structured fields, retained for durable confirmation recovery.
    private let identityBytes: Data
    func serializedFields() throws -> ProjectEditJSON { try JSONDecoder().decode(ProjectEditJSON.self, from: identityBytes) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identityBytes == rhs.identityBytes }

    public static func decode(_ value: ProjectEditJSON, topicID: Int, observedAuditTaskID: Int) throws -> Self {
        guard let root = value.object,
              Set(root.keys) == ["topicId", "observedAuditTaskId", "observedAuditTaskVersion", "sourceConfigVersion", "snapshotHash", "contract", "approvalProof", "releaseAllocated", "summary"],
              root["contract"]?.text == "questify.topic-release.review-preparation.v1",
              root["approvalProof"] == .bool(false), root["releaseAllocated"] == .bool(false),
              root["topicId"]?.integer == topicID, topicID > 0,
              root["observedAuditTaskId"]?.integer == observedAuditTaskID, observedAuditTaskID > 0,
              let version = root["observedAuditTaskVersion"]?.integer, version >= 0, version <= Int(Int32.max),
              let sourceVersion = root["sourceConfigVersion"]?.integer, sourceVersion >= 0,
              let hash = root["snapshotHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash),
              let summary = root["summary"]?.object,
              Set(summary.keys).isSubset(of: ["name", "description", "categoryIds", "coverReference", "productType", "publishMode", "secretValuesExcluded", "publicationEligibilityChecked", "chapters", "selectedCover"]),
              summary["productType"]?.integer == ProjectEditProduct.city.rawValue, summary["publishMode"]?.text == "pro",
              summary["secretValuesExcluded"] == .bool(true), summary["publicationEligibilityChecked"] == .bool(false),
              let rows = summary["chapters"]?.array, !rows.isEmpty, rows.count <= 200 else { throw ApprovedTopicReleaseError.invalidResponse }
        var chapterIDs = Set<Int>(), nodeIDs = Set<Int>()
        let chapters = try rows.map { value -> Chapter in
            guard let chapter = value.object, Set(chapter.keys).isSubset(of: ["id", "name", "description", "blocks"]),
                  let id = chapter["id"]?.integer, id > 0, chapterIDs.insert(id).inserted,
                  let rows = chapter["blocks"]?.array, !rows.isEmpty, rows.count <= 200 else { throw ApprovedTopicReleaseError.invalidResponse }
            let blocks = try rows.map { value -> Block in
                guard let block = value.object, Set(block.keys).isSubset(of: ["type", "key", "content", "node"]),
                      let type = block["type"]?.text, type == "text" || type == "node" else { throw ApprovedTopicReleaseError.invalidResponse }
                let node: Node?
                if type == "node" {
                    guard let row = block["node"]?.object,
                          Set(row.keys).isSubset(of: ["id", "templateId", "nodeTime", "templateCategoryId", "name", "description", "address", "longitude", "latitude", "imageReference", "templateTitle", "templateCategoryIds", "templateContentHash", "questionText", "ruleInstructions", "answerPresent"]),
                          let id = row["id"]?.integer, id > 0, nodeIDs.insert(id).inserted,
                          let template = row["templateId"]?.integer, template > 0,
                          let time = row["nodeTime"]?.integer, time >= 0,
                          let contentHash = row["templateContentHash"]?.text, contentHash.hasPrefix("sha256:"), ApprovedTopicReleasePreparation.validHash(String(contentHash.dropFirst(7))),
                          case .bool(let hasAnswer)? = row["answerPresent"] else { throw ApprovedTopicReleaseError.invalidResponse }
                    node = try .init(id: id, templateID: template, nodeTime: time, templateCategoryID: optionalInteger(row, "templateCategoryId"),
                        name: optionalText(row, "name"), description: optionalText(row, "description"), address: optionalText(row, "address"),
                        longitude: optionalText(row, "longitude"), latitude: optionalText(row, "latitude"), imageReference: optionalText(row, "imageReference"),
                        templateTitle: optionalText(row, "templateTitle"), templateCategoryIDs: optionalText(row, "templateCategoryIds"), templateContentHash: contentHash,
                        questionText: optionalText(row, "questionText"), ruleInstructions: optionalText(row, "ruleInstructions"), answerPresent: hasAnswer)
                } else {
                    guard block["node"] == nil || block["node"] == .null else { throw ApprovedTopicReleaseError.invalidResponse }; node = nil
                }
                return try .init(type: type, key: optionalText(block, "key"), content: optionalText(block, "content"), node: node)
            }
            // The current-review projection permits text-only chapters. Publication eligibility is a separate server check.
            return try .init(id: id, name: optionalText(chapter, "name"), description: optionalText(chapter, "description"), blocks: blocks)
        }
        let selectedCover: ApprovedTopicSelectedCover?
        if let value = summary["selectedCover"], value != .null {
            selectedCover = try .decode(value, topicID: topicID, sourceConfigVersion: sourceVersion, legacyReference: optionalText(summary, "coverReference"))
        } else { selectedCover = nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let identityBytes = try encoder.encode(value)
        guard identityBytes.count <= 4 * 1024 * 1024 else { throw ApprovedTopicReleaseError.invalidResponse }
        return try .init(topicID: topicID, observedAuditTaskID: observedAuditTaskID, observedAuditTaskVersion: version, sourceConfigVersion: sourceVersion,
            snapshotHash: hash, name: optionalText(summary, "name"), description: optionalText(summary, "description"), categoryIDs: optionalText(summary, "categoryIds"), coverReference: optionalText(summary, "coverReference"), chapters: chapters, selectedCover: selectedCover, identityBytes: identityBytes)
    }
    private static func optionalText(_ row: [String: ProjectEditJSON], _ key: String) throws -> String? {
        guard let value = row[key], value != .null else { return nil }; guard let text = value.text else { throw ApprovedTopicReleaseError.invalidResponse }; return text
    }
    private static func optionalInteger(_ row: [String: ProjectEditJSON], _ key: String) throws -> Int? {
        guard let value = row[key], value != .null else { return nil }; guard let integer = value.integer, integer >= 0 else { throw ApprovedTopicReleaseError.invalidResponse }; return integer
    }
}

public struct ApprovedTopicReviewCommand: Equatable, Sendable {
    public let topicID: Int, observedAuditTaskID: Int, observedAuditTaskVersion: Int, sourceConfigVersion: Int
    public let snapshotHash: String, requestID: String
    public init(capture: ApprovedTopicReviewCapture, requestID: UUID = UUID()) {
        topicID = capture.topicID; observedAuditTaskID = capture.observedAuditTaskID; observedAuditTaskVersion = capture.observedAuditTaskVersion
        sourceConfigVersion = capture.sourceConfigVersion; snapshotHash = capture.snapshotHash; self.requestID = requestID.uuidString
    }
    public var fields: [String: ProjectEditJSON] {
        ["topicId": .number(Decimal(topicID)), "observedAuditTaskId": .number(Decimal(observedAuditTaskID)), "observedAuditTaskVersion": .number(Decimal(observedAuditTaskVersion)),
         "sourceConfigVersion": .number(Decimal(sourceConfigVersion)), "snapshotHash": .string(snapshotHash), "requestId": .string(requestID)]
    }
    static func decode(_ value: ProjectEditJSON, capture: ApprovedTopicReviewCapture) throws -> Self {
        guard let row = value.object, let key = row["requestId"]?.text, let id = UUID(uuidString: key), id.uuidString == key else { throw ApprovedTopicReleaseError.invalidResponse }
        let expected = Self(capture: capture, requestID: id); guard row == expected.fields else { throw ApprovedTopicReleaseError.invalidResponse }; return expected
    }
}

/// Historical submission fact. Approval, current task state and any release require independent reads.
public struct ApprovedTopicReviewReceipt: Equatable, Sendable {
    public let topicID: Int, auditTaskID: Int, submittedTaskVersion: Int, submittedTaskStatus: Int, sourceConfigVersion: Int
    public let snapshotHash: String, requestID: String
    public static func decode(_ value: ProjectEditJSON, command: ApprovedTopicReviewCommand) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["topicId", "auditTaskId", "sourceConfigVersion", "submittedTaskVersion", "submittedTaskStatus", "snapshotHash", "requestId", "approvalProof", "releaseAllocated"],
              row["topicId"]?.integer == command.topicID, let task = row["auditTaskId"]?.integer, task > 0,
              let version = row["submittedTaskVersion"]?.integer, version >= 0, version <= Int(Int32.max),
              let state = row["submittedTaskStatus"]?.integer, state == 0 || state == 3,
              row["sourceConfigVersion"]?.integer == command.sourceConfigVersion,
              row["snapshotHash"]?.text == command.snapshotHash, row["requestId"]?.text == command.requestID,
              row["approvalProof"] == .bool(false), row["releaseAllocated"] == .bool(false) else { throw ApprovedTopicReleaseError.invalidResponse }
        if task == command.observedAuditTaskID {
            guard command.observedAuditTaskVersion < Int(Int32.max), version == command.observedAuditTaskVersion + 1 else { throw ApprovedTopicReleaseError.invalidResponse }
        } else {
            guard version == 0, state == 0 else { throw ApprovedTopicReleaseError.invalidResponse }
        }
        return .init(topicID: command.topicID, auditTaskID: task, submittedTaskVersion: version, submittedTaskStatus: state, sourceConfigVersion: command.sourceConfigVersion, snapshotHash: command.snapshotHash, requestID: command.requestID)
    }
    var fields: ProjectEditJSON {
        .object(["topicId": .number(Decimal(topicID)), "auditTaskId": .number(Decimal(auditTaskID)), "sourceConfigVersion": .number(Decimal(sourceConfigVersion)),
                 "submittedTaskVersion": .number(Decimal(submittedTaskVersion)), "submittedTaskStatus": .number(Decimal(submittedTaskStatus)),
                 "snapshotHash": .string(snapshotHash), "requestId": .string(requestID), "approvalProof": .bool(false), "releaseAllocated": .bool(false)])
    }
}
