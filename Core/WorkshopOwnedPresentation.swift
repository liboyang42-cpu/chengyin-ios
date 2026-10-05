import Foundation

/// Irrevocable permit for one visible screen. Issued synchronously by its presentation callback;
/// button actions offer a read BEFORE creating a Task. Neither value is a deployment approval.
@MainActor public final class WorkshopOwnedPresentationPermit {
    let claimID: String?
    private(set) var isLive = true
    fileprivate var currentAction: WorkshopOwnedActionPermit?
    init(claimID: String? = nil) { self.claimID = claimID }
    func revoke() { isLive = false; currentAction?.revoke(); currentAction = nil }
    public func offer() -> WorkshopOwnedActionPermit? {
        guard isLive else { return nil }
        currentAction?.revoke()
        let action = WorkshopOwnedActionPermit(presentation: self); currentAction = action; return action
    }
}
/// One synchronous UI action. New offers invalidate older queued AND in-flight reads.
@MainActor public final class WorkshopOwnedActionPermit {
    private(set) weak var presentation: WorkshopOwnedPresentationPermit?
    private var revoked = false
    private var entered = false
    fileprivate init(presentation: WorkshopOwnedPresentationPermit) { self.presentation = presentation }
    fileprivate func revoke() { revoked = true }
    func claim() -> Bool { guard isLive, !entered else { return false }; entered = true; return true }
    var isLive: Bool { !revoked && presentation?.isLive == true && presentation?.currentAction === self }
}
