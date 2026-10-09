import Foundation
import CryptoKit

/// Captures the real local draft and original chapter order. No server identity/version is invented.
public struct ProjectStoryImageTarget: Codable, Equatable {
    public enum Action: Codable, Equatable { case append, replace(String), insertBefore(String), appendAlbumImage(Data) }
    public let id: UUID
    public let ownerKey: String
    public let draftBucket: String
    public let chapterID: String
    public let originalDraftHash: String
    public let action: Action
    public let resultingBlockID: String
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, replacing blockID: String? = nil, insertingBefore anchorID: String? = nil,
                appendingToAlbum albumID: String? = nil, id: UUID = UUID()) throws {
        guard [blockID, anchorID, albumID].compactMap({ $0 }).count <= 1,
              draft.chapters.filter({ $0.id == chapterID }).count == 1,
              let chapter = draft.chapters.first(where: { $0.id == chapterID }), let blocks = chapter.blocks,
              Set(blocks.map(\.id)).count == blocks.count,
              ProjectEditStarterPolicy.usesStoryEditor(product: draft.product, chapter: chapter),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryImageFailure.changedContext }
        let action: Action
        if let albumID {
            _ = try Self.album(draft, chapterID: chapterID, blockID: Data(albumID.utf8), maximum: 5)
            action = .appendAlbumImage(Data(albumID.utf8))
        } else if let anchorID {
            _ = try ProjectStoryMediaGap(draft: draft, identity: identity, session: session, chapterID: chapterID, before: anchorID)
            action = .insertBefore(anchorID)
        } else if let blockID {
            guard blocks.contains(where: { $0.id == blockID && $0.kind == .image }) else { throw ProjectStoryImageFailure.changedContext }
            action = .replace(blockID)
        } else {
            guard blocks.count < 200 else { throw ProjectStoryImageFailure.changedContext }
            action = .append
        }
        self.id = id; ownerKey = session.ownerKey; draftBucket = identity.bucket; self.chapterID = chapterID
        originalDraftHash = Self.hash(bytes); self.action = action; resultingBlockID = albumID ?? blockID ?? id.uuidString
    }
    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public func matches(_ draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        guard ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { return false }
        if isAlbumAppend {
            guard ownerKey.utf8.elementsEqual(session.ownerKey.utf8), draftBucket.utf8.elementsEqual(identity.bucket.utf8) else { return false }
        }
        return Self.hash(bytes) == originalDraftHash
    }
    public func applying(_ receipt: ProjectStoryUploadedImage, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard receipt.ownerKey == ownerKey, receipt.reference.utf16.count <= 500, matches(draft, identity: identity, session: session),
              let ci = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              var blocks = draft.chapters[ci].blocks else { throw ProjectStoryImageFailure.changedContext }
        switch action {
        case .appendAlbumImage(let albumID):
            let location = try Self.album(draft, chapterID: chapterID, blockID: albumID, maximum: 5)
            guard receipt.ownerKey.utf8.elementsEqual(ownerKey.utf8), Data(resultingBlockID.utf8) == albumID else { throw ProjectStoryImageFailure.changedContext }
            var next = draft
            next.chapters[location.chapter].blocks?[location.block].sourceFields?["images"] =
                .array(location.images + [.object(["url": .string(receipt.reference), "line": .string("")])])
            return next
        case .append:
            guard blocks.count < 200, !blocks.contains(where: { $0.id == resultingBlockID }) else { throw ProjectStoryImageFailure.changedContext }
            var image = ProjectEditBlock(kind: .image, url: receipt.reference); image.id = resultingBlockID
            blocks.append(image)
        case .insertBefore(let anchorID):
            let gap = try ProjectStoryMediaGap(draft: draft, identity: identity, session: session, chapterID: chapterID, before: anchorID)
            var image = ProjectEditBlock(kind: .image, url: receipt.reference); image.id = resultingBlockID
            return try gap.inserting(image, into: draft, identity: identity, session: session)
        case .replace(let blockID):
            guard let bi = blocks.firstIndex(where: { $0.id == blockID && $0.kind == .image }) else { throw ProjectStoryImageFailure.changedContext }
            blocks[bi].url = receipt.reference
        }
        var next = draft; next.chapters[ci].blocks = blocks; return next
    }
    private var isInsertBefore: Bool { if case .insertBefore = action { return true }; return false }
    public func hasAppliedReference(_ receipt: ProjectStoryUploadedImage, in draft: ProjectEditDraft,
                                    identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        if case .appendAlbumImage(let albumID) = action {
            guard receipt.ownerKey.utf8.elementsEqual(ownerKey.utf8), ownerKey.utf8.elementsEqual(session.ownerKey.utf8),
                  draftBucket.utf8.elementsEqual(identity.bucket.utf8), Data(resultingBlockID.utf8) == albumID,
                  let location = try? Self.album(draft, chapterID: chapterID, blockID: albumID, maximum: 6),
                  let last = location.images.last,
                  ProjectEditPendingMaterials.exactData(last) == ProjectEditPendingMaterials.exactData(
                    ProjectEditJSON.object(["url": .string(receipt.reference), "line": .string("")])) else { return false }
            // Remove exactly the appended ordinal and require the ENTIRE captured preimage.
            // A matching URL, same-looking array or matching prefix never proves application.
            var original = draft
            original.chapters[location.chapter].blocks?[location.block].sourceFields?["images"] = .array(Array(location.images.dropLast()))
            return matches(original, identity: identity, session: session)
        }
        guard receipt.ownerKey == ownerKey, ownerKey == session.ownerKey, identity.bucket == draftBucket,
              let block = draft.chapters.first(where: { $0.id == chapterID })?.blocks?.first(where: { $0.id == resultingBlockID }),
              block.kind == .image else { return false }
        if action == .append || isInsertBefore {
            guard draft.chapters.filter({ $0.id == chapterID }).count == 1,
                  let ci = draft.chapters.firstIndex(where: { $0.id == chapterID }),
                  let blocks = draft.chapters[ci].blocks, Set(blocks.map(\.id)).count == blocks.count,
                  let inserted = blocks.firstIndex(where: { $0.id == resultingBlockID }) else { return false }
            switch action {
            case .append: guard inserted == blocks.count - 1 else { return false }
            case .insertBefore(let anchorID):
                guard inserted + 1 < blocks.count, blocks[inserted + 1].id == anchorID else { return false }
            case .replace, .appendAlbumImage: return false
            }
            var expectedImage = ProjectEditBlock(kind: .image, url: receipt.reference); expectedImage.id = resultingBlockID
            guard ProjectEditPendingMaterials.exactData(block) == ProjectEditPendingMaterials.exactData(expectedImage) else { return false }
            var original = draft; original.chapters[ci].blocks?.remove(at: inserted)
            guard matches(original, identity: identity, session: session) else { return false }
        }
        return block.url.utf8.elementsEqual(receipt.reference.utf8)
    }
    public var isAlbumAppend: Bool { if case .appendAlbumImage = action { return true }; return false }

    /// Only known album shapes are editable. Never compactMap malformed rows or normalize
    /// existing references/captions. Canonical aliases are rejected, not used to select IDs.
    private static func album(_ draft: ProjectEditDraft, chapterID: String, blockID: Data,
                              maximum: Int) throws -> (chapter: Int, block: Int, images: [ProjectEditJSON]) {
        guard let id = String(data: blockID, encoding: .utf8), !id.isEmpty, !chapterID.isEmpty,
              draft.chapters.filter({ $0.id == chapterID }).count == 1,
              let ci = draft.chapters.firstIndex(where: { Data($0.id.utf8) == Data(chapterID.utf8) }),
              draft.chapters[ci].schemaVersion == 1,
              let blocks = draft.chapters[ci].blocks, blocks.count <= 200,
              !blocks.contains(where: { $0.id.isEmpty }), Set(blocks.map(\.id)).count == blocks.count,
              draft.chapters.flatMap({ $0.blocks ?? [] }).filter({ $0.id == id }).count == 1,
              let bi = blocks.firstIndex(where: { Data($0.id.utf8) == blockID }) else { throw ProjectStoryImageFailure.changedContext }
        let block = blocks[bi]
        guard block.kind == .dream, block.content.isEmpty, block.nodeID.isEmpty, block.url.isEmpty, block.localAudio == nil,
              let fields = block.sourceFields, Set(fields.keys.map { Data($0.utf8) }).isSubset(of: Set(["images", "title"].map { Data($0.utf8) })),
              let images = fields["images"]?.array, images.count <= maximum else { throw ProjectStoryImageFailure.changedContext }
        if let title = fields["title"], title != .null {
            guard let value = title.text, javaTrim(value).utf16.count <= 20 else { throw ProjectStoryImageFailure.changedContext }
        }
        for raw in images {
            guard let image = raw.object,
                  Set(image.keys.map { Data($0.utf8) }).isSubset(of: Set(["url", "line"].map { Data($0.utf8) })),
                  let url = image["url"]?.text, !javaTrim(url).isEmpty, url.utf16.count <= 500 else { throw ProjectStoryImageFailure.changedContext }
            if let line = image["line"], line != .null {
                guard let value = line.text, value.utf16.count <= 80 else { throw ProjectStoryImageFailure.changedContext }
            }
        }
        return (ci, bi, images)
    }
    private static func javaTrim(_ value: String) -> String {
        let scalars = value.unicodeScalars
        let start = scalars.firstIndex(where: { $0.value > 0x20 }) ?? scalars.endIndex
        let end = scalars.lastIndex(where: { $0.value > 0x20 }).map { scalars.index(after: $0) } ?? scalars.endIndex
        return String(scalars[start..<end])
    }

}
