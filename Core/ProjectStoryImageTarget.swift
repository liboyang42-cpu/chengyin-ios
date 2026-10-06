import Foundation
import CryptoKit

/// Captures the real local draft and original chapter order. No server identity/version is invented.
public struct ProjectStoryImageTarget: Codable, Equatable {
    public enum Action: Codable, Equatable { case append, replace(String), insertBefore(String) }
    public let id: UUID
    public let ownerKey: String
    public let draftBucket: String
    public let chapterID: String
    public let originalDraftHash: String
    public let action: Action
    public let resultingBlockID: String
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, replacing blockID: String? = nil, insertingBefore anchorID: String? = nil, id: UUID = UUID()) throws {
        guard blockID == nil || anchorID == nil,
              draft.chapters.filter({ $0.id == chapterID }).count == 1,
              let chapter = draft.chapters.first(where: { $0.id == chapterID }), let blocks = chapter.blocks,
              Set(blocks.map(\.id)).count == blocks.count,
              ProjectEditStarterPolicy.usesStoryEditor(product: draft.product, chapter: chapter),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryImageFailure.changedContext }
        let action: Action
        if let anchorID {
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
        originalDraftHash = Self.hash(bytes); self.action = action; resultingBlockID = blockID ?? id.uuidString
    }
    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public func matches(_ draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        guard ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { return false }
        return Self.hash(bytes) == originalDraftHash
    }
    public func applying(_ receipt: ProjectStoryUploadedImage, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard receipt.ownerKey == ownerKey, receipt.reference.utf16.count <= 500, matches(draft, identity: identity, session: session),
              let ci = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              var blocks = draft.chapters[ci].blocks else { throw ProjectStoryImageFailure.changedContext }
        switch action {
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
            case .replace: return false
            }
            var expectedImage = ProjectEditBlock(kind: .image, url: receipt.reference); expectedImage.id = resultingBlockID
            guard ProjectEditPendingMaterials.exactData(block) == ProjectEditPendingMaterials.exactData(expectedImage) else { return false }
            var original = draft; original.chapters[ci].blocks?.remove(at: inserted)
            guard matches(original, identity: identity, session: session) else { return false }
        }
        return block.url.utf8.elementsEqual(receipt.reference.utf8)
    }
}
