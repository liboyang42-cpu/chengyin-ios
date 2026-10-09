import Foundation
import CryptoKit

/// One exact ordinary node and complete draft preimage. Existing CSV bytes are opaque.
public struct ProjectNodeImageTarget: Codable, Equatable {
    public let id: UUID
    public let ownerKey: String
    public let draftBucket: String
    public let chapterID: Data
    public let nodeID: Data
    public let originalCSV: Data
    public let originalDraftHash: String
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                scope: ProjectEditScope, chapterID: String, nodeID: String, id: UUID = UUID()) throws {
        let field = ProjectNodePhotoRemoval(draft: draft, chapterID: chapterID, nodeID: nodeID)
        guard scope == .full, draft.owner == .personal, field.isCurrent(in: draft), field.photos.count < 9,
              let ci = draft.chapters.firstIndex(where: { Data($0.id.utf8) == Data(chapterID.utf8) }),
              let node = draft.chapters[ci].nodes.first(where: { Data($0.id.utf8) == Data(nodeID.utf8) }),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectNodeImageFailure.changedContext }
        self.id = id; ownerKey = session.ownerKey; draftBucket = identity.bucket
        self.chapterID = Data(chapterID.utf8); self.nodeID = Data(nodeID.utf8)
        originalCSV = Data(node.imgUrl.utf8); originalDraftHash = Self.hash(bytes)
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && Data(a.ownerKey.utf8) == Data(b.ownerKey.utf8) && Data(a.draftBucket.utf8) == Data(b.draftBucket.utf8) &&
        a.chapterID == b.chapterID && a.nodeID == b.nodeID && a.originalCSV == b.originalCSV && a.originalDraftHash == b.originalDraftHash
    }
    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public func sameField(_ other: Self) -> Bool {
        Data(ownerKey.utf8) == Data(other.ownerKey.utf8) && Data(draftBucket.utf8) == Data(other.draftBucket.utf8) &&
        chapterID == other.chapterID && nodeID == other.nodeID
    }
    public func matches(_ draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        Data(ownerKey.utf8) == Data(session.ownerKey.utf8) && Data(draftBucket.utf8) == Data(identity.bucket.utf8) &&
        ProjectEditPendingMaterials.exactData(draft).map(Self.hash) == originalDraftHash
    }
    public static func representable(_ reference: String) -> Bool {
        !reference.isEmpty && !reference.utf8.contains(0x2C) &&
        !reference.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) } &&
        !reference.contains("\"") && !reference.contains("[") && !reference.contains("]") && !reference.contains("{") && !reference.contains("}")
    }
    private func location(_ draft: ProjectEditDraft, maximum: Int) -> (Int, Int)? {
        guard let chapter = String(data: chapterID, encoding: .utf8), let node = String(data: nodeID, encoding: .utf8),
              draft.owner == .personal else { return nil }
        let field = ProjectNodePhotoRemoval(draft: draft, chapterID: chapter, nodeID: node)
        guard field.isCurrent(in: draft), field.photos.count <= maximum,
              let ci = draft.chapters.firstIndex(where: { Data($0.id.utf8) == chapterID }),
              let ni = draft.chapters[ci].nodes.firstIndex(where: { Data($0.id.utf8) == nodeID }) else { return nil }
        return (ci, ni)
    }
    public func applying(_ receipt: ProjectNodeUploadedImage, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard receipt.targetID == id, Data(receipt.ownerKey.utf8) == Data(ownerKey.utf8), Self.representable(receipt.reference),
              matches(draft, identity: identity, session: session), let (ci,ni) = location(draft, maximum: 8),
              Data(draft.chapters[ci].nodes[ni].imgUrl.utf8) == originalCSV else { throw ProjectNodeImageFailure.changedContext }
        var bytes = originalCSV; if !bytes.isEmpty { bytes.append(0x2C) }; bytes.append(Data(receipt.reference.utf8))
        // Same conservative local record bound as exact-slot removal, not a backend promise.
        guard bytes.count <= 96 * 1024, let csv = String(data: bytes, encoding: .utf8) else { throw ProjectNodeImageFailure.invalidResponse }
        var next = draft; next.chapters[ci].nodes[ni].imgUrl = csv; return next
    }
    public func hasAppliedReference(_ receipt: ProjectNodeUploadedImage, in draft: ProjectEditDraft,
                                    identity: ProjectEditDraftIdentity, session: ProjectEditSession) -> Bool {
        guard receipt.targetID == id, Data(receipt.ownerKey.utf8) == Data(ownerKey.utf8), Self.representable(receipt.reference),
              let (ci,ni) = location(draft, maximum: 9), let original = String(data: originalCSV, encoding: .utf8) else { return false }
        var exact = originalCSV; if !exact.isEmpty { exact.append(0x2C) }; exact.append(Data(receipt.reference.utf8))
        guard Data(draft.chapters[ci].nodes[ni].imgUrl.utf8) == exact else { return false }
        var restored = draft; restored.chapters[ci].nodes[ni].imgUrl = original
        return matches(restored, identity: identity, session: session)
    }
}
