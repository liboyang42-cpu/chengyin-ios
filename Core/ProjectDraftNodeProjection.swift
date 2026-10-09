import Foundation

/// Read-only source-order overview of placed chapter nodes. Coordinates are
/// retained as authored text, never relabelled as a MapKit-compatible datum.
public struct ProjectDraftNodeProjection {
    public enum Reason: String { case identity, limit }
    public enum CoordinateState: String { case missing, invalid, zero, datumUnverified }
    public struct Key: Hashable {
        public let chapter: Data
        public let node: Data
        public init(chapterID: String, nodeID: String) { chapter = Data(chapterID.utf8); node = Data(nodeID.utf8) }
    }
    public struct Row: Identifiable {
        public let id: Key
        public let chapterID: String, nodeID: String
        public let order: Int, chapterOrder: Int
        public let chapterName: String, name: String, address: String
        public let longitude: String, latitude: String
        public let coordinates: CoordinateState
    }
    public private(set) var rows: [Row] = []
    public private(set) var reason: Reason?
    public let chapterCount: Int
    public let excludedPendingCount: Int
    private var bytes: Data?

    public init(draft: ProjectEditDraft) {
        chapterCount = draft.chapters.count; excludedPendingCount = (draft.pendingMaterials ?? []).count
        guard draft.chapters.count <= 128, draft.chapters.flatMap(\.nodes).count <= 512 else { reason = .limit; return }
        let chapterIDs = draft.chapters.map(\.id)
        let nodeIDs = draft.chapters.flatMap(\.nodes).map(\.id) + (draft.pendingMaterials ?? []).map(\.id)
        // Existing child editors still use String identities. Reject canonical
        // aliases as well as exact duplicates rather than choose a first match.
        guard chapterIDs.allSatisfy({ !$0.isEmpty }), Set(chapterIDs).count == chapterIDs.count,
              nodeIDs.allSatisfy({ !$0.isEmpty }), Set(nodeIDs).count == nodeIDs.count,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { reason = .identity; return }
        self.bytes = bytes
        for (ci, chapter) in draft.chapters.enumerated() {
            for node in chapter.nodes {
                rows.append(.init(id: .init(chapterID: chapter.id, nodeID: node.id), chapterID: chapter.id, nodeID: node.id,
                    order: rows.count + 1, chapterOrder: ci + 1, chapterName: chapter.name, name: node.name, address: node.address,
                    longitude: node.longitude, latitude: node.latitude, coordinates: Self.coordinateState(node)))
            }
        }
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func row(_ key: Key) -> Row? { reason == nil ? rows.first { $0.id == key } : nil }
    public func resolve(_ key: Key, in draft: ProjectEditDraft) -> Row? { isCurrent(in: draft) ? row(key) : nil }
    private static func coordinateState(_ node: ProjectEditNode) -> CoordinateState {
        if node.longitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            node.latitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missing }
        if node.hasUsableCoordinates { return .datumUnverified }
        if let longitude = Double(node.longitude), let latitude = Double(node.latitude),
           longitude.isFinite, latitude.isFinite, (-180...180).contains(longitude), (-90...90).contains(latitude),
           longitude == 0 || latitude == 0 { return .zero }
        return .invalid
    }
}
