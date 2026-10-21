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

/// Display-only projection of the owned-list review and marketplace columns.
/// No action eligibility, write intent, library identity, or authority is derived here.
public struct TemplateOwnShelfStateProjection: Decodable, Equatable {
    public enum Personal: String {
        case draft = "templateShelfState.personal.draft"
        case approved = "templateShelfState.personal.approved"
        case rejected = "templateShelfState.personal.rejected"
        case reviewing = "templateShelfState.personal.reviewing"
        case unknown = "templateShelfState.personal.unknown"
    }
    public enum Market: String {
        case notSubmitted = "templateShelfState.market.notSubmitted"
        case reviewing = "templateShelfState.market.reviewing"
        case listed = "templateShelfState.market.listed"
        case unlisted = "templateShelfState.market.unlisted"
        case rejected = "templateShelfState.market.rejected"
        case unknown = "templateShelfState.market.unknown"
    }
    public let personal: Personal
    public let market: Market
    public let marketReason: String?
    /// A missing sidecar is unknown, never evidence of an absent marketplace record.
    public static let unknown = Self(personal: .unknown, market: .unknown, marketReason: nil)
    private init(personal: Personal, market: Market, marketReason: String?) {
        self.personal = personal; self.market = market; self.marketReason = marketReason
    }
    private enum Keys: String, CodingKey {
        case draftStatus, status, checkStatus, marketTemplateId, marketStatus, marketPublishStatus, marketReason
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let draft = Self.code(values, .draftStatus), status = Self.code(values, .status)
        let check = Self.code(values, .checkStatus)
        if draft == 0 { personal = .draft }
        else if draft == 1, status == 1, check == 1 { personal = .approved }
        else if draft == 1, status == 2 || check == 2 { personal = .rejected }
        else if draft == 1, status == 0 || check == 0 { personal = .reviewing }
        else { personal = .unknown }
        let marketStatus = Self.code(values, .marketStatus)
        let marketPublishStatus = Self.code(values, .marketPublishStatus)
        switch Self.marketIdentity(values) {
        case .absent: market = .notSubmitted
        case .unknown: market = .unknown
        case .present:
            if marketStatus == 0 { market = .reviewing }
            else if marketStatus == 1, marketPublishStatus == 1 { market = .listed }
            else if marketStatus == 1, marketPublishStatus == 0 { market = .unlisted }
            else if marketStatus == 2 { market = .rejected }
            else { market = .unknown }
        }
        if let reason = try? values.decode(String.self, forKey: .marketReason),
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { marketReason = reason }
        else { marketReason = nil }
    }
    /// Exact 0/1/2 or their canonical text only. In particular, empty text is not zero.
    private static func code(_ values: KeyedDecodingContainer<Keys>, _ key: Keys) -> Int64? {
        if let value = try? values.decode(Int64.self, forKey: key), (0...2).contains(value) { return value }
        guard let text = try? values.decode(String.self, forKey: key) else { return nil }
        switch text { case "0": return 0; case "1": return 1; case "2": return 2; default: return nil }
    }
    private enum MarketIdentity { case absent, present, unknown }
    private static func marketIdentity(_ values: KeyedDecodingContainer<Keys>) -> MarketIdentity {
        guard values.contains(.marketTemplateId) else { return .absent }
        if (try? values.decodeNil(forKey: .marketTemplateId)) == true { return .absent }
        if let value = try? values.decode(Int64.self, forKey: .marketTemplateId) {
            return value == 0 ? .absent : value > 0 ? .present : .unknown
        }
        guard let text = try? values.decode(String.self, forKey: .marketTemplateId) else { return .unknown }
        if text == "0" { return .absent }
        // Source accepts arbitrary-length digit strings. We bound them to the
        // backend Long domain; an out-of-domain value remains an unknown display.
        guard (1...19).contains(text.utf8.count), let first = text.utf8.first, (49...57).contains(first),
              text.utf8.dropFirst().allSatisfy({ (48...57).contains($0) }),
              let value = Int64(text), value > 0 else { return .unknown }
        return .present
    }
}
private struct TemplateOwnShelfStateEnvelope: Decodable {
    struct Payload: Decodable { let rows: [TemplateOwnShelfStateProjection] }
    let data: Payload
}

/// Presentation-only member shelf. Never used as mutation authority or absence proof.
public struct TemplateOwnShelfPage {
    public static let pageSize = 10
    public static let maximumPages = 100
    public let rows: [DiscoveryPlayTemplate]
    public let total: Int?
    public let rowStates: [Int: TemplateOwnShelfStateProjection]
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
        // Decode optional display columns from original bytes, avoiding Double
        // roundtripping of backend Long values. Malformed optional columns are unknown.
        let states = try JSONDecoder().decode(TemplateOwnShelfStateEnvelope.self, from: data).data.rows
        guard states.count == rows.count else { throw TemplateAuthoringError.invalidContract }
        let rowStates = Dictionary(uniqueKeysWithValues: zip(rows.map(\.id), states))
        return .init(rows: rows, total: total.flatMap { $0 >= 0 ? $0 : nil }, rowStates: rowStates)
    }
}

@MainActor public final class TemplateOwnShelfReader {
    private let adapter: TemplateAuthoringAdapter
    private let currentSession: () -> TemplateAuthoringSession?
    private var owner: TemplateAuthoringSession?
    private var generation = 0
    public private(set) var rows: [DiscoveryPlayTemplate] = []
    public private(set) var rowStates: [Int: TemplateOwnShelfStateProjection] = [:]
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
    public func leave() { generation += 1; busy = false; rows = []; page = 0; hasMore = false; messageKey = nil; isShowingRefreshSnapshot = false; rowStates = [:] }
    /// A same-scope display snapshot only. It cannot authorize a shelf mutation.
    public func refreshSnapshot(keyword: String) -> [DiscoveryPlayTemplate] {
        synchronizeSession()
        guard owner != nil, owner == currentSession(), adapter.canRead, self.keyword == keyword, !Task.isCancelled else { return [] }
        return rows
    }
    public func refresh(keyword: String = "") async {
        let snapshot = refreshSnapshot(keyword: keyword)
        let stateSnapshot = snapshot.isEmpty ? [:] : rowStates
        leave(); self.keyword = keyword; owner = currentSession()
        rows = snapshot; isShowingRefreshSnapshot = !snapshot.isEmpty
        rowStates = stateSnapshot
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
            // No suspension between committing rows and their display-only sidecars.
            if requested == 1 { rowStates = result.rowStates }
            else { rowStates.merge(result.rowStates) { _, fresh in fresh } }
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
            messageKey = requested == 1 ? Self.firstPageFailureKey(error) : "templateAuthor.shelf.moreFailed"
        }
    }
    /// Copy only. Login and permission stay distinct; other failures keep the list-unavailable key.
    private static func firstPageFailureKey(_ error: Error) -> String {
        if case APIError.unauthorized = error { return "templateAuthor.signIn" }
        if case APIError.httpStatus(let status) = error {
            if status == 401 { return "templateAuthor.signIn" }
            if status == 403 { return "templateOwnShelf.read.denied" }
        }
        if let rejection = error as? TemplateAuthoringRejection {
            if rejection.code == 401 { return "templateAuthor.signIn" }
            if rejection.code == 403 { return "templateOwnShelf.read.denied" }
        }
        return "templateAuthor.listUnavailable"
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
