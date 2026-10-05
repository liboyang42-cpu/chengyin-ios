import Foundation

/// Independent integration seam. Does not enable or register itself in the normal app session.
@MainActor enum WorkshopOwnedComposition {
    static func makeBrowser(context: RuntimeDependencyContext, api: APIConfiguration, transport: any HTTPTransport,
                            approval: WorkshopOwnedReadApproval? = nil,
                            currentApproval: @escaping () -> WorkshopOwnedReadApproval? = { nil },
                            current: @escaping () -> RuntimeDependencyContext?,
                            packageApproval: WorkshopOwnedPackageReadApproval? = nil,
                            currentPackageApproval: @escaping () -> WorkshopOwnedPackageReadApproval? = { nil },
                            onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) -> WorkshopOwnedBrowser? {
        guard let approval, approval.matches(context), currentApproval()?.revision == approval.revision,
              ContentDraftContextFence.matches(current(), context),
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { return nil }
        let lease = ContentDraftSessionLease(context: context, current: current)
        let reader = WorkshopOwnedService(api: api, transport: transport, lease: lease,
            approval: approval, currentApproval: currentApproval, onUnauthorized: onUnauthorized)
        var packageBrowser: WorkshopOwnedPackageBrowser?
        if let packageApproval, packageApproval.matches(context), currentPackageApproval()?.revision == packageApproval.revision {
            let packageReader = WorkshopOwnedPackageService(api: api, transport: transport, lease: lease,
                approval: packageApproval, currentApproval: currentPackageApproval, onUnauthorized: onUnauthorized)
            packageBrowser = WorkshopOwnedPackageBrowser(reader: packageReader, lease: lease)
        }
        return WorkshopOwnedBrowser(reader: reader, lease: lease, packageBrowser: packageBrowser)
    }
}
