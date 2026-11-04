import Foundation

/// Private host composition adapter. All inputs come from the existing AppSession;
/// endpoint approvals and final-forward transport are independently supplied by the root.
@MainActor enum NativeChannelManagementBinding {
    static func make(context: RuntimeDependencyContext, viewerRevision: UInt64, scope: NativeChannelManagementScope,
                     configuration: APIConfiguration, transport: any NativeChannelManagementDispatching,
                     storage: any ProjectEditDataStorage,
                     current: @escaping () -> RuntimeDependencyContext?, viewer: @escaping () -> UInt64,
                     selectedApproval: @escaping () -> NativeChannelManagementApproval?,
                     onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) -> NativeChannelManagementCoordinator? {
        guard let grant = selectedApproval(), grant.matches(context, viewerRevision: viewerRevision, scope: scope),
              let service = try? NativeChannelManagementHTTPService(context: context, viewerRevision: viewerRevision,
                  scope: scope, configuration: configuration, transport: transport, current: current, viewer: viewer,
                  selectedApproval: selectedApproval, onUnauthorized: onUnauthorized) else { return nil }
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: scope, storage: storage)
        return try? NativeChannelManagementCoordinator(service: service, journal: journal)
    }
}
