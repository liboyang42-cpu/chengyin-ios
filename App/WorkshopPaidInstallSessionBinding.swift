import Foundation

/// Session-owned single controller. UI closure only asks for this binding; it cannot manufacture an
/// approval. Identity/configuration changes must invalidate before mutation, including A → B → A.
@MainActor final class WorkshopPaidInstallSessionBinding {
    private var captured: RuntimeDependencyContext?
    private var revision: UUID?
    private var controller: WorkshopPaidInstallController?
    func make(item: WorkshopPurchasedItem, context: RuntimeDependencyContext?, approval: WorkshopPaidInstallApproval?,
              api: APIConfiguration?, transport: any HTTPTransport, storage: any TemplateAuthoringStorage,
              currentApproval: @escaping () -> WorkshopPaidInstallApproval?, current: @escaping () -> RuntimeDependencyContext?,
              onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) -> WorkshopPaidInstallController? {
        guard let context, let approval, let api, approval.matches(context), currentApproval()?.revision == approval.revision,
              ContentDraftContextFence.matches(current(), context), api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { invalidate(); return nil }
        if ContentDraftContextFence.matches(captured, context), captured?.session.role.utf8.elementsEqual(context.session.role.utf8) == true,
           revision == approval.revision, let controller, controller.item == item { return controller }
        invalidate()
        guard let store = try? WorkshopPaidInstallPendingStore(storage: storage, context: context, licenseId: item.licenseId) else { return nil }
        let lease = ContentDraftSessionLease(context: context, current: current)
        let service = WorkshopPaidInstallService(api: api, transport: transport, lease: lease, approval: approval, currentApproval: currentApproval, onUnauthorized: onUnauthorized)
        let result = WorkshopPaidInstallController(item: item, service: service, lease: lease, store: store)
        captured = context; revision = approval.revision; controller = result; return result
    }
    func invalidate() {
        guard captured != nil || revision != nil || controller != nil else { return }
        controller?.invalidate(); controller = nil; captured = nil; revision = nil
    }
}
