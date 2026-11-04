import Foundation

/// An owner may disappear while its service is queued. A retained transport must not
/// retain that owner or revive its old authority when the same screen opens again.
@MainActor final class NativeWebhookRuntimeVisit {
    private weak var owner: NativeWebhookCoordinator?
    private var bound = false
    private var retired = false
    @discardableResult func bind(_ owner: NativeWebhookCoordinator) -> Bool {
        guard !bound, !retired else { retire(); return false }
        bound = true; self.owner = owner
        guard owner.bindRuntimeRetirement({ [weak self] in self?.retire() }) else { retire(); return false }
        return isCurrent
    }
    func retire() { retired = true }
    var isCurrent: Bool {
        guard !retired else { return false }
        // The real factory's construction is inert. Bind immediately upon return.
        guard bound else { return true }
        guard let owner, owner.phase != .revoked, owner.phase != .denied,
              owner.presentationIsCurrent() else { retire(); return false }
        return true
    }
}
