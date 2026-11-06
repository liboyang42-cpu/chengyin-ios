import Foundation
import Observation

/// Reviewed, bounded composition collection ONLY. Providers return existing exact grants; this never issues them.
/// Nil production injection stays disabled. A URL, role, server writeApproved or login is not this review.
@MainActor @Observable public final class CityActionBudgetRuntimeGrants {
    public let context: RuntimeDependencyContext
    public let revision: UInt64
    public let regionID: String
    public let expiresAt: Date
    public private(set) var isRevoked = false
    public let scope: CityActionBudgetScope
    private let stateProvider: (CityActionBudgetScope) -> CityActionBudgetReadGrant?
    private let commandProvider: (CityActionBudgetScope) -> CityActionBudgetCommandGrant?
    private let receiptProvider: (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, revision: UInt64, regionID: String, expiresAt: Date,
                state: @escaping (CityActionBudgetScope) -> CityActionBudgetReadGrant? = { _ in nil },
                command: @escaping (CityActionBudgetScope) -> CityActionBudgetCommandGrant? = { _ in nil },
                receipt: @escaping (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? = { _ in nil }) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.role == context.session.role, !context.role.isEmpty,
              CityParticipationCommand.id(regionID), duration.isFinite, duration > 0, duration <= 86400 else { throw APIError.invalidConfiguration }
        self.context = context; self.revision = revision; self.regionID = regionID; self.expiresAt = expiresAt
        scope = try .init(market:context.market,baseURL:context.baseURL,namespace:context.session.namespace,
                          accountID:context.session.accountID,epoch:context.session.epoch,token:context.session.token)
        stateProvider = state; commandProvider = command; receiptProvider = receipt
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
    public func state(_ requested: CityActionBudgetScope) -> CityActionBudgetReadGrant? {
        guard live, requested == scope else { return nil }
        return stateProvider(requested)
    }
    public func command(_ requested: CityActionBudgetScope) -> CityActionBudgetCommandGrant? {
        guard live, requested == scope else { return nil }; return commandProvider(requested)
    }
    public func receipt(_ reference: CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? {
        guard live, reference.session == scope.session, reference.domain == .actionBudget else { return nil }
        return receiptProvider(reference)
    }
}
