import Foundation

@MainActor final class WorkshopCreatorPendingSessionBinding {
    private var context: RuntimeDependencyContext?
    private var source: Int64?
    private var revisions: [UUID?] = []
    private var controller: WorkshopCreatorPendingController?
    func make(source: Int64, context: RuntimeDependencyContext?, revisions: [UUID?],
              create: (RuntimeDependencyContext) -> WorkshopCreatorPendingController?) -> WorkshopCreatorPendingController? {
        guard let context, source > 0 else { invalidate(); return nil }
        if self.source == source, self.revisions == revisions, ContentDraftContextFence.matches(self.context, context),
           self.context?.session.role.utf8.elementsEqual(context.session.role.utf8) == true, let controller { return controller }
        invalidate(); guard let result = create(context) else { return nil }
        self.source = source; self.context = context; self.revisions = revisions; controller = result; return result
    }
    func invalidate() { controller?.invalidate(); controller = nil; context = nil; source = nil; revisions = [] }
}
