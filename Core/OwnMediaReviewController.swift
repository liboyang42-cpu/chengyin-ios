import Foundation
import Observation

/// Owns only the existing owner-scoped media list read. No preview, retry-review,
/// upload, delete, or approval is created by opening this screen.
@MainActor @Observable public final class OwnMediaReviewController {
    public enum Phase: Equatable { case idle, loading, ready, signedOut, unavailable, denied, failed }
    public struct Access: Equatable {
        let scope: UUID
        let signedIn: Bool
        let available: Bool
    }
    private enum ReadPlan: Equatable { case refresh, more(before: Int64) }
    private let reader: any OwnMediaReading
    private let capturedScope: UUID
    private var storedRows: [OwnMediaAsset] = []
    private var cursor: Int64?
    private var storedPhase: Phase = .idle
    private var failedPlan: ReadPlan?
    private var visible = false
    private var foreground = false
    private var retired = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    public private(set) var loadingMore = false
    public private(set) var isLoading = false

    public init(reader: any OwnMediaReading) {
        self.reader = reader; capturedScope = reader.scope
    }
    /// Reading this also observes an independently revoked read approval.
    public var access: Access { .init(scope: reader.scope, signedIn: reader.isSignedIn, available: reader.isAvailable) }
    private var ownsAccess: Bool { !retired && reader.scope == capturedScope && reader.isSignedIn && reader.isAvailable }
    private var active: Bool { visible && foreground && ownsAccess }
    public var phase: Phase {
        if !reader.isSignedIn { return .signedOut }
        if !ownsAccess { return .unavailable }
        return visible && foreground ? storedPhase : .idle
    }
    public var rows: [OwnMediaAsset] { active ? storedRows : [] }
    public var nextCursor: Int64? { active ? cursor : nil }
    public var moreFailed: Bool {
        if case .some(.more(before: _)) = failedPlan { return active }; return false
    }
    public var canRetry: Bool { active && !isLoading && failedPlan != nil }
    public var canLoadMore: Bool { active && !isLoading && storedPhase == .ready && failedPlan == nil && cursor != nil }

    @discardableResult public func appear(foreground: Bool) -> Task<Void, Never>? {
        visible = true; self.foreground = foreground
        synchronizeAccess()
        guard active else { return nil }
        cancelRead(); clearRows()
        return start(.refresh)
    }
    public func disappear() {
        visible = false; cancelRead(); clearRows()
    }
    @discardableResult public func setForeground(_ value: Bool) -> Task<Void, Never>? {
        guard foreground != value else { synchronizeAccess(); return nil }
        foreground = value; cancelRead(); clearRows(); synchronizeAccess()
        return active ? start(.refresh) : nil
    }
    /// A destination never silently adopts another account, token epoch, or lease.
    public func synchronizeAccess() {
        if reader.scope != capturedScope { retired = true }
        guard !ownsAccess else { return }
        cancelRead(); clearRows()
    }
    @discardableResult public func refresh() -> Task<Void, Never>? {
        synchronizeAccess()
        guard active, !isLoading || loadingMore else { return nil }
        cancelRead(); clearRows()
        return start(.refresh)
    }
    @discardableResult public func more() -> Task<Void, Never>? {
        synchronizeAccess()
        guard canLoadMore, let cursor else { return nil }
        return start(.more(before: cursor))
    }
    @discardableResult public func retry() -> Task<Void, Never>? {
        synchronizeAccess()
        guard canRetry, let failedPlan else { return nil }
        return start(failedPlan)
    }
    private func cancelRead() {
        generation = UUID(); task?.cancel(); task = nil; isLoading = false; loadingMore = false
    }
    private func clearRows() {
        storedRows = []; cursor = nil; failedPlan = nil; storedPhase = .idle
    }
    private func accepts(_ run: UUID) -> Bool { generation == run && active }
    @discardableResult private func start(_ plan: ReadPlan) -> Task<Void, Never>? {
        guard active, !isLoading else { return nil }
        let before: Int64?
        switch plan {
        case .refresh: before = nil; storedPhase = .loading
        case .more(let requested):
            guard storedPhase == .ready, cursor == requested else { return nil }
            before = requested
        }
        let run = UUID(); generation = run; isLoading = true
        loadingMore = before != nil; failedPlan = nil
        let next = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == run { self.isLoading = false; self.loadingMore = false; self.task = nil }
            }
            do {
                guard self.accepts(run), !Task.isCancelled else { return }
                let page = try await self.reader.page(before: before)
                self.synchronizeAccess()
                guard self.accepts(run) else { return }
                try Task.checkCancellation()
                // The service validates the wire page. Also fence injected readers and
                // cross-page boundaries before publishing any part of a result.
                try Self.validate(page, before: before)
                switch plan {
                case .refresh: self.storedRows = page.rows
                case .more(let requested):
                    guard self.cursor == requested, self.storedRows.last?.id == requested else { throw APIError.malformedResponse }
                    self.storedRows += page.rows
                }
                self.cursor = page.nextCursor; self.storedPhase = .ready
            } catch {
                self.synchronizeAccess()
                guard self.accepts(run) else { return }
                let failure = Self.phase(for: error)
                if failure != .failed {
                    self.clearRows(); self.storedPhase = failure
                } else {
                    // A failed older-page request retains both the current rows and its
                    // exact cursor. It cannot masquerade as an empty successful page.
                    self.failedPlan = plan
                    self.storedPhase = before == nil ? .failed : .ready
                }
            }
        }
        task = next; return next
    }
    private static func validate(_ page: OwnMediaPage, before: Int64?) throws {
        guard page.rows.count <= OwnMediaPage.pageSize else { throw APIError.malformedResponse }
        var upper = before
        for row in page.rows {
            guard row.id > 0, upper.map({ row.id < $0 }) ?? true else { throw APIError.malformedResponse }
            upper = row.id
        }
    }
    public static func phase(for error: Error) -> Phase {
        if error as? APIError == .unauthorized { return .signedOut }
        if error as? APIError == .notConfigured { return .unavailable }
        if error as? OwnMediaReadFailure == .rejected(code: 403) || error as? APIError == .httpStatus(403) { return .denied }
        return .failed
    }
}
