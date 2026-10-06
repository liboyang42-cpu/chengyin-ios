import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopPurchasedBrowser {
    public enum Phase: String { case idle, loading, ready, empty, notEnabled, failed, invalidated }
    public let identity = UUID()
    public private(set) var phase: Phase = .idle
    public private(set) var rows: [WorkshopPurchasedItem] = []
    public private(set) var checkedAt: String?
    public private(set) var nextCursor: Int64?
    public var hasMore: Bool { nextCursor != nil }
    public private(set) var issue: WorkshopPurchasedIssue?
    public private(set) var detail: WorkshopPurchasedDetail?
    public private(set) var detailLoading = false
    public private(set) var detailIssue: WorkshopPurchasedIssue?
    private let reader: any WorkshopPurchasedReading
    private let lease: ContentDraftSessionLease
    private var listPresentation: WorkshopPurchasedPresentationPermit?
    private var detailPresentation: WorkshopPurchasedPresentationPermit?
    private var listGeneration = UUID()
    private var detailGeneration = UUID()
    private var listLifetime: WorkshopPurchasedReadLifetime?
    private var detailLifetime: WorkshopPurchasedReadLifetime?
    public init(reader: any WorkshopPurchasedReading, lease: ContentDraftSessionLease) { self.reader = reader; self.lease = lease }
    public func invalidate() {
        listPresentation?.revoke(); listPresentation = nil; detailPresentation?.revoke(); detailPresentation = nil
        lease.revoke(); listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID(); closeDetail()
        rows = []; checkedAt = nil; nextCursor = nil; issue = .staleSession; detailIssue = .staleSession; phase = .invalidated
    }
    private func current() -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated
    }
    /// Called only by actual synchronous onAppear, never from a queued action Task.
    public func presentList() -> WorkshopPurchasedPresentationPermit? {
        guard current() else { return nil }
        listPresentation?.revoke(); listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID()
        if phase == .loading { phase = .idle }
        let permit = WorkshopPurchasedPresentationPermit(); listPresentation = permit; return permit
    }
    public func leaveList(_ permit: WorkshopPurchasedPresentationPermit, closing: Bool) {
        permit.revoke()
        guard listPresentation === permit else { return }
        listPresentation = nil; listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID()
        if closing { closeList() } else if phase == .loading { phase = .idle }
    }
    public func load(before: Int64? = nil, action: WorkshopPurchasedActionPermit) async {
        guard before == nil || before == nextCursor, let presentation = action.presentation, listPresentation === presentation, action.isLive, !Task.isCancelled, current(), action.claim() else { return }
        listLifetime?.revoke(); let lifetime = WorkshopPurchasedReadLifetime(action: action); listLifetime = lifetime
        let ticket = UUID(); listGeneration = ticket
        closeDetail(); rows = []; checkedAt = nil; nextCursor = nil; issue = nil; phase = .loading
        do {
            let page = try await reader.list(before: before, lifetime: lifetime)
            guard action.isLive, current(), listGeneration == ticket else { return }
            guard !Task.isCancelled else { closeList(); return }
            checkedAt = page.checkedAt
            rows = page.items; nextCursor = page.nextBeforeOrderLineId; phase = rows.isEmpty ? .empty : .ready
        } catch {
            guard action.isLive, current(), listGeneration == ticket else { return }
            guard !Task.isCancelled else { closeList(); return }
            issue = (error as? WorkshopPurchasedIssue) ?? .unavailable
            phase = issue == .disabled || issue == .notFound ? .notEnabled : .failed
        }
    }
    public func presentDetail(licenseId: String) -> WorkshopPurchasedPresentationPermit? {
        guard current() else { return nil }
        closeDetail()
        guard phase == .ready, rows.contains(where: { $0.licenseId == licenseId }) else { return nil }
        let permit = WorkshopPurchasedPresentationPermit(licenseID: licenseId); detailPresentation = permit; return permit
    }
    public func leaveDetail(_ permit: WorkshopPurchasedPresentationPermit, closing: Bool) {
        permit.revoke()
        guard detailPresentation === permit else { return }
        detailPresentation = nil; detailLifetime?.revoke(); detailLifetime = nil; detailGeneration = UUID(); detailLoading = false
        if closing { closeDetail() }
    }
    public func open(licenseId: String, action: WorkshopPurchasedActionPermit) async {
        guard let presentation = action.presentation, detailPresentation === presentation, action.isLive, presentation.licenseID == licenseId,
              !Task.isCancelled, current(), phase == .ready, rows.contains(where: { $0.licenseId == licenseId }), action.claim() else { return }
        detailLifetime?.revoke(); let lifetime = WorkshopPurchasedReadLifetime(action: action); detailLifetime = lifetime
        let ticket = UUID(); detailGeneration = ticket; detail = nil; detailIssue = nil; detailLoading = true
        do {
            let response = try await reader.detail(licenseId: licenseId, lifetime: lifetime)
            guard action.isLive, current(), detailGeneration == ticket else { return }
            guard !Task.isCancelled else { closeDetail(); return }
            guard response.item.licenseId == licenseId else { throw WorkshopPurchasedIssue.malformed }
            detail = response; detailLoading = false
        } catch {
            guard action.isLive, current(), detailGeneration == ticket else { return }
            guard !Task.isCancelled else { closeDetail(); return }
            detailIssue = (error as? WorkshopPurchasedIssue) ?? .unavailable; detailLoading = false
        }
    }
    public func closeDetail() {
        detailPresentation?.revoke(); detailPresentation = nil
        detailLifetime?.revoke(); detailLifetime = nil; detailGeneration = UUID()
        detail = nil; detailIssue = nil; detailLoading = false
    }
    public func closeList() {
        listPresentation?.revoke(); listPresentation = nil
        guard phase != .invalidated else { return }
        listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID(); closeDetail()
        rows = []; checkedAt = nil; nextCursor = nil; issue = nil; phase = .idle
    }
}
