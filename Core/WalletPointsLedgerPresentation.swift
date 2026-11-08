import Foundation
import Observation

/// Points facts only. A row's afterPoints is never an authoritative current balance.
public struct WalletPointsLedgerEntry: Equatable {
    public let direction: WalletDirection
    public let signedChange: String?
    public let afterPoints: WalletAmount?
    public let reason: String?
    public let recordedTime: String?
    public init(row: WalletLedgerRow) {
        if let type = row.changeType {
            direction = type == 1 ? .income : type == 2 ? .expense : .unknown
        } else if let points = row.changePoints, points.value != 0 {
            direction = points.value < 0 ? .expense : .income
        } else { direction = .unknown }
        if let points = row.changePoints {
            let magnitude = NSDecimalNumber(decimal: points.value < 0 ? -points.value : points.value).stringValue
            if points.value == 0 { signedChange = "0" }
            else {
                switch direction {
                case .income: signedChange = "+" + magnitude
                case .expense: signedChange = "−" + magnitude
                case .unknown: signedChange = points.text
                }
            }
        } else { signedChange = nil }
        afterPoints = row.afterPoints
        reason = Self.nonblank(row.changeReason)
        // Preserve source time verbatim: the contract supplies no timezone to infer.
        recordedTime = Self.nonblank(row.createTime)
    }
    private static func nonblank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// Presentation lifetime layered over the unchanged reader and endpoint contracts.
/// Every displayed value, including errors and loading, belongs to an exact owner.
@MainActor @Observable public final class WalletPointsLedgerPresentation {
    public struct Owner: Hashable {
        public let readerID: ObjectIdentifier
        public let scope: WalletCommerceScope?
        public let configured: Bool
        public let kindKey: String
        @MainActor public init(reader: WalletCommerceReader, kind: WalletLedgerKind) {
            readerID = ObjectIdentifier(reader); scope = reader.scope; configured = reader.isConfigured
            switch kind {
            case .points: kindKey = "points"
            case .assetPoints: kindKey = "assetPoints"
            case .balance: kindKey = "balance"
            case .income(let filter): kindKey = "income:" + filter.rawValue
            }
        }
    }
    public enum Failure: Equatable { case login, unavailable, retryable }
    public struct Snapshot {
        public fileprivate(set) var rows: [WalletLedgerRow] = []
        public fileprivate(set) var hasMore = true
        public fileprivate(set) var isLoading = false
        public fileprivate(set) var loaded = false
        public fileprivate(set) var failure: Failure?
    }
    private var owner: Owner?
    private var value = Snapshot()
    private var generation = UUID()
    private var nextPage = 1
    public init() {}
    public func snapshot(for current: Owner) -> Snapshot { owner == current ? value : Snapshot() }
    public func cancel() { generation = UUID(); value.isLoading = false }
    private func reset(to current: Owner) {
        generation = UUID(); owner = current; value = Snapshot(); nextPage = 1
    }
    public func load(reader: WalletCommerceReader, kind: WalletLedgerKind, refresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        let current = Owner(reader: reader, kind: kind)
        if refresh || owner != current { reset(to: current) }
        guard !value.isLoading, value.hasMore else { return }
        let captured = generation, pageNumber = nextPage
        value.isLoading = true; value.failure = nil
        do {
            let page = try await reader.read { try await $0.ledger(kind, page: pageNumber, token: $1) }
            try Task.checkCancellation()
            guard captured == generation, current == Owner(reader: reader, kind: kind) else { return }
            var seen = Set(value.rows.map(\.id))
            let additional = page.rows.filter { seen.insert($0.id).inserted }
            if pageNumber > 1 && !page.rows.isEmpty && additional.isEmpty { throw APIError.malformedResponse }
            value.rows += additional; value.loaded = true
            value.hasMore = page.hasMore(loadedCount: value.rows.count); nextPage += 1
        } catch {
            guard captured == generation, current == Owner(reader: reader, kind: kind) else { return }
            if error is CancellationError || Task.isCancelled { value.isLoading = false; return }
            if (error as? APIError) == .unauthorized { value.failure = .login }
            else if (error as? APIError) == .notConfigured || (error as? WalletCommerceSafetyError) == .unavailable { value.failure = .unavailable }
            else { value.failure = .retryable }
        }
        value.isLoading = false
    }
}
