import Foundation

/// The existing opaque businessTime field. This supports its source picker format
/// only; it does not establish opening, booking, date or timezone semantics.
public struct ProjectNodeBusinessHours {
    public enum Reason: String { case identity, unsupported }
    public struct Value: Equatable {
        public let startHour: Int, startMinute: Int, endHour: Int, endMinute: Int
        public init?(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
            guard (0...23).contains(startHour), (0...23).contains(endHour),
                  (0...59).contains(startMinute), (0...59).contains(endMinute) else { return nil }
            self.startHour = startHour; self.startMinute = startMinute; self.endHour = endHour; self.endMinute = endMinute
        }
        public var text: String {
            func pad(_ n: Int) -> String { (n < 10 ? "0" : "") + String(n) }
            return pad(startHour) + ":" + pad(startMinute) + "-" + pad(endHour) + ":" + pad(endMinute)
        }
    }
    public let chapterID: String, nodeID: String
    public private(set) var rawText: String?
    public private(set) var value: Value?
    public private(set) var reason: Reason?
    private var bytes: Data?
    private var chapterIndex = 0, nodeIndex = 0
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
        let raw = draft.chapters[ci].nodes[ni].localMetadata["businessTime"]
        guard let raw, raw != .null else { return }
        guard let text = raw.text else { reason = .unsupported; return }
        rawText = text
        guard !text.isEmpty else { return }
        let b = Array(text.utf8)
        // Match exactly the picker-produced ASCII form. Historical relaxed
        // parseInt formats are retained read-only, never silently normalized.
        guard b.count == 11, b[2] == 58, b[5] == 45, b[8] == 58,
              [0, 1, 3, 4, 6, 7, 9, 10].allSatisfy({ (48...57).contains(b[$0]) }) else { reason = .unsupported; return }
        func number(_ i: Int) -> Int { Int(b[i] - 48) * 10 + Int(b[i + 1] - 48) }
        guard let parsed = Value(startHour: number(0), startMinute: number(3), endHour: number(6), endMinute: number(9)) else { reason = .unsupported; return }
        value = parsed
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    /// Explicit clear has distinct semantics from an absent picker selection.
    /// An already-empty/missing/null representation remains byte-exact.
    public func clearing(in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard value != nil else { return draft }
        var next = draft; next.chapters[chapterIndex].nodes[nodeIndex].localMetadata["businessTime"] = .string("")
        return next
    }
    public func replacing(with selected: Value?, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard let selected, selected != value else { return draft }
        var next = draft; next.chapters[chapterIndex].nodes[nodeIndex].localMetadata["businessTime"] = .string(selected.text)
        return next
    }
}
