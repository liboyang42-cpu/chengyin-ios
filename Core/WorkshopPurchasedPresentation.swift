import Foundation

/// Irrevocable permit for one visible screen. Issued synchronously by its presentation callback;
/// button actions offer a read BEFORE creating a Task. Neither value is a deployment approval.
@MainActor public final class WorkshopPurchasedPresentationPermit {
    let licenseID: String?
    private(set) var isLive = true
    fileprivate var currentAction: WorkshopPurchasedActionPermit?
    init(licenseID: String? = nil) { self.licenseID = licenseID }
    func revoke() { isLive = false; currentAction?.revoke(); currentAction = nil }
    public func offer() -> WorkshopPurchasedActionPermit? {
        guard isLive else { return nil }
        currentAction?.revoke()
        let action = WorkshopPurchasedActionPermit(presentation: self); currentAction = action; return action
    }
}
/// One synchronous UI action. New offers invalidate older queued AND in-flight reads.
@MainActor public final class WorkshopPurchasedActionPermit {
    private(set) weak var presentation: WorkshopPurchasedPresentationPermit?
    private var revoked = false
    private var entered = false
    fileprivate init(presentation: WorkshopPurchasedPresentationPermit) { self.presentation = presentation }
    fileprivate func revoke() { revoked = true }
    func claim() -> Bool { guard isLive, !entered else { return false }; entered = true; return true }
    var isLive: Bool { !revoked && presentation?.isLive == true && presentation?.currentAction === self }
}
