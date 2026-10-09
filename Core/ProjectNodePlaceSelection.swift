import Foundation

/// A chosen city POI is distinct from the manually entered search centre.
/// This adapter changes only location fields and an originally empty node name.
public struct ProjectNodePlaceSelection {
    public private(set) var available = false
    private var bytes: Data?
    private var chapterIndex = 0, nodeIndex = 0
    public init(draft: ProjectEditDraft, chapterID: String, nodeID: String) {
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !nodeID.isEmpty, chapters.count == 1, let ci = chapters.first,
              Data(draft.chapters[ci].id.utf8) == Data(chapterID.utf8),
              draft.chapters.flatMap(\.nodes).filter({ $0.id == nodeID }).count == 1,
              !(draft.pendingMaterials ?? []).contains(where: { $0.id == nodeID }),
              let ni = draft.chapters[ci].nodes.firstIndex(where: { Data($0.id.utf8) == Data(nodeID.utf8) }),
              draft.chapters[ci].blocks?.contains(where: { $0.kind == .node && $0.nodeID == nodeID && $0.sourceFields?["locationRequired"] == .bool(false) }) != true,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { return }
        self.bytes = bytes; chapterIndex = ci; nodeIndex = ni; available = true
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        available && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public static func permits(_ poi: SearchMapCityNode) -> Bool {
        guard poi.id > 0, let coordinate = poi.coordinate,
              coordinate.latitude != 0, coordinate.longitude != 0,
              !poi.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !poi.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        return true
    }
    public func applying(_ poi: SearchMapCityNode, to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        var next = draft
        next.chapters[chapterIndex].nodes[nodeIndex] = try Self.replacingLocation(of: draft.chapters[chapterIndex].nodes[nodeIndex], with: poi)
        return next
    }
    /// Shared location-only adapter for saved nodes and staged pending candidates.
    public static func replacingLocation(of node: ProjectEditNode, with poi: SearchMapCityNode) throws -> ProjectEditNode {
        guard Self.permits(poi), let coordinate = poi.coordinate else { throw ProjectEditError.invalidDraft }
        var next = node
        // The existing city-node projection has no street-address field. Its place label
        // is explicitly reviewed as the address, matching the existing POI name fallback.
        next.address = poi.name
        if Double(next.latitude) != coordinate.latitude { next.latitude = String(coordinate.latitude) }
        if Double(next.longitude) != coordinate.longitude { next.longitude = String(coordinate.longitude) }
        if next.name.isEmpty { next.name = poi.name }
        return next
    }

}
