import Foundation

/// Default nil composition. Host issuance is separate from read and image-upload leases.
@MainActor enum ClubPostOriginalComposition {
    static func makeService(
        currentContext: @escaping () -> RuntimeDependencyContext?,
        selectApproval: @escaping (RuntimeDependencyContext) -> ClubPostOriginalApproval?,
        currentSession: () throws -> ClubCommunitySession,
        transport: () -> any HTTPTransport
    ) -> ClubPostOriginalService? {
        guard let context = currentContext(), let session = try? currentSession(),
              session.identity.accountID == context.session.accountID,
              session.identity.epoch == context.session.epoch, session.token == context.session.token,
              let approval = selectApproval(context), approval.matches(context) else { return nil }
        let fenced = ClubPostOriginalRuntimeTransport(transport: transport(), captured: context,
            approval: approval, current: currentContext, select: selectApproval)
        return ClubPostOriginalService(baseURL: context.baseURL, transport: fenced,
            readsEnabled: true, writesEnabled: approval.writes)
    }
}

extension AppSession {
    func resolvedClubPostOriginalService() -> ClubPostOriginalService? {
        ClubPostOriginalComposition.makeService(
            currentContext: { [weak self] in self?.clubCommunityRuntimeContext },
            selectApproval: { [weak self] context in self?.compositionClubPostOriginalApproval(context) },
            currentSession: { [weak self] in
                guard let self else { throw ClubCommunityFailure.unavailable }
                return try self.currentClubCommunitySession()
            },
            transport: { [weak self] in self?.clubCommunityRuntimeTransport ?? CommunityDormantHTTPTransport() }
        )
    }
}
