import Foundation

public enum ProjectStoryTemplateError: Error, Equatable {
    case notConfigured, invalidResponse, changedContext, sourceChanged, unsupported
}

/// A member-template identity read from the personal draft shelf. It conveys no adoption,
/// publication, market, or merchant authority. Only the explicit local apply action adopts it.
public struct ProjectStoryTemplateRow: Equatable, Identifiable {
    public let id: MemberPlayTemplateID
    public let accountID: Int
    public let title: String
    static func decode(_ value: ProjectEditJSON, accountID: Int) throws -> Self {
        guard let fields = value.object, accountID > 0,
              let raw = fields["id"]?.integer, let id = MemberPlayTemplateID(rawValue: raw),
              fields["memberId"]?.integer == accountID, fields["draftStatus"] == .number(0),
              fields["delFlag"] == nil || fields["delFlag"] == .number(0),
              let title = fields["title"]?.text, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf16.count <= 512 else { throw ProjectStoryTemplateError.invalidResponse }
        return .init(id: id, accountID: accountID, title: title)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.accountID == rhs.accountID && lhs.title.utf8.elementsEqual(rhs.title.utf8)
    }
}
public struct ProjectStoryTemplatePage: Equatable {
    public static let pageSize = 20, maximumPages = 50
    public let rows: [ProjectStoryTemplateRow]
    public let nextPage: Int?
    public static func decode(_ value: ProjectEditJSON, accountID: Int, page: Int) throws -> Self {
        guard (1...maximumPages).contains(page), let fields = value.object,
              let raw = fields["rows"]?.array, raw.count <= pageSize,
              let total = fields["total"]?.integer, total >= 0, total >= (page - 1) * pageSize + raw.count,
              raw.count == pageSize || total == (page - 1) * pageSize + raw.count else { throw ProjectStoryTemplateError.invalidResponse }
        let rows = try raw.map { try ProjectStoryTemplateRow.decode($0, accountID: accountID) }
        guard Set(rows.map { $0.id.rawValue }).count == rows.count else { throw ProjectStoryTemplateError.invalidResponse }
        return .init(rows: rows, nextPage: page < maximumPages && page * pageSize < total ? page + 1 : nil)
    }
}

/// Immutable, owner-checked review projection. Secrets/configuration remain in the source;
/// only a reference or the validated album display fields can enter a local story.
public struct ProjectStoryTemplateDraft: Equatable {
    public enum Content: Equatable { case gameplay, album([ProjectEditJSON]) }
    public let row: ProjectStoryTemplateRow
    public let content: Content
    private let exactSource: Data
    public static func decode(_ value: ProjectEditJSON, accountID: Int, requestedID: MemberPlayTemplateID) throws -> Self {
        let row = try ProjectStoryTemplateRow.decode(value, accountID: accountID)
        guard row.id == requestedID, let fields = value.object, fields["delFlag"] == .number(0),
              let exact = ProjectEditPendingMaterials.exactData(value) else { throw ProjectStoryTemplateError.invalidResponse }
        let content: Content
        switch fields["advancedConfigJson"] {
        case nil, .null?, .string("")?: content = .gameplay
        case .string(let raw)?:
            guard raw.utf8.count <= 262_144,
                  // This string is a second JSON document. The outer response parser cannot
                  // see duplicate or escaped-alias keys inside it. Reuse the bounded
                  // grammar/duplicate-key preflight before either Foundation decoder.
                  let config = try? ApprovedTopicReleaseWire.envelope(Data(raw.utf8)),
                  config["schemaVersion"] == .number(1) else { throw ProjectStoryTemplateError.unsupported }
            // Retain the existing advanced-schema validator rather than inventing defaults or
            // treating an unknown/malformed album as ordinary gameplay.
            guard var advanced = try? TemplateAdvancedDraft(raw: raw) else { throw ProjectStoryTemplateError.unsupported }
            // The source permits a nullable optional caption. Only the validation copy
            // drops null captions; the adopted image array remains byte-exact.
            if var album = advanced.value["album"]?.object, let images = album["images"]?.array {
                album["images"] = .array(images.map { image in
                    guard var fields = image.object, fields["line"] == .null else { return image }
                    fields.removeValue(forKey: "line"); return .object(fields)
                })
                advanced.value["album"] = .object(album)
            }
            guard advanced.issues.isEmpty else { throw ProjectStoryTemplateError.unsupported }
            if let album = config["album"] {
                guard let album = album.object, Set(album.keys).isSubset(of: ["enabled", "images"]),
                      let enabled = album["enabled"], enabled == .bool(true) || enabled == .bool(false) else { throw ProjectStoryTemplateError.unsupported }
                if enabled == .bool(true) {
                    guard !advanced.hasRootAuthoringConfiguration,
                          !config.contains(where: { $0.key != "album" && $0.value.object?["enabled"] == .bool(true) }) else { throw ProjectStoryTemplateError.unsupported }
                    for (key, value) in config where key != "schemaVersion" && key != "present" && key != "album" {
                        guard let fields = value.object, fields["enabled"] == .bool(false) else { throw ProjectStoryTemplateError.unsupported }
                    }
                    guard Set(album.keys).isSubset(of: ["enabled", "images"]), let images = album["images"]?.array,
                          (1...6).contains(images.count), row.title.utf16.count <= 20 else { throw ProjectStoryTemplateError.unsupported }
                    for rawImage in images {
                        guard let image = rawImage.object, Set(image.keys).isSubset(of: ["url", "line"]),
                              let url = image["url"]?.text, url.utf16.count <= 500,
                              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectStoryTemplateError.unsupported }
                        if let line = image["line"], line != .null { guard let line = line.text, line.utf16.count <= 40 else { throw ProjectStoryTemplateError.unsupported } }
                    }
                    try ProjectEditRichStoryContract.validateShape(["type": .string("dream"), "title": .string(row.title), "images": .array(images)], kind: .dream)
                    content = .album(images)
                } else { content = .gameplay }
            } else { content = .gameplay }
        default: throw ProjectStoryTemplateError.unsupported
        }
        if case .gameplay = content {
            guard let method = fields["validationMethod"]?.integer, [0, 1, 2, 3, 6, 7].contains(method) else { throw ProjectStoryTemplateError.unsupported }
        }
        return .init(row: row, content: content, exactSource: exact)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.exactSource == rhs.exactSource && lhs.row == rhs.row }
}

