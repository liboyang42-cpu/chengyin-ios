import Foundation

/// A local edit to one exact slot in an ordinary node's existing image CSV.
/// References are opaque stored values. This type never reads or deletes assets.
public struct ProjectNodePhotoRemoval {
    public enum Reason: String { case identity, unsupported }
    public struct Photo: Identifiable {
        public let id: Int
        public let reference: String
    }
    public let chapterID: String
    public let nodeID: String
    public private(set) var reason: Reason?
    public private(set) var photos: [Photo] = []
    private var bytes: Data?
    private var chapterIndex = 0
    private var nodeIndex = 0

    public init(draft: ProjectEditDraft, chapterID: String, nodeID: String) {
        self.chapterID = chapterID; self.nodeID = nodeID
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !nodeID.isEmpty, chapters.count == 1, let ci = chapters.first,
              draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8),
              draft.chapters.flatMap(\.nodes).filter({ $0.id == nodeID }).count == 1,
              !(draft.pendingMaterials ?? []).contains(where: { $0.id == nodeID }),
              let ni = draft.chapters[ci].nodes.firstIndex(where: { $0.id.utf8.elementsEqual(nodeID.utf8) }),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { reason = .identity; return }
        self.bytes = bytes; chapterIndex = ci; nodeIndex = ni
        let raw = draft.chapters[ci].nodes[ni].imgUrl
        guard !raw.isEmpty else { return }
        // The mini stores at most nine comma-delimited references. Reject legacy
        // shapes we cannot present as exact slots; do not trim, filter or deduplicate.
        guard raw.utf8.count <= 96 * 1024 else { reason = .unsupported; return }
        // Swift Character splitting can absorb a comma plus a following combining
        // mark into one grapheme. The source delimiter is the literal 0x2C byte.
        let values = Array(raw.utf8).split(separator: 0x2C, maxSplits: 9, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard (1...9).contains(values.count),
              values.allSatisfy({ value in
                  !value.isEmpty && value.utf8.elementsEqual(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8) &&
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
                  !value.contains("\"") && !value.contains("[") && !value.contains("]") && !value.contains("{") && !value.contains("}")
              }) else { reason = .unsupported; return }
        photos = values.enumerated().map { .init(id: $0.offset, reference: $0.element) }
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func applying(removing slot: Int?, to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard let slot else { return draft }
        guard photos.indices.contains(slot), photos[slot].id == slot else { throw ProjectEditError.invalidDraft }
        // Delete only the selected ordinal, even when two references have equal
        // text or canonically equivalent Unicode. Untouched bytes/order survive.
        let retained = photos.enumerated().filter { $0.offset != slot }.map { $0.element.reference }
        var next = draft; next.chapters[chapterIndex].nodes[nodeIndex].imgUrl = retained.joined(separator: ",")
        return next
    }
}
