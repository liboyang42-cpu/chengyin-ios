import Foundation

/// Editor-only display data. The existing story serializer still emits only its approved fields.
public struct ProjectStoryAudioLocalMetadata: Codable, Equatable {
    public let reference: String
    public let filename: String
    public init(reference: String, filename: String) { self.reference = reference; self.filename = filename }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reference.utf8.elementsEqual(rhs.reference.utf8) && lhs.filename.utf8.elementsEqual(rhs.filename.utf8)
    }
}

/// An audio block already exists before the picker opens, matching the Mini two-step action.
public struct ProjectStoryAudioTarget: Codable, Equatable {
    public let id: UUID
    public let ownerKey: String
    public let draftBucket: String
    public let chapterID: String
    public let blockID: String
    public let originalDraftHash: String
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, blockID: String, id: UUID = UUID()) throws {
        guard let chapter = draft.chapters.first(where: { $0.id == chapterID }),
              ProjectEditStarterPolicy.usesStoryEditor(product: draft.product, chapter: chapter),
              chapter.blocks?.contains(where: { $0.id == blockID && $0.kind == .audio }) == true,
              let raw = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryAudioFailure.changedContext }
        self.id = id; ownerKey = session.ownerKey; draftBucket = identity.bucket; self.chapterID = chapterID; self.blockID = blockID
        originalDraftHash = ProjectStoryImageTarget.hash(raw)
    }
    public func matches(_ draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        guard ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let raw = ProjectEditPendingMaterials.exactData(draft) else { return false }
        return ProjectStoryImageTarget.hash(raw) == originalDraftHash
    }
    public func applying(_ receipt: ProjectStoryUploadedAudio, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard receipt.ownerKey == ownerKey, receipt.reference.utf16.count <= 500,
              matches(draft, identity: identity, session: session),
              let ci = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              let bi = draft.chapters[ci].blocks?.firstIndex(where: { $0.id == blockID && $0.kind == .audio }) else { throw ProjectStoryAudioFailure.changedContext }
        var next = draft
        next.chapters[ci].blocks?[bi].url = receipt.reference
        next.chapters[ci].blocks?[bi].localAudio = .init(reference: receipt.reference, filename: receipt.filename)
        return next
    }
    public func hasAppliedReference(_ receipt: ProjectStoryUploadedAudio, in draft: ProjectEditDraft,
                                    identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        guard receipt.ownerKey == ownerKey, ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let block = draft.chapters.first(where: { $0.id == chapterID })?.blocks?.first(where: { $0.id == blockID }),
              block.kind == .audio, block.url.utf8.elementsEqual(receipt.reference.utf8) else { return false }
        return block.localAudio == .init(reference: receipt.reference, filename: receipt.filename)
    }
}
