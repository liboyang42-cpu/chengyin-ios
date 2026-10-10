import Foundation

public enum TemplateOwnShelfAction: String, Codable { case libraryStatus, remove }
public struct TemplateOwnShelfReview: Equatable, Identifiable {
    public let id: UUID
    public let templateID: AuthoringPlayTemplateID
    public let title: String
    public let action: TemplateOwnShelfAction
    public let desiredPublishStatus: Int?
    public let request: TemplateAuthoringRequest
    let session: TemplateAuthoringSession
    let baseline: DiscoveryPlayTemplate
    let generation: Int
    init(row: DiscoveryPlayTemplate, action: TemplateOwnShelfAction, session: TemplateAuthoringSession, generation: Int) throws {
        guard let identity = AuthoringPlayTemplateID(rawValue: row.id) else { throw TemplateAuthoringError.invalidContract }
        id = UUID(); templateID = identity; title = row.title; self.action = action
        desiredPublishStatus = action == .libraryStatus ? (row.publishStatus == 1 ? 0 : 1) : nil
        request = action == .remove ? TemplateAuthoringContract.remove(id: identity) : TemplateAuthoringContract.libraryStatus(id: identity, current: row.publishStatus)
        self.session = session; baseline = row; self.generation = generation
    }
}
/// One conservative, durable own-shelf write lock per account/region. Separate from
/// the existing create-draft journal, but using the same account-scoped secure store.
public struct TemplateOwnShelfPending: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let templateID: AuthoringPlayTemplateID
    public let action: TemplateOwnShelfAction
    public let desiredPublishStatus: Int?
    public let request: TemplateAuthoringRequest
    public var acknowledged: Bool = false
    init(review: TemplateOwnShelfReview) {
        operationID = review.id; ownerKey = review.session.ownerKey; templateID = review.templateID
        action = review.action; desiredPublishStatus = review.desiredPublishStatus; request = review.request
    }
    /// A 100-row response is capped, not a complete collection. Missing identity
    /// cannot establish removal there. Unknown responses are never reconciled here.
    public func matchesAcknowledgedReadback(_ rows: [DiscoveryPlayTemplate]) -> Bool {
        guard acknowledged else { return false }
        let matches = rows.filter { $0.id == templateID.rawValue }
        switch action {
        case .libraryStatus: return matches.count == 1 && matches[0].publishStatus == desiredPublishStatus
        case .remove: return rows.count < 100 && matches.isEmpty
        }
    }
}

/// Presentation-only member shelf. Never used as mutation authority or absence proof.
public struct TemplateOwnShelfPage {
    public static let pageSize = 10
    public static let maximumPages = 100
    public let rows: [DiscoveryPlayTemplate]
    public let total: Int?
    public static func request(page: Int, keyword: String) throws -> TemplateAuthoringRequest {
        guard (1...maximumPages).contains(page) else { throw TemplateAuthoringError.invalidContract }
        return .init(path: "/api/template/my-list", body: .form([
            "is_quote": "", "keyword": keyword, "category_id": "",
            "pageNum": String(page), "pageSize": String(pageSize)
        ]), mutates: false)
    }
    public static func decode(_ data: Data, httpStatus: Int) throws -> Self {
        try TemplateAuthoringContract.requireSuccess(data, httpStatus: httpStatus)
        let body = try JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: data)
        guard let payload = body["data"]?.object, let raw = payload["rows"]?.array else {
            throw TemplateAuthoringError.invalidContract
        }
        let rows = try JSONDecoder().decode([DiscoveryPlayTemplate].self, from: JSONEncoder().encode(raw))
        guard rows.count <= pageSize,
              rows.allSatisfy({ MemberPlayTemplateID(rawValue: $0.id) != nil }),
              Set(rows.map(\.id)).count == rows.count else { throw TemplateAuthoringError.invalidContract }
        let total = payload["total"]?.integer
        return .init(rows: rows, total: total.flatMap { $0 >= 0 ? $0 : nil })
    }
}

