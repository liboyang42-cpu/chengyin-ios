import Foundation
import Observation

public struct MemberReportProgressPresentation: Equatable { fileprivate let id: UUID }
public struct MemberReportProgressIntent: Equatable {
    fileprivate let owner: MemberReportProgressPresentation
    fileprivate let generation: UInt64
}
public struct MemberReportProgressSelection: Identifiable, Hashable {
    public let id = UUID()
    public let record: MemberReportProgressRecord
    public let reader: MemberReportProgressReader
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    fileprivate init(record: MemberReportProgressRecord, reader: MemberReportProgressReader) { self.record = record; self.reader = reader }
}
/// C6 returns one complete owner array. Display pages and filters never fabricate a server cursor.
@MainActor @Observable public final class MemberReportProgressCoordinator {
    public static let displayPageSize = 20
    public let reader: MemberReportProgressReader
    private var owner: MemberReportProgressPresentation?
    private var generation: UInt64 = 0
    private var active = false
    private var storedFilter: MemberReportProgressFilter = .all
    private var shown = MemberReportProgressCoordinator.displayPageSize
    private var allRecords: [MemberReportProgressRecord] = []
    private var originalRecord: MemberReportProgressRecord?
    private var detailBaseline: MemberReportProgressRecord?
    private var storedDetail: MemberReportProgressRecord?
    private var storedTaxonomy: MemberReportProgressTaxonomy?
    private var storedFailure: MemberReportProgressFailure?
    private var storedLoaded = false
    private var storedBusy = false
    public var isCurrent: Bool { active && reader.isCurrent }
    private var filtered: [MemberReportProgressRecord] {
        guard isCurrent else { return [] }
        return allRecords.filter { storedFilter == .all || (storedFilter == .decided ? $0.isDecided : !$0.isDecided) }
    }
    public var records: [MemberReportProgressRecord] { Array(filtered.prefix(shown)) }
    public var filter: MemberReportProgressFilter { isCurrent ? storedFilter : .all }
    public var hasMore: Bool { isCurrent && shown < filtered.count }
    public var detailRecord: MemberReportProgressRecord? { isCurrent ? originalRecord : nil }
    public var detail: MemberReportProgressRecord? { isCurrent ? storedDetail : nil }
    public var failure: MemberReportProgressFailure? { isCurrent ? storedFailure : nil }
    public var loaded: Bool { isCurrent && storedLoaded }
    public var busy: Bool { isCurrent && storedBusy }
    public func reasonLabel(for record: MemberReportProgressRecord) -> String? {
        isCurrent ? storedTaxonomy?.label(for: record) : nil
    }
    public init(reader: MemberReportProgressReader) { self.reader = reader }
    public func beginHistory(filter: MemberReportProgressFilter = .all) -> MemberReportProgressPresentation {
        retire(); storedFilter = filter; return begin()
    }
    public func beginDetail(_ record: MemberReportProgressRecord) -> MemberReportProgressPresentation {
        retire(); originalRecord = record; detailBaseline = record; return begin()
    }
    private func begin() -> MemberReportProgressPresentation {
        let value = MemberReportProgressPresentation(id: UUID()); owner = value; active = true; return value
    }
    public func capture(_ value: MemberReportProgressPresentation) -> MemberReportProgressIntent? {
        guard isCurrent, owner == value, !Task.isCancelled else { return nil }
        return .init(owner: value, generation: generation)
    }
    public func accepts(_ intent: MemberReportProgressIntent) -> Bool {
        !Task.isCancelled && isCurrent && owner == intent.owner && generation == intent.generation
    }
    public func end(_ value: MemberReportProgressPresentation) { guard owner == value else { return }; retire() }
    public func retire() {
        generation &+= 1; active = false; owner = nil; allRecords = []; originalRecord = nil; detailBaseline = nil
        storedDetail = nil; storedTaxonomy = nil; storedFailure = nil; storedLoaded = false; storedBusy = false
        shown = Self.displayPageSize
    }
    public func changeFilter(_ value: MemberReportProgressFilter, intent: MemberReportProgressIntent) {
        guard accepts(intent), !storedBusy, originalRecord == nil else { return }
        generation &+= 1; storedFilter = value; shown = Self.displayPageSize
    }
    public func showMore(intent: MemberReportProgressIntent) {
        guard accepts(intent), !storedBusy, originalRecord == nil, hasMore else { return }
        generation &+= 1; shown = min(shown + Self.displayPageSize, allRecords.count)
    }
    public func select(_ record: MemberReportProgressRecord, intent: MemberReportProgressIntent) -> MemberReportProgressSelection? {
        guard accepts(intent), !storedBusy, originalRecord == nil, records.contains(record), reader.allows(.detail) else { return nil }
        return .init(record: record, reader: reader)
    }
    public func loadHistory(intent: MemberReportProgressIntent) async {
        guard accepts(intent), !storedBusy, originalRecord == nil else { return }
        generation &+= 1; let stamp = generation
        storedBusy = true; storedFailure = nil; storedLoaded = false; allRecords = []; storedTaxonomy = nil; shown = Self.displayPageSize
        defer { if generation == stamp { storedBusy = false } }
        do {
            let result = try await reader.history()
            guard current(stamp) else { return }; allRecords = result; storedLoaded = true
        } catch {
            if current(stamp) { storedFailure = error as? MemberReportProgressFailure ?? .unavailable }
            return
        }
        await loadTaxonomy(stamp: stamp)
    }
    public func loadDetail(intent: MemberReportProgressIntent) async {
        guard accepts(intent), !storedBusy, let baseline = detailBaseline else { return }
        generation &+= 1; let stamp = generation; storedBusy = true; storedFailure = nil; storedDetail = nil; storedTaxonomy = nil
        defer { if generation == stamp { storedBusy = false } }
        do {
            let result = try await reader.detail(for: baseline)
            guard current(stamp) else { return }; storedDetail = result; detailBaseline = result
        } catch {
            if current(stamp) { storedFailure = error as? MemberReportProgressFailure ?? .unavailable }
            return
        }
        await loadTaxonomy(stamp: stamp)
    }
    private func loadTaxonomy(stamp: UInt64) async {
        guard current(stamp), reader.allows(.taxonomy) else { return }
        do { let result = try await reader.taxonomy(); guard current(stamp) else { return }; storedTaxonomy = result }
        catch {
            // Ordinary metadata failure uses a label fallback. Authentication denial revokes the lease in the reader.
            if current(stamp) { storedTaxonomy = nil }
        }
    }
    private func current(_ stamp: UInt64) -> Bool { stamp == generation && isCurrent && !Task.isCancelled }
}
