import Foundation

/// A coupon feature opens the owner's wallet. Its optional featuredId is not an
/// owned-coupon ID, a claim request or permission to reveal a redemption code.
public struct RoamFeaturedCouponWalletTarget: Hashable {
    public let nodeID: Int
    public let merchantID: Int
    public init?(node: RoamNodeDetail, detail: RoamMerchantDetail) {
        guard node.id > 0, let merchantID = node.merchantId, merchantID > 0,
              merchantID == detail.merchant.id, detail.featured?.featuredType == 2 else { return nil }
        nodeID = node.id; self.merchantID = merchantID
    }
}

/// Explicit navigation from the current, completed node/merchant read only.
public struct RoamFeaturedCouponWalletSelection: Identifiable, Hashable {
    public let id = UUID()
    public let target: RoamFeaturedCouponWalletTarget
    private let origin: RoamEventNavigationScope
    private let snapshotID: UUID
    public init?(place: RoamPlace, currentPlace: RoamPlace?, node: RoamNodeDetail, currentNode: RoamNodeDetail?,
                 detail: RoamMerchantDetail, currentDetail: RoamMerchantDetail?,
                 rendered: RoamEventNavigationScope?, current: RoamEventNavigationScope?,
                 snapshotID: UUID, currentSnapshotID: UUID) {
        guard place.id > 0, place == currentPlace, place.id == node.id,
              node == currentNode, detail == currentDetail, snapshotID == currentSnapshotID,
              let rendered, rendered == current,
              let target = RoamFeaturedCouponWalletTarget(node: node, detail: detail) else { return nil }
        self.target = target; origin = rendered; self.snapshotID = snapshotID
    }
    public func mayRemainOpen(in current: RoamEventNavigationScope?, snapshotID: UUID) -> Bool {
        guard let current, self.snapshotID == snapshotID else { return false }
        // Pushing a destination retires overview callbacks but retains its authority.
        return origin.readerID == current.readerID && origin.identity == current.identity && origin.area == current.area
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
