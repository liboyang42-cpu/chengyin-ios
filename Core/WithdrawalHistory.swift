import Foundation
import Observation

/// Read-only withdrawal history in the mini-program's presentation contract
/// (components/cy/scene-member-withdraw-history). Unlike `WalletWithdrawalRecord`, one
/// unexpected row never fails the table: unknown status reads "status unconfirmed" and a
/// missing or non-numeric `receivedAmount` reads as an explicit dash, never an invented zero.
public struct WithdrawalHistoryRow: Decodable, Equatable {
    public enum Status: String, Equatable { case processing, succeeded, failed, unknown }
    public let id: Int?
    public let status: Status
    /// Server `receivedAmount` (actual amount credited); only a finite, non-negative JSON number.
    public let receivedAmount: Decimal?
    public let createTime: String?
    private enum CodingKeys: String, CodingKey { case id, status, receivedAmount, createTime }
    public init(id: Int?, status: Status, receivedAmount: Decimal?, createTime: String?) {
        self.id = id; self.status = status; self.receivedAmount = receivedAmount; self.createTime = createTime
    }
    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init(id: nil, status: .unknown, receivedAmount: nil, createTime: nil); return
        }
        let id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? nil
        let raw = (try? c.decodeIfPresent(Int.self, forKey: .status)) ?? nil
        let amount = (try? c.decodeIfPresent(Decimal.self, forKey: .receivedAmount)) ?? nil
        let time = (try? c.decodeIfPresent(String.self, forKey: .createTime)) ?? nil
        self.init(id: id, status: Self.status(raw), receivedAmount: amount.flatMap { $0.isNaN || $0 < 0 ? nil : $0 },
                  createTime: time.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
    }
    /// Source mapping: 0 processing, 1 succeeded, 2 failed and refunded; anything else is unconfirmed.
    public static func status(_ raw: Int?) -> Status {
        switch raw {
        case 0: return .processing
        case 1: return .succeeded
        case 2: return .failed
        default: return .unknown
        }
    }
    public var statusKey: String { "withdrawal.history.status." + status.rawValue }
    /// Two fixed decimals with a leading minus, matching the source; nil renders as a dash.
    public var amountText: String? {
        guard let receivedAmount else { return nil }
        var value = receivedAmount, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        guard let text = formatter.string(from: NSDecimalNumber(decimal: rounded)) else { return nil }
        return "-" + text
    }
}

public struct WithdrawalHistoryPage: Equatable {
    public let rows: [WithdrawalHistoryRow]
    /// Present only when the server returns a table; the current source returns a bare list.
    public let total: Int?
    public init(rows: [WithdrawalHistoryRow], total: Int?) { self.rows = rows; self.total = total }
    public var mayHaveMore: Bool { total.map { $0 > rows.count } ?? false }
    /// `data` must be an array, `{rows}` or `{list}`; any other shape is a load failure, not empty.
    public static func decode(envelope bytes: Data) throws -> WithdrawalHistoryPage {
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        return WithdrawalHistoryPage(rows: envelope.rows, total: envelope.total)
    }
    private struct Envelope: Decodable {
        let rows: [WithdrawalHistoryRow]
        let total: Int?
        enum CodingKeys: String, CodingKey { case data }
        enum TableKeys: String, CodingKey { case rows, list, total }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let list = try? c.decode([WithdrawalHistoryRow].self, forKey: .data) { rows = list; total = nil; return }
            let table = try c.nestedContainer(keyedBy: TableKeys.self, forKey: .data)
            if let list = try? table.decode([WithdrawalHistoryRow].self, forKey: .rows) { rows = list }
            else { rows = try table.decode([WithdrawalHistoryRow].self, forKey: .list) }
            let count = (try? table.decodeIfPresent(Int.self, forKey: .total)) ?? (try? table.decodeIfPresent(String.self, forKey: .total)).flatMap { Int($0) }
            total = count.flatMap { $0 >= 0 ? $0 : nil }
        }
    }
}

/// Session-scoped history screen state. Reads go through the existing `WalletCommerceReader`,
/// so the reviewed endpoint approval and stale-owner fences stay authoritative.
@available(macOS 14.0, *)
@MainActor @Observable public final class WithdrawalHistoryCoordinator {
    public enum Phase: Equatable { case idle, loading, ready, empty, login, denied, unavailable, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var page: WithdrawalHistoryPage?
    private let reader: WalletCommerceReader
    private var generation = 0
    private var loadedScope: WalletCommerceScope?
    public init(reader: WalletCommerceReader) { self.reader = reader }
    /// Rows are visible only while they still belong to the reader's current owner.
    public var rows: [WithdrawalHistoryRow] { loadedScope != nil && loadedScope == reader.scope ? page?.rows ?? [] : [] }
    public var canRetry: Bool { phase == .failed || phase == .login }
    public func cancel() { generation += 1; if phase == .loading { phase = .idle } }
    public func load() async {
        generation += 1; let ticket = generation
        let scope = reader.scope
        page = nil; loadedScope = nil
        guard reader.isConfigured else { phase = .unavailable; return }
        guard scope != nil else { phase = .login; return }
        phase = .loading
        do {
            let value = try await reader.read { try await $0.withdrawalHistory(token: $1) }
            guard ticket == generation, scope == reader.scope else { return }
            page = value; loadedScope = scope; phase = value.rows.isEmpty ? .empty : .ready
        } catch {
            guard ticket == generation else { return }
            if error is CancellationError { phase = .idle; return }
            phase = Self.phase(for: error)
        }
    }
    public static func phase(for error: Error) -> Phase {
        switch error {
        case APIError.unauthorized, APIError.httpStatus(401), APIError.businessCode(401): return .login
        case APIError.httpStatus(403), APIError.businessCode(403): return .denied
        case APIError.notConfigured, WalletCommerceSafetyError.unavailable: return .unavailable
        case WalletCommerceSafetyError.staleSession: return .idle
        default: return .failed
        }
    }
}
