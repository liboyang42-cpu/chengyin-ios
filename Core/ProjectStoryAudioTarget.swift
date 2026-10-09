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

/// Explicit chapter narration or an existing story audio block. Legacy block bytes stay unchanged.
public struct ProjectStoryAudioTarget: Codable, Equatable {
    public let id: UUID
    public let ownerKey: String
    public let draftBucket: String
    public let chapterID: String
    public enum Kind: String, Codable { case storyBlock, chapterNarration }
    public let kind: Kind
    public let blockID: String?
    public let originalDraftHash: String
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, blockID: String, id: UUID = UUID()) throws {
        guard let chapter = draft.chapters.first(where: { $0.id == chapterID }),
              ProjectEditStarterPolicy.usesStoryEditor(product: draft.product, chapter: chapter),
              chapter.blocks?.contains(where: { $0.id == blockID && $0.kind == .audio }) == true,
              let raw = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryAudioFailure.changedContext }
        self.id = id; ownerKey = session.ownerKey; draftBucket = identity.bucket; self.chapterID = chapterID; self.blockID = blockID; kind = .storyBlock
        originalDraftHash = ProjectStoryImageTarget.hash(raw)
    }
    public init(chapterNarrationIn draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, id: UUID = UUID()) throws {
        guard let index = ProjectChapterAudio.chapterIndex(chapterID, in: draft),
              !ProjectChapterAudio.isUnsupported(in: draft.chapters[index]),
              let raw = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryAudioFailure.changedContext }
        self.id = id; ownerKey = session.ownerKey; draftBucket = identity.bucket; self.chapterID = chapterID
        kind = .chapterNarration; blockID = nil; originalDraftHash = ProjectStoryImageTarget.hash(raw)
    }
    private enum CodingKeys: String, CodingKey { case id, ownerKey, draftBucket, chapterID, blockID, originalDraftHash, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); ownerKey = try c.decode(String.self, forKey: .ownerKey)
        draftBucket = try c.decode(String.self, forKey: .draftBucket); chapterID = try c.decode(String.self, forKey: .chapterID)
        originalDraftHash = try c.decode(String.self, forKey: .originalDraftHash)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .storyBlock
        blockID = try c.decodeIfPresent(String.self, forKey: .blockID)
        guard hasValidDestination, kind != .chapterNarration || !c.contains(.blockID) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid audio destination"))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(ownerKey, forKey: .ownerKey); try c.encode(draftBucket, forKey: .draftBucket)
        try c.encode(chapterID, forKey: .chapterID); try c.encode(originalDraftHash, forKey: .originalDraftHash)
        if kind == .storyBlock { try c.encode(blockID, forKey: .blockID) }
        else { try c.encode(kind, forKey: .kind) }
    }
    public var hasValidDestination: Bool {
        guard !chapterID.isEmpty else { return false }
        switch kind {
        case .storyBlock: return blockID?.isEmpty == false
        case .chapterNarration: return blockID == nil
        }
    }
    public var maximumReferenceUTF16Count: Int { kind == .chapterNarration ? ProjectChapterAudio.maximumReferenceUTF16Count : 500 }
    public func matches(_ draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        guard ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let raw = ProjectEditPendingMaterials.exactData(draft) else { return false }
        return ProjectStoryImageTarget.hash(raw) == originalDraftHash
    }
    public func applying(_ receipt: ProjectStoryUploadedAudio, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        if kind == .chapterNarration {
            guard receipt.ownerKey == ownerKey, ProjectChapterAudio.fitsWire(receipt.reference),
                  matches(draft, identity: identity, session: session),
                  let index = ProjectChapterAudio.chapterIndex(chapterID, in: draft),
                  !ProjectChapterAudio.isUnsupported(in: draft.chapters[index]) else { throw ProjectStoryAudioFailure.changedContext }
            var next = draft
            next.chapters[index].preserved["audioUrl"] = .string(receipt.reference)
            next.chapters[index].preserved["audioFileName"] = .string(receipt.filename)
            if next.chapters[index].preserved["audioDuration"] != nil { next.chapters[index].preserved["audioDuration"] = .number(0) }
            return next
        }
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
        if kind == .chapterNarration {
            guard receipt.ownerKey == ownerKey, ownerKey == session.ownerKey, draftBucket == identity.bucket,
                  let index = ProjectChapterAudio.chapterIndex(chapterID, in: draft),
                  let reference = ProjectChapterAudio.reference(in: draft.chapters[index]),
                  let filename = draft.chapters[index].preserved["audioFileName"]?.text else { return false }
            return reference.utf8.elementsEqual(receipt.reference.utf8) && filename.utf8.elementsEqual(receipt.filename.utf8)
        }
        guard receipt.ownerKey == ownerKey, ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let block = draft.chapters.first(where: { $0.id == chapterID })?.blocks?.first(where: { $0.id == blockID }),
              block.kind == .audio, block.url.utf8.elementsEqual(receipt.reference.utf8) else { return false }
        return block.localAudio == .init(reference: receipt.reference, filename: receipt.filename)
    }
}
