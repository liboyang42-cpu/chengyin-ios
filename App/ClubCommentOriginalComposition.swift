import Foundation

/// Default nil composition. Host issuance is separate from read and image-upload leases.
@MainActor enum ClubCommentOriginalComposition {
    static func makeService(
        currentContext: @escaping () -> RuntimeDependencyContext?,
        selectApproval: @escaping (RuntimeDependencyContext) -> ClubCommentOriginalApproval?,
        currentSession: () throws -> ClubCommunitySession,
        transport: () -> any HTTPTransport
    ) -> ClubCommentOriginalService? {
        guard let context = currentContext(), let session = try? currentSession(),
              session.identity.accountID == context.session.accountID,
              session.identity.epoch == context.session.epoch, session.token == context.session.token,
              let approval = selectApproval(context), approval.matches(context) else { return nil }
        let fenced = ClubCommentOriginalRuntimeTransport(transport: transport(), captured: context,
            approval: approval, current: currentContext, select: selectApproval)
        return ClubCommentOriginalService(baseURL: context.baseURL, transport: fenced,
            readsEnabled: true, writesEnabled: approval.writes)
    }
}

extension AppSession {
    func resolvedClubCommentOriginalService() -> ClubCommentOriginalService? {
        ClubCommentOriginalComposition.makeService(
            currentContext: { [weak self] in self?.clubCommunityRuntimeContext },
            selectApproval: { [weak self] context in self?.compositionClubCommentOriginalApproval(context) },
            currentSession: { [weak self] in
                guard let self else { throw ClubCommunityFailure.unavailable }
                return try self.currentClubCommunitySession()
            },
            transport: { [weak self] in self?.clubCommunityRuntimeTransport ?? CommunityDormantHTTPTransport() }
        )
    }
}
