import Foundation

@MainActor final class WorkshopPaidProfessionalSessionBinding {
    private var context: RuntimeDependencyContext?
    private var revisions: [UUID?] = []
    private var controller: WorkshopPaidProfessionalController?
    func make(reference: WorkshopPaidInstalledTextReference, context: RuntimeDependencyContext?, revisions: [UUID?],
              build: (RuntimeDependencyContext) -> WorkshopPaidProfessionalController?) -> WorkshopPaidProfessionalController? {
        guard let context else { invalidate(); return nil }
        if ContentDraftContextFence.matches(self.context, context), self.context?.session.role.utf8.elementsEqual(context.session.role.utf8) == true,
           self.revisions == revisions, let controller, controller.reference == reference { return controller }
        invalidate()
        guard let controller = build(context) else { return nil }
        self.context = context; self.revisions = revisions; self.controller = controller; return controller
    }
    func invalidate() { controller?.invalidate(); controller = nil; context = nil; revisions = [] }
}
