import Foundation
import Observation

/// An in-memory, owner-scoped presentation of one confirmed server record.
/// `objectID` is a topic only for routes; neither record IDs nor POI/stamp IDs are route IDs.
public struct RoamMonthlyRecapPresentation: Equatable, Identifiable {
    public let id: UUID
    public let record: RoamRecapRecord
    public let month: String
    public let kind: RoamRecapKind
    public let owner: RoamExperienceIdentity
    public var topicID: String? { kind == .routes ? record.objectID : nil }
}

/// Keeps selection and the exact continuation through detail/back and retry. No private disk cache,
/// local completion inference, new endpoint or authorization is introduced.
@MainActor @Observable public final class RoamMonthlyRecapCoordinator {
    public private(set) var month: String
    public private(set) var kind: RoamRecapKind = .routes
    public private(set) var page: RoamMonthlyRecapPage?
    public private(set) var error: Error?
    public private(set) var isLoading = false
    public private(set) var presentation: RoamMonthlyRecapPresentation?
    private let reader: (any RoamPassportToolsReading)?
    private let readScope: UUID?
    private let now: () -> Date
    private var owner: RoamExperienceIdentity?
    private var generation: UInt64 = 0
    private var attempted: RoamMonthlyRecapQuery?
    private var visibleBeforeID: String?

    public init(reader: (any RoamPassportToolsReading)?, now: (() -> Date)? = nil) {
        self.reader = reader
        readScope = (reader as? RoamPassportToolsSessionReader)?.readScope
        let clock: () -> Date = now ?? {
            reader?.isOfflineExample == true
                ? Date(timeIntervalSince1970: TimeInterval(RoamPassportToolsFixtureReader.asOfMs) / 1000) : Date()
        }
        self.now = clock
        month = RoamShanghaiCalendar.month(now: clock())
        owner = reader?.identity
    }
    public var currentMonth: String { RoamShanghaiCalendar.month(now: now()) }
    public var canGoPrevious: Bool { month > "2000-01" && !isLoading }
    public var canGoNext: Bool { month < currentMonth && !isLoading }
    private var hasCurrentReadScope: Bool { readScope == (reader as? RoamPassportToolsSessionReader)?.readScope }
    public var isLive: Bool { owner != nil && reader?.identity == owner && reader?.isConfigured == true && hasCurrentReadScope }

    /// Entry/re-entry reauthorizes the visible page without losing the month, kind or cursor.
    public func activate() async {
        synchronizeAccess()
        guard !isLoading, presentation == nil else { return }
        await read(.init(month: month, kind: kind, beforeID: visibleBeforeID))
    }
    /// Explicit pull-to-refresh starts a new snapshot at the first page, retaining the filters.
    public func refresh() async {
        synchronizeAccess()
        // Keep the confirmed page and its cursor together until the first-page read succeeds.
        // A cancelled refresh leaves that old page usable for detail/back and reactivation.
        await read(.init(month: month, kind: kind))
    }
    public func retry() async {
        synchronizeAccess()
        guard !isLoading else { return }
        let query = attempted.flatMap { $0.month == month && $0.kind == kind ? $0 : nil }
            ?? .init(month: month, kind: kind, beforeID: visibleBeforeID)
        await read(query)
    }
    public func nextPage() async {
        synchronizeAccess()
        guard !isLoading, error == nil, let page, page.hasMore,
              let cursor = page.nextBeforeID, page.month == month, page.kind == kind else { return }
        await read(.init(month: month, kind: kind, beforeID: cursor))
    }
    public func select(month selected: String) async {
        synchronizeAccess()
        let query = RoamMonthlyRecapQuery(month: selected, kind: kind)
        guard selected != month, (try? query.validate(currentMonth: currentMonth)) != nil else { return }
        month = selected; visibleBeforeID = nil; page = nil
        await read(query)
    }
    public func shiftMonth(by delta: Int) async {
        guard let selected = RoamShanghaiCalendar.shift(month, by: delta) else { return }
        await select(month: selected)
    }
    public func select(kind selected: RoamRecapKind) async {
        synchronizeAccess()
        guard selected != kind else { return }
        kind = selected; visibleBeforeID = nil; page = nil
        await read(.init(month: month, kind: selected))
    }
    /// Disappearance is not a detail pop. Invalidate only in-flight reads, not the selection.
    public func suspend() { generation += 1; isLoading = false }

    public func synchronizeIdentity() {
        guard owner != reader?.identity else { return }
        generation += 1; owner = reader?.identity
        month = currentMonth; kind = .routes; page = nil; error = nil
        isLoading = false; presentation = nil; attempted = nil; visibleBeforeID = nil
    }
    /// Read approval can disappear without changing account or session epoch. Retire the
    /// private presentation, but keep filters and the attempted cursor for an explicit retry.
    public func synchronizeAccess() {
        synchronizeIdentity()
        if owner != nil, let reader, !reader.isConfigured || !hasCurrentReadScope { retireUnavailableAccess() }
    }
    private func retireUnavailableAccess() {
        generation += 1; page = nil; presentation = nil
        isLoading = false; error = APIError.notConfigured
    }
    @discardableResult public func open(_ record: RoamRecapRecord) -> Bool {
        synchronizeAccess()
        guard isLive, !isLoading, error == nil, presentation == nil, let owner,
              let page, page.month == month, page.kind == kind, page.items.contains(record) else { return false }
        presentation = .init(id: UUID(), record: record, month: month, kind: kind, owner: owner)
        return true
    }
    public func isCurrent(_ value: RoamMonthlyRecapPresentation) -> Bool {
        isLive && presentation == value && value.owner == owner && value.month == month && value.kind == kind
    }
    /// Only this exact detail's dismissal earns a reread. Covered child pages and old callbacks do not.
    public func completeReturn(_ value: RoamMonthlyRecapPresentation) async {
        synchronizeAccess()
        guard isCurrent(value) else { return }
        presentation = nil
        await read(.init(month: month, kind: kind, beforeID: visibleBeforeID))
    }
    private func read(_ query: RoamMonthlyRecapQuery) async {
        generation += 1; let ticket = generation
        presentation = nil; attempted = query; error = nil
        guard let reader else { page = nil; isLoading = false; error = APIError.notConfigured; return }
        guard let captured = owner, captured == reader.identity else {
            page = nil; isLoading = false; error = APIError.unauthorized; return
        }
        guard reader.isConfigured, hasCurrentReadScope else { retireUnavailableAccess(); return }
        isLoading = true
        defer { if ticket == generation { isLoading = false } }
        do {
            try query.validate(currentMonth: currentMonth)
            let result = try await reader.monthlyRecap(query)
            guard ticket == generation else { return }
            guard captured == reader.identity else { synchronizeIdentity(); return }
            guard reader.isConfigured, hasCurrentReadScope else { retireUnavailableAccess(); return }
            try Task.checkCancellation()
            guard result.month == query.month, result.kind == query.kind,
                  result.sourceBeforeID == query.beforeID else { throw APIError.malformedResponse }
            // Each response replaces the page. Older titles were not reauthorized by this response.
            page = result; visibleBeforeID = query.beforeID
        } catch {
            guard ticket == generation else { return }
            guard captured == reader.identity else { synchronizeIdentity(); return }
            // Runtime readers intentionally cancel a response after approval is withdrawn.
            // That is not ordinary view cancellation and must not preserve private rows.
            guard reader.isConfigured, hasCurrentReadScope else { retireUnavailableAccess(); return }
            if error is CancellationError { return }
            page = nil; self.error = error
        }
    }
}
