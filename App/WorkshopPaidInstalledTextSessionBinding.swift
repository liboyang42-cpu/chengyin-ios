import Foundation

/// One session-owned protected review controller, with its own independent deployment approval.
/// Identity/configuration replacement invalidates it before mutation and clears all protected data.
@MainActor final class WorkshopPaidInstalledTextSessionBinding {
    private var captured: RuntimeDependencyContext?
    private var revision: UUID?
    private var controller: WorkshopPaidInstalledTextController?
    func make(reference: WorkshopPaidInstalledTextReference, context: RuntimeDependencyContext?, approval: WorkshopPaidInstalledTextApproval?,
              api: APIConfiguration?, transport: any HTTPTransport,
              currentApproval: @escaping () -> WorkshopPaidInstalledTextApproval?, current: @escaping () -> RuntimeDependencyContext?,
              onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) -> WorkshopPaidInstalledTextController? {
        guard let context, let approval, let api, approval.matches(context), currentApproval()?.revision == approval.revision,
              ContentDraftContextFence.matches(current(), context), api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { invalidate(); return nil }
        if ContentDraftContextFence.matches(captured, context), captured?.session.role.utf8.elementsEqual(context.session.role.utf8) == true,
           revision == approval.revision, let controller, controller.reference == reference { return controller }
        invalidate()
        let lease = ContentDraftSessionLease(context: context, current: current)
        let service = WorkshopPaidInstalledTextService(api: api, transport: transport, lease: lease, approval: approval,
            currentApproval: currentApproval, onUnauthorized: onUnauthorized)
        let result = WorkshopPaidInstalledTextController(reference: reference, service: service, lease: lease)
        captured = context; revision = approval.revision; controller = result; return result
    }
    func invalidate() {
        guard captured != nil || revision != nil || controller != nil else { return }
        controller?.invalidate(); controller = nil; captured = nil; revision = nil
    }
}
