import Foundation

@MainActor enum WorkshopPurchasedComposition {
    static func makeBrowser(context: RuntimeDependencyContext, api: APIConfiguration, transport: any HTTPTransport,
                            approval: WorkshopPurchasedReadApproval? = nil,
                            currentApproval: @escaping () -> WorkshopPurchasedReadApproval? = { nil },
                            current: @escaping () -> RuntimeDependencyContext?,
                            onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) -> WorkshopPurchasedBrowser? {
        guard let approval, approval.matches(context), currentApproval()?.revision == approval.revision,
              ContentDraftContextFence.matches(current(), context),
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { return nil }
        let lease = ContentDraftSessionLease(context: context, current: current)
        let reader = WorkshopPurchasedService(api: api, transport: transport, lease: lease, approval: approval,
            currentApproval: currentApproval, onUnauthorized: onUnauthorized)
        return WorkshopPurchasedBrowser(reader: reader, lease: lease)
    }
}
