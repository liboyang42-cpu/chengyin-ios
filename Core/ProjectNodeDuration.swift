import Foundation

/// NodeDTO.nodeTime is a Java Integer measured in minutes, not seconds.
/// A draft snapshot is retained verbatim until an explicit valid replacement.
public struct ProjectNodeDuration {
    public static let maximumMinutes = 2_147_483_647
    public let chapterID: String, nodeID: String
    public private(set) var available = false
    public private(set) var minutes = 0
    private var chapterIndex = 0, nodeIndex = 0
    private var bytes: Data?
    public init(draft: ProjectEditDraft, chapterID: String, nodeID: String) {
        self.chapterID = chapterID; self.nodeID = nodeID
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !nodeID.isEmpty, chapters.count == 1, let ci = chapters.first,
              draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8),
              draft.chapters.flatMap(\.nodes).filter({ $0.id == nodeID }).count == 1,
              let ni = draft.chapters[ci].nodes.firstIndex(where: { $0.id.utf8.elementsEqual(nodeID.utf8) }),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { return }
        self.bytes = bytes; chapterIndex = ci; nodeIndex = ni
        minutes = draft.chapters[ci].nodes[ni].nodeTime; available = true
    }
    /// The keypad accepts 1–10 ASCII digits. No trimming, signs, fraction,
    /// exponent, Unicode digits, clamping or silent fallback is performed.
    public static func parse(_ text: String) -> Int? {
        guard (1...10).contains(text.utf8.count), text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(text), value <= maximumMinutes else { return nil }
        return value
    }
    public static func adjusted(_ minutes: Int, by delta: Int) -> Int? {
        guard (0...maximumMinutes).contains(minutes), delta == -1 || delta == 1 else { return nil }
        let next = minutes + delta
        return (0...maximumMinutes).contains(next) ? next : nil
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        available && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func replacing(with text: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard let value = Self.parse(text) else { throw ProjectEditError.invalidDraft }
        guard value != minutes else { return draft }
        var next = draft; next.chapters[chapterIndex].nodes[nodeIndex].nodeTime = value; return next
    }
}
