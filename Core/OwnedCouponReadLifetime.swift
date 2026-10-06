import Foundation

/// Immutable owned history selection, distinct from reward-pool or coupon-definition IDs.
public struct OwnedCouponDetailSelection: Equatable, Identifiable, Sendable {
    public struct Identity: Hashable, Sendable { public let historyID: Int; public let ownerScope: UUID }
    public let historyID: Int
    public let ownerScope: UUID
    public var id: Identity { .init(historyID: historyID, ownerScope: ownerScope) }
    public init(historyID: Int, ownerScope: UUID) { self.historyID = historyID; self.ownerScope = ownerScope }
}
/// Coupon metadata read lifetime only; never a presentation credential or redemption authority.
@MainActor public final class OwnedCouponReadLifetime {
    public private(set) var isActive = true
    public let ownerScope: UUID?
    public init(ownerScope: UUID? = nil) { self.ownerScope = ownerScope }
    public func invalidate() { isActive = false }
    func check() throws { try Task.checkCancellation(); guard isActive else { throw CancellationError() } }
}