@MainActor public final class TemplateOwnShelfReader {
    private let adapter: TemplateAuthoringAdapter
    private let currentSession: () -> TemplateAuthoringSession?
    private var owner: TemplateAuthoringSession?
    private var generation = 0
    public private(set) var rows: [DiscoveryPlayTemplate] = []
    public private(set) var keyword = ""
    public private(set) var page = 0
    public private(set) var hasMore = false
    public private(set) var busy = false
    public private(set) var isShowingRefreshSnapshot = false
    public private(set) var messageKey: String?
    public init(adapter: TemplateAuthoringAdapter, currentSession: @escaping () -> TemplateAuthoringSession?) {
        self.adapter = adapter; self.currentSession = currentSession
    }
    public func synchronizeSession() {
        guard owner != currentSession() || !adapter.canRead else { return }
        leave(); owner = currentSession()
    }
    public func leave() { generation += 1; busy = false; rows = []; page = 0; hasMore = false; messageKey = nil; isShowingRefreshSnapshot = false }
    /// A same-scope display snapshot only. It cannot authorize a shelf mutation.
    public func refreshSnapshot(keyword: String) -> [DiscoveryPlayTemplate] {
        synchronizeSession()
        guard owner != nil, owner == currentSession(), adapter.canRead, self.keyword == keyword, !Task.isCancelled else { return [] }
        return rows
    }
    public func refresh(keyword: String = "") async {
        let snapshot = refreshSnapshot(keyword: keyword)
        leave(); self.keyword = keyword; owner = currentSession()
        rows = snapshot; isShowingRefreshSnapshot = !snapshot.isEmpty
        await fetch(page: 1)
    }
    public func loadMore() async {
        guard owner == currentSession(), adapter.canRead else { leave(); owner = currentSession(); return }
        guard !busy, hasMore, page < TemplateOwnShelfPage.maximumPages else { return }
        await fetch(page: page + 1)
    }
    private func fetch(page requested: Int) async {
        guard !Task.isCancelled, adapter.canRead else { leave(); return }
        guard let owner, owner == currentSession() else { leave(); messageKey = "templateAuthor.signIn"; return }
        guard !busy else { return }
        let stamp = generation; busy = true; messageKey = nil
        defer { if generation == stamp { busy = false } }
        do {
            let result = try await adapter.listMinePage(page: requested, keyword: keyword)
            guard generation == stamp else { return }
            guard self.owner == owner, currentSession() == owner, adapter.canRead, !Task.isCancelled else { leave(); return }
            // Offset pagination is not a snapshot. Refuse overlapping pages rather than
            // silently hiding a shifted/missing row or letting duplicates grant authority.
            if requested == 1 {
                rows = result.rows; isShowingRefreshSnapshot = false
            } else {
                let existing = Set(rows.map(\.id))
                guard result.rows.allSatisfy({ !existing.contains($0.id) }) else {
                    messageKey = "templateAuthor.shelf.moreFailed"; return
                }
                rows += result.rows
            }
            page = requested
            let continuation = !result.rows.isEmpty && (result.total.map { rows.count < $0 } ?? (result.rows.count == TemplateOwnShelfPage.pageSize))
            hasMore = continuation && page < TemplateOwnShelfPage.maximumPages
            messageKey = continuation && !hasMore ? "templateAuthor.shelf.pageLimit" : rows.isEmpty ? "templateAuthor.shelf.empty" : nil
        } catch {
            guard generation == stamp else { return }
            guard self.owner == owner, currentSession() == owner, adapter.canRead, !Task.isCancelled else { leave(); return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { leave(); return }
            // Only an explicit transient first-page failure may retain this snapshot.
            // Existing continuation retries keep their pages, except auth/contract failures.
            if (requested == 1 && !Self.isTransientRefreshFailure(error)) || Self.invalidatesReadScope(error) { leave() }
            // Retained refresh snapshots restart at page one; continuation retries
            // keep the same next page when their previous pages remain valid.
            messageKey = requested == 1 ? "templateAuthor.listUnavailable" : "templateAuthor.shelf.moreFailed"
        }
    }
    private static func isTransientRefreshFailure(_ error: Error) -> Bool {
        if case APIError.httpStatus(let status) = error { return (500...599).contains(status) }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
    }
    private static func invalidatesReadScope(_ error: Error) -> Bool {
        if error is TemplateAuthoringRejection || error is DecodingError { return true }
        if let error = error as? TemplateAuthoringError, error == .invalidContract || error == .unavailable { return true }
        guard let error = error as? APIError else { return false }
        switch error {
        case .httpStatus(let status): return !(500...599).contains(status)
        default: return true
        }
    }
}
