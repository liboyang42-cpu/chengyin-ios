import Foundation

/// Only the public merchant's explicit activity feature is a destination.
/// POI, merchant and activity IDs are separate domains; none is a fallback.
public struct RoamFeaturedActivityTarget: Hashable {
    public let nodeID: Int
    public let merchantID: Int
    public let activityID: Int
    public init?(node: RoamNodeDetail, detail: RoamMerchantDetail) {
        guard node.id > 0, let merchantID = node.merchantId, merchantID > 0,
              merchantID == detail.merchant.id, let featured = detail.featured,
              featured.featuredType == 1, let activityID = featured.featuredId, activityID > 0 else { return nil }
        nodeID = node.id; self.merchantID = merchantID; self.activityID = activityID
    }
}

/// An explicit tap on one completed node/merchant read. A successful reread,
/// even with equal payloads, retires its callbacks and accepted destination.
public struct RoamFeaturedActivitySelection: Identifiable, Hashable {
    public let id = UUID()
    public let target: RoamFeaturedActivityTarget
    private let origin: RoamEventNavigationScope
    private let snapshotID: UUID
    public init?(place: RoamPlace, currentPlace: RoamPlace?, node: RoamNodeDetail, currentNode: RoamNodeDetail?,
                 detail: RoamMerchantDetail, currentDetail: RoamMerchantDetail?,
                 rendered: RoamEventNavigationScope?, current: RoamEventNavigationScope?,
                 snapshotID: UUID, currentSnapshotID: UUID) {
        guard place.id > 0, place == currentPlace, place.id == node.id,
              node == currentNode, detail == currentDetail, snapshotID == currentSnapshotID,
              let rendered, rendered == current, let target = RoamFeaturedActivityTarget(node: node, detail: detail) else { return nil }
        self.target = target; origin = rendered; self.snapshotID = snapshotID
    }
    public func mayRemainOpen(in current: RoamEventNavigationScope?, snapshotID: UUID) -> Bool {
        guard let current, self.snapshotID == snapshotID else { return false }
        // Normal push changes presentationID, not the read snapshot or authority.
        return origin.readerID == current.readerID && origin.identity == current.identity && origin.area == current.area
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
