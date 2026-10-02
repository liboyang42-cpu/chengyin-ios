import Foundation

@MainActor public protocol SquareGovernanceAccess {
    var identity: SquareGovernanceIdentity? { get }
    var token: String? { get }
    /// Refresh current post/comment detail via the host's existing authorized read.
    /// Unknown ownership/version is preserved. No invented moderator-access endpoint.
    func freshComments() async throws -> [SquareGovernanceComment]
}
@MainActor public final class SquareGovernanceCoordinator {
    public let service: SquareGovernanceService
    private var inFlight = false
    private var consumed = Set<UUID>()
    private let journal: SquareGovernanceJournal
    public init(service: SquareGovernanceService, journal: SquareGovernanceJournal? = nil) { self.service = service; self.journal = journal ?? .persistent() }
    public func check(_ identity: SquareGovernanceIdentity, access: any SquareGovernanceAccess) throws {
        guard identity.valid, identity == access.identity, let token = access.token, AuthRequestBuilder.isValidToken(token) else { throw SquareGovernanceFailure.signedOut }
    }
    public func load(access: any SquareGovernanceAccess, enforcementPages: Int = 1, notificationPages: Int = 1) async throws -> SquareGovernanceSnapshot {
        guard let identity = access.identity, let token = access.token else { throw SquareGovernanceFailure.signedOut }
        try check(identity, access: access)
        guard (1...100).contains(enforcementPages), (1...100).contains(notificationPages) else { throw SquareGovernanceFailure.invalid }
        var records: [SquareEnforcement] = [], notices: [SquareGovernanceNotification] = []
        var cursor: Int?
        for _ in 0..<enforcementPages {
            let page = try await service.enforcements(cursor: cursor, token: token) { try self.check(identity, access: access) }
            var known = Set(records.map(\.id)); records += page.filter { known.insert($0.id).inserted }
            let next = records.map(\.id).min()
            if page.count < 30 { break }
            guard next != cursor else { throw SquareGovernanceFailure.malformed }; cursor = next
        }
        cursor = nil
        for _ in 0..<notificationPages {
            let page = try await service.notifications(cursor: cursor, token: token) { try self.check(identity, access: access) }
            var known = Set(notices.map(\.id)); notices += page.filter { known.insert($0.id).inserted }
            let next = notices.map(\.id).min()
            if page.count < 50 { break }
            guard next != cursor else { throw SquareGovernanceFailure.malformed }; cursor = next
        }
        let preferences = try await service.preferences(token: token) { try self.check(identity, access: access) }
        let comments = try await access.freshComments(); try check(identity, access: access)
        return .init(identity: identity, enforcements: records, notifications: notices, preferences: preferences, comments: comments, enforcementPages: enforcementPages, notificationPages: notificationPages)
    }
    public static func validate(_ action: SquareGovernanceAction, snapshot: SquareGovernanceSnapshot) throws {
        guard snapshot.identity.valid else { throw SquareGovernanceFailure.signedOut }
        switch action {
        case .appeal(let id, let reason):
            let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty, reason.count <= 1000, snapshot.enforcements.contains(where: { $0.id == id && $0.canRequestReview }) else { throw SquareGovernanceFailure.invalid }
        case .markRead(let id):
            guard snapshot.notifications.contains(where: { $0.id == id && $0.unread }) else { throw SquareGovernanceFailure.invalid }
        case .preferences(let values):
            guard !values.isEmpty, values.keys.allSatisfy({ snapshot.preferences[$0.rawValue].bool != nil }) else { throw SquareGovernanceFailure.invalid }
        case .approveComment(let postID, let commentID):
            guard snapshot.comments.contains(where: { $0.id == commentID && $0.postID == postID && $0.canApprove(snapshot.identity) }) else { throw SquareGovernanceFailure.forbidden }
        case .deleteOwnComment(let id):
            guard snapshot.comments.contains(where: { $0.id == id && $0.canDelete(snapshot.identity) }) else { throw SquareGovernanceFailure.forbidden }
        }
    }
    static func lockKey(_ action: SquareGovernanceAction) -> String {
        switch action {
        case .appeal(let id, _): return "appeal:\(id)"
        case .markRead(let id): return "read:\(id)"
        case .preferences: return "preferences"
        case .approveComment(let post, let comment): return "comment:\(post):\(comment)"
        case .deleteOwnComment(let id): return "delete:\(id)"
        }
    }
    public func prepare(_ action: SquareGovernanceAction, snapshot: SquareGovernanceSnapshot, access: any SquareGovernanceAccess, now: Date = Date()) throws -> SquareGovernanceReview {
        guard !inFlight else { throw SquareGovernanceFailure.busy }
        try check(snapshot.identity, access: access); try Self.validate(action, snapshot: snapshot)
        guard !journal.contains(Self.lockKey(action), identity: snapshot.identity) else { throw SquareGovernanceFailure.outcomeLocked }
        return .init(snapshot: snapshot, action: action, now: now)
    }
    public func confirm(_ review: SquareGovernanceReview, access: any SquareGovernanceAccess, now: Date = Date()) async throws -> SquareGovernanceReceipt {
        guard !inFlight else { throw SquareGovernanceFailure.busy }
        guard service.allows(review.action) else { throw SquareGovernanceFailure.disabled }
        guard !consumed.contains(review.id), !journal.contains(Self.lockKey(review.action), identity: review.snapshot.identity) else { throw SquareGovernanceFailure.outcomeLocked }
        guard now.timeIntervalSince(review.createdAt) >= 0, now.timeIntervalSince(review.createdAt) <= 300 else { throw SquareGovernanceFailure.staleReview }
        inFlight = true; defer { inFlight = false }
        try check(review.snapshot.identity, access: access)
        let fresh = try await load(access: access, enforcementPages: review.snapshot.enforcementPages, notificationPages: review.snapshot.notificationPages)
        guard fresh == review.snapshot else { throw SquareGovernanceFailure.staleReview }
        try Self.validate(review.action, snapshot: fresh)
        guard let token = access.token else { throw SquareGovernanceFailure.signedOut }
        // Consume before dispatch. Unknown results cannot be repeated with a new request ID.
        consumed.insert(review.id)
        journal.insert(Self.lockKey(review.action), identity: fresh.identity)
        return try await service.dispatch(review, token: token) { try self.check(fresh.identity, access: access) }
    }
}

/// Conservative account-scoped dispatch journal: survives relogin/epoch changes.
/// Stores only target/action IDs, never credentials or appeal text. No automatic unlock.
@MainActor public final class SquareGovernanceJournal {
    private let defaults: UserDefaults?
    private var memory: [String: Set<String>] = [:]
    private init(defaults: UserDefaults?) { self.defaults = defaults }
    public static func persistent() -> SquareGovernanceJournal { .init(defaults: .standard) }
    public static func ephemeral() -> SquareGovernanceJournal { .init(defaults: nil) }
    private func key(_ identity: SquareGovernanceIdentity) -> String { "square.governance.dispatch.\(identity.namespace.utf8.count):\(identity.namespace):\(identity.accountID)" }
    func contains(_ action: String, identity: SquareGovernanceIdentity) -> Bool {
        let key = key(identity)
        return memory[key]?.contains(action) == true || defaults?.stringArray(forKey: key)?.contains(action) == true
    }
    func insert(_ action: String, identity: SquareGovernanceIdentity) {
        let key = key(identity)
        var values = Set(defaults?.stringArray(forKey: key) ?? []); values.formUnion(memory[key] ?? []); values.insert(action)
        memory[key] = values; defaults?.set(Array(values).sorted(), forKey: key)
    }
}