/// Captures an existing stable gap. Reuses the media gap's whole-draft equality and
/// owner/bucket fences; live ABA is additionally guarded by the editor's monotonic revision.
public struct ProjectStoryTemplateTarget: Equatable {
    public let gap: ProjectStoryMediaGap
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, before blockID: String?) throws {
        guard draft.product == .city, draft.owner == .personal,
              let index = draft.chapters.firstIndex(where: { $0.id == chapterID }) else { throw ProjectStoryTemplateError.changedContext }
        let chapter = draft.chapters[index]
        guard chapter.schemaVersion == 1, chapter.required == 1,
              chapter.preserved["opening"] == nil || chapter.preserved["opening"] == .null || chapter.preserved["opening"] == .bool(false) || chapter.preserved["opening"] == .bool(true),
              chapter.preserved["opening"] != .bool(true) || (index == 0 && chapter.preserved["recruitEnabled"]?.integer != 1) else { throw ProjectStoryTemplateError.unsupported }
        if let ending = chapter.preserved["ending"], ending != .null {
            guard let fields = ending.object, Set(fields.keys).isSubset(of: ["fallback", "when"]),
                  chapter.preserved["opening"] != .bool(true), chapter.nodes.isEmpty,
                  chapter.preserved["recruitEnabled"]?.integer != 1 else { throw ProjectStoryTemplateError.unsupported }
            if fields["fallback"] != .bool(true) {
                guard fields["fallback"] == nil || fields["fallback"] == .null || fields["fallback"] == .bool(false),
                      let conditions = fields["when"]?.array, !conditions.isEmpty, conditions.count <= 16 else { throw ProjectStoryTemplateError.unsupported }
                for condition in conditions { try ProjectEditRichStoryContract.validateCondition(condition, ending: true) }
            }
        }
        let blockIDs = draft.chapters.flatMap { ($0.blocks ?? []).map(\.id) }
        guard Set(blockIDs).count == blockIDs.count else { throw ProjectStoryTemplateError.changedContext }
        let nodeIDs = draft.chapters.flatMap { $0.nodes.map(\.id) }
        guard nodeIDs.allSatisfy({ !$0.isEmpty }), Set(nodeIDs).count == nodeIDs.count,
              Set(draft.chapters.map(\.id)).count == draft.chapters.count else { throw ProjectStoryTemplateError.changedContext }
        let references = (chapter.blocks ?? []).filter { $0.kind == .node }.map(\.nodeID)
        guard Set(references).count == references.count, Set(references) == Set(chapter.nodes.map(\.id)) else { throw ProjectStoryTemplateError.changedContext }
        if chapter.preserved["opening"] == .bool(true) {
            guard (chapter.blocks ?? []).filter({ $0.kind == .node }).allSatisfy({ $0.sourceFields?["locationRequired"] == .bool(false) }),
                  chapter.nodes.allSatisfy({ $0.longitude.isEmpty && $0.latitude.isEmpty && ($0.templateID ?? 0) > 0 }) else { throw ProjectStoryTemplateError.unsupported }
        }
        gap = try .init(draft: draft, identity: identity, session: session, chapterID: chapterID, before: blockID)
    }
    public func applying(_ selected: ProjectStoryTemplateDraft, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard selected.row.accountID == session.accountID,
              try Self(draft: draft, identity: identity, session: session, chapterID: gap.chapterID, before: gap.beforeBlockID) == self else { throw ProjectStoryTemplateError.changedContext }
        let block: ProjectEditBlock
        var node: ProjectEditNode?
        switch selected.content {
        case .gameplay:
            guard let chapter = draft.chapters.first(where: { $0.id == gap.chapterID }),
                  chapter.preserved["ending"] == nil || chapter.preserved["ending"] == .null else { throw ProjectStoryTemplateError.unsupported }
            var created = ProjectEditNode(); created.name = selected.row.title; created.templateID = selected.row.id.rawValue
            created.longitude = ""; created.latitude = ""; node = created
            var value = ProjectEditBlock(kind: .node, nodeID: created.id)
            value.sourceFields = ["locationRequired": .bool(false)]; block = value
        case .album(let images):
            var value = ProjectEditBlock(kind: .dream)
            value.sourceFields = ["title": .string(selected.row.title), "images": .array(images)]; block = value
        }
        var next = try gap.inserting(block, into: draft, identity: identity, session: session)
        guard let index = next.chapters.firstIndex(where: { $0.id == gap.chapterID }) else { throw ProjectStoryTemplateError.changedContext }
        if let node {
            guard !next.chapters.flatMap({ $0.nodes }).contains(where: { $0.id == node.id }) else { throw ProjectStoryTemplateError.changedContext }
            next.chapters[index].nodes.append(node)
        }
        // pendingMaterials are never consumed, promoted, or rewritten by this selection.
        return next
    }
}
