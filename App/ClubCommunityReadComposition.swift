import Foundation

/// Composes read-only `ClubCommunityService` and `ClubCommunityReadRuntime` instances from
/// an explicitly issued `ClubCommunityReadApproval` without ever enabling write permissions.
/// When no valid read approval matches the current `RuntimeDependencyContext`, falls back to
/// the dormant non-network service (`CommunityDormantHTTPTransport`).
@MainActor
enum ClubCommunityReadComposition {
    static func makeService(
        currentContext: @escaping () -> RuntimeDependencyContext?,
        selectApproval: @escaping (RuntimeDependencyContext) -> ClubCommunityReadApproval?,
        currentSession: @escaping () throws -> ClubCommunitySession,
        transport: @escaping () -> any HTTPTransport,
        fallback: ClubCommunityService
    ) -> ClubCommunityService {
        guard let context = currentContext(),
              let session = try? currentSession(),
              session.identity.accountID == context.session.accountID,
              session.identity.epoch == context.session.epoch,
              session.token == context.session.token,
              let approval = selectApproval(context),
              approval.matches(context) else {
            return fallback
        }
        let runtimeTransport = ClubCommunityReadRuntimeTransport(
            transport: transport(),
            currentContext: currentContext,
            selectApproval: selectApproval,
            currentSession: currentSession
        )
        // Uses the 2-argument read-only initializer (`allowsInjectedWrites == false`).
        // Read approval never opens write or upload permissions.
        return ClubCommunityService(baseURL: context.baseURL, transport: runtimeTransport)
    }

    static func makeRuntime(
        currentContext: @escaping () -> RuntimeDependencyContext?,
        selectApproval: @escaping (RuntimeDependencyContext) -> ClubCommunityReadApproval?,
        currentSession: @escaping () throws -> ClubCommunitySession,
        transport: @escaping () -> any HTTPTransport,
        fallback: ClubCommunityService
    ) -> ClubCommunityReadRuntime {
        ClubCommunityReadRuntime(
            makeService: {
                makeService(
                    currentContext: currentContext,
                    selectApproval: selectApproval,
                    currentSession: currentSession,
                    transport: transport,
                    fallback: fallback
                )
            },
            currentSession: currentSession,
            currentContext: currentContext,
            selectApproval: selectApproval
        )
    }
}

extension AppSession {
    func selectClubCommunityReadApproval(_ context: RuntimeDependencyContext) -> ClubCommunityReadApproval? {
        guard let current = clubCommunityRuntimeContext,
              ContentDraftContextFence.matches(context, current),
              let approval = clubCommunityReadApprovalSelector(context),
              approval.matches(context) else {
            return nil
        }
        return approval
    }

    func configureClubCommunityReadComposition(
        approval: @escaping (RuntimeDependencyContext) -> ClubCommunityReadApproval?,
        transport: (any HTTPTransport)? = nil
    ) {
        clubCommunityReadApprovalSelector = approval
        clubCommunityTransportOverride = transport
    }

    func resolvedClubCommunityService(fallback: ClubCommunityService) -> ClubCommunityService {
        ClubCommunityReadComposition.makeService(
            currentContext: { [weak self] in self?.clubCommunityRuntimeContext },
            selectApproval: { [weak self] context in self?.selectClubCommunityReadApproval(context) },
            currentSession: { [weak self] in
                guard let self else { throw ClubCommunityFailure.unavailable }
                return try self.currentClubCommunitySession()
            },
            transport: { [weak self] in
                self?.clubCommunityRuntimeTransport ?? CommunityDormantHTTPTransport()
            },
            fallback: fallback
        )
    }

    func makeClubCommunityReadRuntime() -> ClubCommunityReadRuntime {
        let fallback = ClubCommunityService(
            dormantBaseURL: URL(string: "https://disabled.invalid")!,
            transport: CommunityDormantHTTPTransport()
        )
        return ClubCommunityReadComposition.makeRuntime(
            currentContext: { [weak self] in self?.clubCommunityRuntimeContext },
            selectApproval: { [weak self] context in self?.selectClubCommunityReadApproval(context) },
            currentSession: { [weak self] in
                guard let self else { throw ClubCommunityFailure.unavailable }
                return try self.currentClubCommunitySession()
            },
            transport: { [weak self] in
                self?.clubCommunityRuntimeTransport ?? CommunityDormantHTTPTransport()
            },
            fallback: fallback
        )
    }
}
