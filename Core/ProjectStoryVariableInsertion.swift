import Foundation

/// Appends a source-declared profile token to one existing plain-text block.
/// Template snapshots are read locally; no configuration is copied into the story.
public struct ProjectStoryVariableInsertion {
    public enum Reason: String, Error { case identity, declarations, unsupported }
    public struct Variable: Identifiable {
        public let key: String
        public let label: String
        public var id: Data { Data(key.utf8) }
        public var token: String { "{" + key + "}" }
    }
    public let chapterID: String, blockID: String
    public private(set) var reason: Reason?
    public private(set) var variables: [Variable] = []
    private var bytes: Data?
    private var chapterIndex = 0, blockIndex = 0
    private var contentLength = 0

    public init(draft: ProjectEditDraft, chapterID: String, blockID: String) {
        self.chapterID = chapterID; self.blockID = blockID
        // Also reject canonical aliases that SwiftUI's existing String identity
        // could collapse, but never use canonical equality to select a target.
        let matches = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !blockID.isEmpty, matches.count == 1, let ci = matches.first,
              Self.exact(draft.chapters[ci].id, chapterID),
              draft.chapters.flatMap({ $0.blocks ?? [] }).filter({ $0.id == blockID }).count == 1,
              let blocks = draft.chapters[ci].blocks,
              let bi = blocks.firstIndex(where: { Self.exact($0.id, blockID) }),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { reason = .identity; return }
        let block = blocks[bi]
        guard draft.chapters[ci].schemaVersion == 1, block.kind == .text, block.nodeID.isEmpty,
              block.sourceFields?["beat"] == nil || block.sourceFields?["beat"] == .string(""),
              !block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              block.content.utf16.count <= 5000,
              draft.chapters.count <= 128, draft.chapters.flatMap(\.nodes).count <= 512 else { reason = .unsupported; return }
        self.bytes = bytes; chapterIndex = ci; blockIndex = bi; contentLength = block.content.utf16.count
        do { variables = try Self.declarations(draft) }
        catch { reason = .declarations }
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func canAppend(_ key: String) -> Bool {
        reason == nil && variables.contains { Self.exact($0.key, key) && contentLength + $0.token.utf16.count <= 5000 }
    }
    public func applying(appending key: String?, to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard let key else { return draft }
        guard canAppend(key), let variable = variables.first(where: { Self.exact($0.key, key) }),
              var blocks = draft.chapters[chapterIndex].blocks else { throw ProjectEditError.invalidDraft }
        // The native field does not capture a text cursor. This is exactly the
        // mini helper's no-cursor fallback, explicitly labelled as append in UI.
        blocks[blockIndex].content += variable.token
        var next = draft; next.chapters[chapterIndex].blocks = blocks; return next
    }
    private static func exact(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    private static func declarations(_ draft: ProjectEditDraft) throws -> [Variable] {
        var result: [Variable] = [], seen = Set<Data>(), configBytes = 0
        for node in draft.chapters.flatMap(\.nodes) {
            guard let templateID = node.templateID else {
                guard node.localMetadata["templateInfo"] == nil else { throw Reason.declarations }; continue
            }
            guard templateID > 0, let info = node.localMetadata["templateInfo"]?.object,
                  info["id"]?.integer == templateID else { throw Reason.declarations }
            guard let raw = info["advancedConfigJson"], raw != .null, raw != .string("") else { continue }
            // Object-form values have already lost raw duplicate-key provenance.
            // Only the original string snapshot can establish exact declarations.
            guard let text = raw.text, text.utf8.count <= 262_144 else { throw Reason.declarations }
            configBytes += text.utf8.count
            guard configBytes <= 1_048_576,
                  case .object(let root) = try ContentDraftJSON.parse(text),
                  root[Data("schemaVersion".utf8)] == .number(negative: false, digits: "1", exponent: 0) else { throw Reason.declarations }
            guard let rawProfile = root[Data("profile".utf8)], rawProfile != .null else { continue }
            guard case .object(let profile) = rawProfile else { throw Reason.declarations }
            let enabled = profile[Data("enabled".utf8)]
            guard enabled == nil || enabled == .bool(false) || enabled == .bool(true) else { throw Reason.declarations }
            guard enabled == .bool(true) else { continue }
            guard case .array(let questions)? = profile[Data("questions".utf8)], (1...8).contains(questions.count) else { throw Reason.declarations }
            for rawQuestion in questions {
                guard case .object(let question) = rawQuestion,
                      case .string(let keyBytes)? = question[Data("key".utf8)],
                      let key = String(data: keyBytes, encoding: .utf8), validKey(keyBytes),
                      case .string(let labelBytes)? = question[Data("label".utf8)],
                      let label = String(data: labelBytes, encoding: .utf8),
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.utf16.count <= 40,
                      seen.insert(keyBytes).inserted else { throw Reason.declarations }
                result.append(.init(key: key, label: label))
                guard result.count <= 128 else { throw Reason.declarations }
            }
        }
        return result
    }
    private static func validKey(_ key: Data) -> Bool {
        let bytes = Array(key)
        func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
        return (1...16).contains(bytes.count) && letter(bytes[0]) && bytes.allSatisfy { letter($0) || (48...57).contains($0) || $0 == 95 }
    }
}
