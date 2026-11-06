import Foundation
import Observation

public struct MemberScoreReadPresentation: Equatable { fileprivate let id: UUID }
public struct MemberScoreReadIntent: Equatable {
    fileprivate let owner: MemberScoreReadPresentation
    fileprivate let generation: UInt64
}
/// A selected original record is tied to the exact client, never a replacement account.
public struct MemberScoreAppealSelection: Identifiable, Hashable {
    public let id = UUID()
    public let row: MemberScoreAppealRow
    public let client: MemberScoreAppealListClient
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    fileprivate init(row: MemberScoreAppealRow, client: MemberScoreAppealListClient) { self.row = row; self.client = client }
}
@MainActor @Observable public final class MemberScoreAppealReadCoordinator {
    public let client: MemberScoreAppealListClient
    private var owner: MemberScoreReadPresentation?
    private var generation: UInt64 = 0
    private var active = false
    private var filter: MemberScoreAppealFilter = .all
    private var originalRow: MemberScoreAppealRow?
    private var storedRows: [MemberScoreAppealRow] = []
    private var storedDetail: MemberScoreAppealDetail?
    private var storedReputation: MemberScoreReputation?
    private var storedFailure: MemberScoreListFailure?
    private var storedReputationUnavailable = false
    private var storedLoaded = false
    private var storedBusy = false
    private var page = 0
    private var more = false
    public var isCurrent: Bool { active && client.isCurrent }
    public var rows: [MemberScoreAppealRow] { isCurrent ? storedRows : [] }
    public var detail: MemberScoreAppealDetail? { isCurrent ? storedDetail : nil }
    public var detailRow: MemberScoreAppealRow? { isCurrent ? originalRow : nil }
    public var reputation: MemberScoreReputation? { isCurrent ? storedReputation : nil }
    public var reputationUnavailable: Bool { isCurrent && storedReputationUnavailable }
    public var failure: MemberScoreListFailure? { isCurrent ? storedFailure : nil }
    public var loaded: Bool { isCurrent && storedLoaded }
    public var busy: Bool { isCurrent && storedBusy }
    public var hasMore: Bool { isCurrent && more }
    public init(client: MemberScoreAppealListClient) { self.client = client }
    public func beginList(filter: MemberScoreAppealFilter = .all) -> MemberScoreReadPresentation {
        retire(); self.filter = filter; return begin()
    }
    public func beginDetail(_ row: MemberScoreAppealRow) -> MemberScoreReadPresentation {
        retire(); originalRow = row; return begin()
    }
    private func begin() -> MemberScoreReadPresentation { let value = MemberScoreReadPresentation(id: UUID()); owner = value; active = true; return value }
    public func capture(_ value: MemberScoreReadPresentation) -> MemberScoreReadIntent? {
        guard isCurrent, owner == value, !Task.isCancelled else { return nil }
        return .init(owner: value, generation: generation)
    }
    public func accepts(_ intent: MemberScoreReadIntent) -> Bool {
        !Task.isCancelled && isCurrent && owner == intent.owner && generation == intent.generation
    }
    public func end(_ value: MemberScoreReadPresentation) { guard owner == value else { return }; retire() }
    public func retire() {
        generation &+= 1; active = false; owner = nil; originalRow = nil
        storedRows = []; storedDetail = nil; storedReputation = nil; storedFailure = nil
        storedReputationUnavailable = false; storedLoaded = false; storedBusy = false; page = 0; more = false
    }
    public func select(_ row: MemberScoreAppealRow, intent: MemberScoreReadIntent) -> MemberScoreAppealSelection? {
        guard accepts(intent), !storedBusy, storedRows.contains(row), row.canReadSession, client.allows(.sessionDetail) else { return nil }
        return .init(row: row, client: client)
    }
    public func loadList(more next: Bool = false, intent: MemberScoreReadIntent) async {
        guard accepts(intent), !storedBusy, originalRow == nil, !next || more else { return }
        generation &+= 1; let stamp = generation
        let target = next ? page + 1 : 1
        storedBusy = true; storedFailure = nil
        if !next { storedRows = []; storedLoaded = false; page = 0; more = false; storedReputation = nil; storedReputationUnavailable = false }
        defer { if generation == stamp { storedBusy = false } }
        do {
            let result = try await client.list(page: target, filter: filter)
            guard current(stamp) else { return }
            if next {
                // Offset pagination is not a frozen snapshot. A repeated key updates that record, not another row.
                for row in result.rows {
                    if let index = storedRows.firstIndex(where: { $0.id == row.id }) { storedRows[index] = row }
                    else { storedRows.append(row) }
                }
            } else { storedRows = result.rows }
            page = target; more = !result.rows.isEmpty && target < MemberScoreReadRoute.maximumPage && target * MemberScoreReadRoute.pageSize < result.total
            storedLoaded = true
        } catch { if current(stamp) { storedFailure = error as? MemberScoreListFailure ?? .unavailable } }
        guard !next, current(stamp) else { return }
        // Independent optional read. Failure never yields a normal reputation or blocks list recovery.
        guard client.allows(.reputation) else { storedReputationUnavailable = true; return }
        do {
            let value = try await client.reputation()
            guard current(stamp) else { return }; storedReputation = value
        } catch { if current(stamp) { storedReputation = nil; storedReputationUnavailable = true } }
    }
    public func loadDetail(intent: MemberScoreReadIntent) async {
        guard accepts(intent), !storedBusy, let row = originalRow else { return }
        generation &+= 1; let stamp = generation; storedBusy = true; storedFailure = nil; storedDetail = nil
        defer { if generation == stamp { storedBusy = false } }
        do { let value = try await client.detail(row); guard current(stamp) else { return }; storedDetail = value }
        catch { if current(stamp) { storedFailure = error as? MemberScoreListFailure ?? .unavailable } }
    }
    private func current(_ stamp: UInt64) -> Bool { stamp == generation && isCurrent && !Task.isCancelled }
}
