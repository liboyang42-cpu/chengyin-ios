import Foundation
import Observation

/// Retain one binding in AppSession. Call invalidate BEFORE mutating identity or read configuration,
/// including intermediate A → B → A transitions. Reconciliation is a second guard, not a substitute.
/// A revision only identifies separately reviewed configuration; it never grants endpoint access.
@MainActor @Observable final class WorkshopPurchasedSessionBinding {
    private(set) var browser: WorkshopPurchasedBrowser?
    private var captured: RuntimeDependencyContext?
    private var revision: UUID?

    func reconcile(context: RuntimeDependencyContext?, configurationRevision: UUID? = nil,
                   makeBrowser: (RuntimeDependencyContext) -> WorkshopPurchasedBrowser?) {
        guard let context, let configurationRevision else { invalidate(); return }
        if ContentDraftContextFence.matches(captured, context),
           captured?.session.role.utf8.elementsEqual(context.session.role.utf8) == true,
           revision == configurationRevision { return }
        invalidate()
        captured = context; revision = configurationRevision
        browser = makeBrowser(context)
    }

    func invalidate() {
        // Already disabled read reconciliation must not publish body-time mutations.
        guard browser != nil || captured != nil || revision != nil else { return }
        browser?.invalidate()
        browser = nil; captured = nil; revision = nil
    }
}
