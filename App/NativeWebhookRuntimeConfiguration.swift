import Foundation

/// Reviewed deployment inputs, not native identity or channel RBAC. No default grant,
/// wildcard paths, credential generation, transport execution or pending-request replay.
struct NativeWebhookRuntimeConfiguration: Equatable {
    let endpoints: OperationEndpointApproval
    let scopes: Set<NativeWebhookScope>
    let revision: String
    let enabled: Bool

    init(endpoints: OperationEndpointApproval, scopes: Set<NativeWebhookScope>,
         revision: String, enabled: Bool = false) throws {
        guard !scopes.isEmpty, !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              endpoints.paths.contains("api/im/webhook/context"),
              endpoints.paths.allSatisfy({ $0.hasPrefix("api/im/webhook/") && !$0.contains("*") && !$0.contains("#") }) else {
            throw APIError.invalidConfiguration
        }
        self.endpoints = endpoints; self.scopes = scopes; self.revision = revision; self.enabled = enabled
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled && lhs.scopes == rhs.scopes
            && lhs.revision.utf8.elementsEqual(rhs.revision.utf8)
            && lhs.endpoints.baseURL.absoluteString.utf8.elementsEqual(rhs.endpoints.baseURL.absoluteString.utf8)
            && lhs.endpoints.namespace.utf8.elementsEqual(rhs.endpoints.namespace.utf8)
            && lhs.endpoints.accountID == rhs.endpoints.accountID
            && Set(lhs.endpoints.paths.map { Data($0.utf8) }) == Set(rhs.endpoints.paths.map { Data($0.utf8) })
    }
    func approval(for context: RuntimeDependencyContext, scope: NativeWebhookScope) -> OperationEndpointApproval? {
        guard enabled, scopes.contains(scope), context.baseURL.absoluteString.utf8.elementsEqual(endpoints.baseURL.absoluteString.utf8),
              context.session.namespace.utf8.elementsEqual(endpoints.namespace.utf8),
              context.session.accountID == endpoints.accountID else { return nil }
        return endpoints
    }
    func allowsOwner(_ owner: String, context: RuntimeDependencyContext) -> Bool {
        scopes.contains { $0.ownerID.rawValue == owner && approval(for: context, scope: $0) != nil }
    }
}

@MainActor enum NativeWebhookNormalRuntime {
    /// Both context lookup and every original operation recheck the same configuration.
    /// Removal, revision replacement and account/realm changes retire the old request fence.
    static func make(configuration: NativeWebhookRuntimeConfiguration,
                     currentConfiguration: @escaping () -> NativeWebhookRuntimeConfiguration?,
                     current: @escaping () -> RuntimeDependencyContext?, transport: any HTTPTransport,
                     onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) -> any NativeWebhookRuntimeFactory {
        let approval: NativeWebhookConfiguredRuntimeFactory.Approval = { context, scope in
            guard current() == context, currentConfiguration() == configuration else { return nil }
            return configuration.approval(for: context, scope: scope)
        }
        let source = NativeWebhookManagementContextSource(transport: transport, current: current,
            approval: approval, onUnauthorized: onUnauthorized)
        return NativeWebhookConfiguredRuntimeFactory(transport: transport,
            lookup: { context, scope in try await source.context(context, scope: scope) }, approval: approval)
    }
}
