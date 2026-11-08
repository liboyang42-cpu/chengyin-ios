import Foundation
import Observation

/// Account assets entry only. Stages remain money, never a points balance.
/// Uses the existing reader; its failure does not remove the separate ledger links.
@MainActor @Observable public final class WalletAssetsReadPresentation {
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
        public fileprivate(set) var stages: WalletFundsStages?
        public fileprivate(set) var failure: Failure?
        public fileprivate(set) var isLoading = false
    }
    private var owner: Owner?
    private var value = Snapshot()
    private var generation = UUID()
    private var active = false
    // Retain the exact source while it owns values, avoiding ObjectIdentifier reuse.
    @ObservationIgnored private var source: WalletCommerceReader?
    public init() {}
    public func snapshot(for current: Owner) -> Snapshot {
        active && owner == current ? value : Snapshot()
    }
    public func activate(reader: WalletCommerceReader) {
        let current = Owner(reader: reader)
        if !active || owner != current {
            generation = UUID(); value = Snapshot(); owner = current
        }
        source = reader; active = true
    }
    public func deactivate() {
        active = false; generation = UUID(); owner = nil; source = nil; value = Snapshot()
    }
    /// Refresh replaces any older attempt and removes its amounts/errors immediately.
    /// A stale queued action cannot reassign ownership or revive a disappeared entry.
    public func reload(reader: WalletCommerceReader) async {
        guard !Task.isCancelled, active, source === reader else { return }
        let current = Owner(reader: reader)
        guard owner == current else { return }
        let ticket = UUID(); generation = ticket
        value = Snapshot(); value.isLoading = true
        do {
            let stages = try await reader.read { try await $0.stages(token: $1) }
            try Task.checkCancellation()
            guard accepts(ticket, current: current, reader: reader) else { return }
            value.stages = stages
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
        active && generation == ticket && owner == current && source === reader && current == Owner(reader: reader)
    }
}
