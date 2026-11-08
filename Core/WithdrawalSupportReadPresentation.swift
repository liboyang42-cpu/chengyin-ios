import Foundation
import Observation

/// The existing account balance and settlement-stage reads, with independent outcomes.
/// Neither value is a points balance or authority to submit a withdrawal.
@MainActor @Observable public final class WithdrawalSupportReadPresentation {
    public struct Owner: Hashable {
        public let readerID: ObjectIdentifier
        public let scope: WalletCommerceScope?
        public let configured: Bool
        @MainActor public init(reader: WalletCommerceReader) {
            readerID = ObjectIdentifier(reader); scope = reader.scope; configured = reader.isConfigured
        }
    }
    public enum Failure: Equatable { case login, unavailable, retryable }
    public struct Snapshot {
        public fileprivate(set) var balance: WithdrawalBalance?
        public fileprivate(set) var stages: WalletFundsStages?
        public fileprivate(set) var balanceFailure: Failure?
        public fileprivate(set) var stagesFailure: Failure?
        public fileprivate(set) var balanceLoading = false
        public fileprivate(set) var stagesLoading = false
    }
    private var owner: Owner?
    private var value = Snapshot()
    private var active = false
    private var generation = UUID()
    @ObservationIgnored private var source: WalletCommerceReader?
    public init() {}
    public func isActive(for current: Owner) -> Bool { active && owner == current }
    public func snapshot(for current: Owner) -> Snapshot { isActive(for: current) ? value : Snapshot() }
    public func activate(reader: WalletCommerceReader) {
        let current = Owner(reader: reader)
        if !active || owner != current { value = Snapshot(); generation = UUID(); owner = current }
        source = reader; active = true
    }
    public func deactivate() {
        active = false; generation = UUID(); owner = nil; source = nil; value = Snapshot()
    }
    public func reload(reader: WalletCommerceReader) async {
        guard !Task.isCancelled, active, source === reader else { return }
        let current = Owner(reader: reader)
        guard owner == current else { return }
        let ticket = UUID(); generation = ticket; value = Snapshot()
        guard let scope = current.scope else { deny(.login); return }
        guard current.configured else { deny(.unavailable); return }
        value.balanceLoading = true; value.stagesLoading = true
        do {
            try Task.checkCancellation()
            let result = try await reader.read { try await $0.withdrawalBalance(memberID: scope.accountID, token: $1) }
            try Task.checkCancellation()
            guard accepts(ticket, owner: current, reader: reader) else { return }
            value.balance = result; value.balanceLoading = false
        } catch {
            guard accepts(ticket, owner: current, reader: reader) else { return }
            if error is CancellationError || Task.isCancelled { stopLoading(); return }
            let issue = Self.failure(error)
            if issue == .login { deny(.login); return } // No sibling dispatch after a known 401.
            value.balanceFailure = issue; value.balanceLoading = false
        }
        do {
            try Task.checkCancellation()
            guard accepts(ticket, owner: current, reader: reader) else { return }
            let result = try await reader.read { try await $0.stages(token: $1) }
            try Task.checkCancellation()
            guard accepts(ticket, owner: current, reader: reader) else { return }
            value.stages = result; value.stagesLoading = false
        } catch {
            guard accepts(ticket, owner: current, reader: reader) else { return }
            if error is CancellationError || Task.isCancelled { stopLoading(); return }
            let issue = Self.failure(error)
            if issue == .login { deny(.login); return } // Retire a successful private sibling too.
            value.stagesFailure = issue; value.stagesLoading = false
        }
    }
    private func accepts(_ ticket: UUID, owner: Owner, reader: WalletCommerceReader) -> Bool {
        isActive(for: owner) && generation == ticket && source === reader && owner == Owner(reader: reader)
    }
    private func stopLoading() { value.balanceLoading = false; value.stagesLoading = false }
    private func deny(_ failure: Failure) {
        value = Snapshot(); value.balanceFailure = failure; value.stagesFailure = failure
    }
    private static func failure(_ error: Error) -> Failure {
        if error as? APIError == .unauthorized { return .login }
        if error as? APIError == .notConfigured || error as? WalletCommerceSafetyError == .unavailable { return .unavailable }
        return .retryable
    }
}
