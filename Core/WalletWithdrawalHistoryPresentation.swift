import Foundation
import Observation

/// A single returned application-history batch, never an account balance or payout receipt.
@MainActor @Observable public final class WalletWithdrawalHistoryPresentation {
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
        public fileprivate(set) var page: WalletPage<WalletWithdrawalRecord>?
        public fileprivate(set) var failure: Failure?
        public fileprivate(set) var isLoading = false
        public var sourceLimited: Bool {
            guard let page, let total = page.total else { return false }
            return total > page.rows.count
        }
    }
    private var owner: Owner?
    private var value = Snapshot()
    private var active = false
    private var generation = UUID()
    @ObservationIgnored private var source: WalletCommerceReader?
    public init() {}
    public func snapshot(for current: Owner) -> Snapshot { active && owner == current ? value : Snapshot() }
    public func activate(reader: WalletCommerceReader) {
        let current = Owner(reader: reader)
        if !active || owner != current { value = Snapshot(); generation = UUID(); owner = current }
        source = reader; active = true
    }
    public func deactivate() {
        active = false; generation = UUID(); owner = nil; source = nil; value = Snapshot()
    }
    /// Always reread the source's original nonpaged endpoint. No append or guessed cursor.
    public func reload(reader: WalletCommerceReader) async {
        guard !Task.isCancelled, active, source === reader else { return }
        let current = Owner(reader: reader)
        guard current == owner else { return }
        let ticket = UUID(); generation = ticket; value = Snapshot(); value.isLoading = true
        do {
            let page = try await reader.read { try await $0.withdrawals(token: $1) }
            try Task.checkCancellation()
            guard accepts(ticket, current: current, reader: reader) else { return }
            // Ambiguous record identity must not silently choose one financial state.
            guard Set(page.rows.map(\.id)).count == page.rows.count,
                  page.total.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
            value.page = page
        } catch {
            guard accepts(ticket, current: current, reader: reader) else { return }
            if error is CancellationError || Task.isCancelled { value.isLoading = false; return }
            if error as? APIError == .unauthorized { value.failure = .login }
            else if error as? APIError == .notConfigured || error as? WalletCommerceSafetyError == .unavailable { value.failure = .unavailable }
            else { value.failure = .retryable }
        }
        value.isLoading = false
    }
    private func accepts(_ ticket: UUID, current: Owner, reader: WalletCommerceReader) -> Bool {
        active && generation == ticket && current == owner && source === reader && current == Owner(reader: reader)
    }
}

/// Preserve only source record facts and the already masked account projection.
public struct WalletWithdrawalHistoryEntry {
    public let amount: WalletAmount
    public let currency: String?
    public let statusKey: String
    public let recordedTime: String?
    public let maskedAccount: String?
    public init(record: WalletWithdrawalRecord) {
        amount = record.amount; currency = Self.nonblank(record.currency); statusKey = record.statusKey
        recordedTime = Self.nonblank(record.createTime); maskedAccount = Self.nonblank(record.maskedAccount)
    }
    private static func nonblank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
