import SwiftUI

/// One optional draft lease. An accepted lease never downgrades to legacy mode.
@MainActor final class ClubProfileDraftVisit: ObservableObject, Identifiable {
    let id = UUID()
    private(set) var bound = false
    private(set) var enabled = false
    private(set) var context: ClubProfileLocalDraftContext?
    private var target: ClubOperationsTarget?
    private var identity: ClubReadIdentity?
    private var accessID: ObjectIdentifier?
    private var retired = false
    func bind(target: ClubOperationsTarget, identity: ClubReadIdentity?, access: any ClubOperationsAccess) {
        guard !bound else { return }
        bound = true; self.target = target; self.identity = identity; accessID = ObjectIdentifier(access)
        if target != .create, let context = access.profileDrafts {
            enabled = true; self.context = context
            if !context.isCurrent || context.identity != identity { retired = true }
        }
    }
    func matches(target: ClubOperationsTarget, identity: ClubReadIdentity?, access: any ClubOperationsAccess) -> Bool {
        guard bound, !retired, self.target == target, self.identity == identity,
              access.identity == identity, accessID == ObjectIdentifier(access) else { return false }
        guard enabled else { return true }
        guard let context, context.isCurrent, let current = access.profileDrafts, current.isCurrent else { return false }
        return context.identity == current.identity && context.namespace == current.namespace &&
            context.viewerRevision == current.viewerRevision && context.store === current.store
    }
    func retire() { retired = true }
}
