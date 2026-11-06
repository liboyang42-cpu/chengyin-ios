import Foundation
import Observation

/// Reviewed, bounded composition collection ONLY. Providers return existing exact grants; this never issues them.
/// Nil production injection stays disabled. A URL, role, server writeApproved or login is not this review.
@MainActor @Observable public final class CityParticipationRuntimeGrants {
    public let context: RuntimeDependencyContext
    public let revision: UInt64
    public let regionID: String
    public let expiresAt: Date
    public private(set) var isRevoked = false
    public let scope: CityParticipationCommandScope
    private let stateProvider: (CityParticipationReadScope) -> CityParticipationReadGrant?
    private let invitationProvider: (CityParticipationCommandScope, String, String) -> CityParticipationInvitationGrant?
    private let commandProvider: (CityParticipationCommandScope) -> CityParticipationCommandGrant?
    private let receiptProvider: (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant?
    private let approvalProvider: (@MainActor (CityParticipationCommand) async -> Bool)?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, revision: UInt64, regionID: String, expiresAt: Date,
                state: @escaping (CityParticipationReadScope) -> CityParticipationReadGrant? = { _ in nil },
                invitation: @escaping (CityParticipationCommandScope, String, String) -> CityParticipationInvitationGrant? = { _,_,_ in nil },
                command: @escaping (CityParticipationCommandScope) -> CityParticipationCommandGrant? = { _ in nil },
                receipt: @escaping (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? = { _ in nil },
                approve: (@MainActor (CityParticipationCommand) async -> Bool)? = nil) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.role == context.session.role, !context.role.isEmpty,
              CityParticipationCommand.id(regionID), duration.isFinite, duration > 0, duration <= 86400 else { throw APIError.invalidConfiguration }
        self.context = context; self.revision = revision; self.regionID = regionID; self.expiresAt = expiresAt
        scope = try .init(market:context.market,baseURL:context.baseURL,namespace:context.session.namespace,
                          accountID:context.session.accountID,epoch:context.session.epoch,token:context.session.token)
        stateProvider = state; invitationProvider = invitation; commandProvider = command; receiptProvider = receipt; approvalProvider = approve
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(max(0,min(duration,86400))*1_000_000_000)); try Task.checkCancellation() }
            catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext?, revision: UInt64, now: Date = Date()) -> Bool {
        guard !isRevoked, now < expiresAt, self.revision == revision, let current,
              current.role == current.session.role else { return false }
        return ContentDraftContextFence.matches(context,current) && context.session == current.session
    }
    private var live: Bool { !isRevoked && Date() < expiresAt }
    public func state(_ requested: CityParticipationReadScope) -> CityParticipationReadGrant? {
        guard live, requested.session == scope.session, requested.regionID == regionID else { return nil }
        return stateProvider(requested)
    }
    public func invitation(_ requested: CityParticipationCommandScope, region: String, code: String) -> CityParticipationInvitationGrant? {
        guard live, requested == scope, region == regionID else { return nil }
        return invitationProvider(requested,region,code)
    }
    public func command(_ requested: CityParticipationCommandScope) -> CityParticipationCommandGrant? {
        guard live, requested == scope else { return nil }; return commandProvider(requested)
    }
    public func receipt(_ reference: CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? {
        guard live, reference.session == scope.session, reference.domain == .participation else { return nil }
        return receiptProvider(reference)
    }
    public var approval: (@MainActor (RuntimeDependencyContext, UInt64, CityParticipationCommand) async -> Bool)? {
        guard let approvalProvider else { return nil }
        return { [weak self] context,revision,command in
            guard let self, self.matches(context,revision:revision), command.regionId == self.regionID else { return false }
            let approved = await approvalProvider(command)
            return approved && self.matches(context,revision:revision)
        }
    }
}
