import Foundation

public enum ApprovedTopicReleasePaths {
    public static let prepare = "api/approved-topic-release/v1/prepare"
}

/// A server-approved, captured summary. It is neither a local draft nor an allocated release.
public struct ApprovedTopicReleasePreparation: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public let id: Int
        public let templateID: Int
        public let nodeTime: Int
        public let name: String?
        public let description: String?
        public let address: String?
        public let longitude: String?
        public let latitude: String?
        public let imageReference: String?
        public let templateTitle: String?
        /// Actual cms_member_template.categoryId, distinct from activityCategoryids.
        public let templateCategoryID: Int?
        public let templateCategoryIDs: String?
        public let templateContentHash: String
        public let questionText: String?
        public let ruleInstructions: String?
        public let answerPresent: Bool
    }
    public struct Block: Equatable, Sendable {
        public let key: String?
        public let content: String?
        public let node: Node?
        public var isNode: Bool { node != nil }
    }
    public struct Chapter: Equatable, Sendable {
        public let id: Int
        public let name: String?
        public let description: String?
        public let blocks: [Block]
    }
    public let contract: String
    public let topicID: Int
    public let auditTaskID: Int
    public let auditTaskVersion: Int
    public let auditSnapshotHash: String
    public let manifestHash: String
    public let headRevision: Int
    public let sourceConfigVersion: Int
    public let name: String?
    public let description: String?
    public let categoryIDs: String?
    public let chapters: [Chapter]
    public let selectedCover: ApprovedTopicSelectedCover?

    public static let textCityContract = "questify.topic-release.text-city.v1"
    public static func decode(_ body: ProjectEditJSON, topicID: Int, auditTaskID: Int) throws -> Self {
        guard let root = body.object,
              Set(root.keys).isSubset(of: ["contract", "topicId", "auditTaskId", "auditTaskVersion", "auditSnapshotHash", "manifestHash", "headRevision", "sourceConfigVersion", "name", "description", "currentlyApproved", "releaseAllocated", "secretValuesExcluded", "chapters", "categoryIds", "selectedCover"]),
              root["contract"]?.text == textCityContract, root["topicId"]?.integer == topicID, topicID > 0,
              root["auditTaskId"]?.integer == auditTaskID, auditTaskID > 0,
              let version = root["auditTaskVersion"]?.integer, version >= 0,
              let auditHash = root["auditSnapshotHash"]?.text, validHash(auditHash),
              let manifestHash = root["manifestHash"]?.text, validHash(manifestHash),
              let head = root["headRevision"]?.integer, head >= 0,
              let source = root["sourceConfigVersion"]?.integer, source >= 0,
              root["currentlyApproved"] == .bool(true), root["releaseAllocated"] == .bool(false),
              root["secretValuesExcluded"] == .bool(true), let chapterRows = root["chapters"]?.array,
              !chapterRows.isEmpty, chapterRows.count <= 200 else { throw ApprovedTopicReleaseError.invalidResponse }
        var chapterIDs = Set<Int>(), nodeIDs = Set<Int>()
        let chapters = try chapterRows.map { value -> Chapter in
            guard let row = value.object, Set(row.keys).isSubset(of: ["id", "name", "description", "blocks"]),
                  let id = row["id"]?.integer, id > 0, chapterIDs.insert(id).inserted,
                  let blockRows = row["blocks"]?.array, !blockRows.isEmpty, blockRows.count <= 200 else { throw ApprovedTopicReleaseError.invalidResponse }
            let blocks = try blockRows.map { value -> Block in
                guard let block = value.object, Set(block.keys).isSubset(of: ["type", "key", "content", "node"]),
                      let kind = block["type"]?.text, kind == "text" || kind == "node" else { throw ApprovedTopicReleaseError.invalidResponse }
                let node: Node?
                if kind == "node" {
                    guard let source = block["node"]?.object,
                          Set(source.keys).isSubset(of: ["id", "templateId", "nodeTime", "name", "description", "address", "longitude", "latitude", "imgUrl", "templateTitle", "templateCategoryId", "templateCategoryIds", "templateContentHash", "questionText", "ruleInstructions", "answerPresent"]),
                          let id = source["id"]?.integer, id > 0, nodeIDs.insert(id).inserted,
                          let template = source["templateId"]?.integer, template > 0,
                          let time = source["nodeTime"]?.integer, time >= 0,
                          let hash = source["templateContentHash"]?.text, hash.hasPrefix("sha256:"), validHash(String(hash.dropFirst(7))),
                          source["answerPresent"] == .bool(true) else { throw ApprovedTopicReleaseError.invalidResponse }
                    let image = try optionalText(source, "imgUrl")
                    // Node media remains unavailable. The independent frozen topic-cover
                    // profile is decoded explicitly below; it never authorizes a node URL.
                    guard image == nil || image == "" else { throw ApprovedTopicReleaseError.invalidResponse }
                    node = try .init(id: id, templateID: template, nodeTime: time,
                        name: optionalText(source, "name"), description: optionalText(source, "description"),
                        address: optionalText(source, "address"), longitude: optionalText(source, "longitude"), latitude: optionalText(source, "latitude"),
                        imageReference: image, templateTitle: optionalText(source, "templateTitle"), templateCategoryID: optionalNonnegativeInteger(source, "templateCategoryId"), templateCategoryIDs: optionalText(source, "templateCategoryIds"), templateContentHash: hash,
                        questionText: optionalText(source, "questionText"), ruleInstructions: optionalText(source, "ruleInstructions"), answerPresent: true)
                } else {
                    guard block["node"] == nil || block["node"] == .null else { throw ApprovedTopicReleaseError.invalidResponse }
                    node = nil
                }
                return try .init(key: optionalText(block, "key"), content: optionalText(block, "content"), node: node)
            }
            guard blocks.contains(where: \.isNode) else { throw ApprovedTopicReleaseError.invalidResponse }
            return try .init(id: id, name: optionalText(row, "name"), description: optionalText(row, "description"), blocks: blocks)
        }
        let selectedCover: ApprovedTopicSelectedCover?
        if let value = root["selectedCover"], value != .null {
            guard let proof = value.object else { throw ApprovedTopicReleaseError.invalidResponse }
            selectedCover = try .decode(value, topicID: topicID, sourceConfigVersion: source, legacyReference: optionalText(proof, "legacyTopicImageReference"))
            guard selectedCover?.permitsReviewRequest == true else { throw ApprovedTopicReleaseError.invalidResponse }
        } else { selectedCover = nil }
        return try .init(contract: textCityContract, topicID: topicID, auditTaskID: auditTaskID, auditTaskVersion: version,
            auditSnapshotHash: auditHash, manifestHash: manifestHash, headRevision: head, sourceConfigVersion: source,
            name: optionalText(root, "name"), description: optionalText(root, "description"), categoryIDs: optionalText(root, "categoryIds"), chapters: chapters, selectedCover: selectedCover)
    }
    static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func optionalNonnegativeInteger(_ row: [String: ProjectEditJSON], _ key: String) throws -> Int? {
        guard let value = row[key], value != .null else { return nil }
        guard let number = value.integer, number >= 0 else { throw ApprovedTopicReleaseError.invalidResponse }; return number
    }
    private static func optionalText(_ row: [String: ProjectEditJSON], _ key: String) throws -> String? {
        guard let value = row[key], value != .null else { return nil }
        guard let text = value.text else { throw ApprovedTopicReleaseError.invalidResponse }; return text
    }
}

