import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopOwnedBrowser {
    public enum Phase: String { case idle, loading, ready, empty, notEnabled, failed, invalidated }
    public let identity = UUID()
    public let packageBrowser: WorkshopOwnedPackageBrowser?
    public private(set) var phase: Phase = .idle
    public private(set) var rows: [WorkshopOwnedItem] = []
    public private(set) var checkedAt: String?
    public private(set) var hasMore = false
    public private(set) var issue: WorkshopOwnedIssue?
    public private(set) var detail: WorkshopOwnedDetail?
    public private(set) var detailLoading = false
    public private(set) var detailIssue: WorkshopOwnedIssue?
    private let reader: any WorkshopOwnedReading
    private let lease: ContentDraftSessionLease
    private var listPresentation: WorkshopOwnedPresentationPermit?
    private var detailPresentation: WorkshopOwnedPresentationPermit?
    private var listGeneration = UUID()
    private var detailGeneration = UUID()
    private var listLifetime: WorkshopOwnedReadLifetime?
    private var detailLifetime: WorkshopOwnedReadLifetime?
    public init(reader: any WorkshopOwnedReading, lease: ContentDraftSessionLease, packageBrowser: WorkshopOwnedPackageBrowser? = nil) { self.reader = reader; self.lease = lease; self.packageBrowser = packageBrowser }
    public func invalidate() {
        listPresentation?.revoke(); listPresentation = nil; detailPresentation?.revoke(); detailPresentation = nil
        packageBrowser?.invalidate(); lease.revoke(); listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID(); closeDetail()
        rows = []; checkedAt = nil; hasMore = false; issue = .staleSession; detailIssue = .staleSession; phase = .invalidated
    }
    private func current() -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated
    }
    /// Called only by actual synchronous onAppear, never from a queued action Task.
    public func presentList() -> WorkshopOwnedPresentationPermit? {
        guard current() else { return nil }
        listPresentation?.revoke(); listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID()
        if phase == .loading { phase = .idle }
        let permit = WorkshopOwnedPresentationPermit(); listPresentation = permit; return permit
    }
    public func leaveList(_ permit: WorkshopOwnedPresentationPermit, closing: Bool) {
        permit.revoke()
        guard listPresentation === permit else { return }
        listPresentation = nil; listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID()
        if closing { closeList() } else if phase == .loading { phase = .idle }
    }
    public func load(action: WorkshopOwnedActionPermit) async {
        guard let presentation = action.presentation, listPresentation === presentation, action.isLive, !Task.isCancelled, current(), action.claim() else { return }
        listLifetime?.revoke(); let lifetime = WorkshopOwnedReadLifetime(action: action); listLifetime = lifetime
        let ticket = UUID(); listGeneration = ticket
        closeDetail(); rows = []; checkedAt = nil; hasMore = false; issue = nil; phase = .loading
        do {
            let page = try await reader.list(lifetime: lifetime)
            guard action.isLive, current(), listGeneration == ticket else { return }
            guard !Task.isCancelled else { closeList(); return }
            checkedAt = page.metadata.checkedAt
            if page.metadata.availability == .notEnabled { phase = .notEnabled; return }
            rows = page.items; hasMore = page.hasMore; phase = rows.isEmpty ? .empty : .ready
        } catch {
            guard action.isLive, current(), listGeneration == ticket else { return }
            guard !Task.isCancelled else { closeList(); return }
            issue = (error as? WorkshopOwnedIssue) ?? .unavailable
            phase = issue == .disabled || issue == .notFound ? .notEnabled : .failed
        }
    }
    public func presentDetail(claimId: String) -> WorkshopOwnedPresentationPermit? {
        guard current() else { return nil }
        closeDetail()
        guard phase == .ready, rows.contains(where: { $0.claimId == claimId }) else { return nil }
        let permit = WorkshopOwnedPresentationPermit(claimID: claimId); detailPresentation = permit; return permit
    }
    public func leaveDetail(_ permit: WorkshopOwnedPresentationPermit, closing: Bool) {
        permit.revoke()
        guard detailPresentation === permit else { return }
        detailPresentation = nil; detailLifetime?.revoke(); detailLifetime = nil; detailGeneration = UUID(); detailLoading = false
        if closing { closeDetail() }
    }
    public func open(claimId: String, action: WorkshopOwnedActionPermit) async {
        guard let presentation = action.presentation, detailPresentation === presentation, action.isLive, presentation.claimID == claimId,
              !Task.isCancelled, current(), phase == .ready, rows.contains(where: { $0.claimId == claimId }), action.claim() else { return }
        packageBrowser?.close(); detailLifetime?.revoke(); let lifetime = WorkshopOwnedReadLifetime(action: action); detailLifetime = lifetime
        let ticket = UUID(); detailGeneration = ticket; detail = nil; detailIssue = nil; detailLoading = true
        do {
            let response = try await reader.detail(claimId: claimId, lifetime: lifetime)
            guard action.isLive, current(), detailGeneration == ticket else { return }
            guard !Task.isCancelled else { closeDetail(); return }
            guard response.item == nil || response.item?.claimId == claimId else { throw WorkshopOwnedIssue.malformed }
            detail = response; detailLoading = false
        } catch {
            guard action.isLive, current(), detailGeneration == ticket else { return }
            guard !Task.isCancelled else { closeDetail(); return }
            detailIssue = (error as? WorkshopOwnedIssue) ?? .unavailable; detailLoading = false
        }
    }
    public func closeDetail() {
        detailPresentation?.revoke(); detailPresentation = nil
        packageBrowser?.close()
        detailLifetime?.revoke(); detailLifetime = nil; detailGeneration = UUID()
        detail = nil; detailIssue = nil; detailLoading = false
    }
    public func closeList() {
        listPresentation?.revoke(); listPresentation = nil
        guard phase != .invalidated else { return }
        listLifetime?.revoke(); listLifetime = nil; listGeneration = UUID(); closeDetail()
        rows = []; checkedAt = nil; hasMore = false; issue = nil; phase = .idle
    }
}
