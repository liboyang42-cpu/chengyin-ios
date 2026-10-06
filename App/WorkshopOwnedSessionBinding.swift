import Foundation
import Observation

/// Retain one binding in AppSession. Call invalidate BEFORE mutating identity or read configuration,
/// including intermediate A → B → A transitions. Reconciliation is a second guard, not a substitute.
/// A revision only identifies separately reviewed configuration; it never grants endpoint access.
@MainActor @Observable final class WorkshopOwnedSessionBinding {
    private(set) var browser: WorkshopOwnedBrowser?
    private var captured: RuntimeDependencyContext?
    private var revision: UUID?

    func reconcile(context: RuntimeDependencyContext?, configurationRevision: UUID? = nil,
                   makeBrowser: (RuntimeDependencyContext) -> WorkshopOwnedBrowser?) {
        guard let context, let configurationRevision else { invalidate(); return }
        if ContentDraftContextFence.matches(captured, context),
           captured?.session.role.utf8.elementsEqual(context.session.role.utf8) == true,
           revision == configurationRevision { return }
        invalidate()
        captured = context; revision = configurationRevision
        browser = makeBrowser(context)
    }

    func invalidate() {
        // Normal Account body reads reconcile the default-off binding. An already-empty
        // binding must not publish fresh Observation mutations during that read.
        guard browser != nil || captured != nil || revision != nil else { return }
        browser?.invalidate()
        browser = nil; captured = nil; revision = nil
    }
}