public enum ApprovedTopicReleaseError: Error, Equatable {
    case notConfigured, changedContext, invalidResponse, unavailable, changedReview, forbidden, persistenceUnavailable
}

/// Resource preflight before Foundation constructs the response tree. This is not
/// a replacement JSON parser: Foundation still validates UTF-8 and the full grammar.
public enum ApprovedTopicReleaseWire {
    public static func envelope(_ data: Data) throws -> [String: ProjectEditJSON] {
        guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else { throw ApprovedTopicReleaseError.invalidResponse }
        var depth = 0, tokens = 0, stringBytes = 0, atomBytes = 0
        var quoted = false, escaped = false
        for byte in data {
            if quoted {
                stringBytes += 1
                guard stringBytes <= 96 * 1024 else { throw ApprovedTopicReleaseError.invalidResponse }
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else {
                switch byte {
                case 34: quoted = true; stringBytes = 0; atomBytes = 0; tokens += 1
                case 91, 123: depth += 1; atomBytes = 0; tokens += 1
                case 93, 125: depth -= 1; atomBytes = 0; tokens += 1
                case 44, 58: atomBytes = 0; tokens += 1
                case 9, 10, 13, 32: atomBytes = 0
                default: atomBytes += 1
                }
                guard depth >= 0, depth <= 32, tokens <= 100_000, atomBytes <= 128 else { throw ApprovedTopicReleaseError.invalidResponse }
            }
        }
        guard !quoted, depth == 0 else { throw ApprovedTopicReleaseError.invalidResponse }
        do {
            guard let text = String(data: data, encoding: .utf8) else { throw ApprovedTopicReleaseError.invalidResponse }
            // Reuse the existing lossless duplicate-key/grammar validator after the
            // shallower resource preflight; escaped aliases cannot create two identities.
            _ = try ContentDraftJSON.parse(text)
            return try JSONDecoder().decode([String: ProjectEditJSON].self, from: data)
        }
        catch { throw ApprovedTopicReleaseError.invalidResponse }
    }
}
