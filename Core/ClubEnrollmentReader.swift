import Foundation
import Observation

/// Screen-scoped, read-only state. Every receipt belongs to an account epoch and generation.
@MainActor @Observable public final class ClubEnrollmentReader {
    public private(set) var teams: [ClubEnrollmentTeam] = []
    public private(set) var rosters: [Int: ClubEnrollmentRoster] = [:]
    public private(set) var expanded: Set<Int> = []
    public private(set) var detailLoading: Set<Int> = []
    public private(set) var detailFailures: [Int: ClubGovernanceFailure] = [:]
    public private(set) var loading = false
    public private(set) var hasLoaded = false
    public private(set) var failure: ClubGovernanceFailure?
    public private(set) var identity: ClubReadIdentity?
    public private(set) var presentationRevision: UInt64 = 0
    public private(set) var completedRefreshRevision: UInt64 = 0
    public let clubID: Int
    public let clubName: String?
    private let focusTopicID: Int?
    private let access: any ClubGovernanceAccess
    private let authorization: UUID?
    private let namespace: String
    private let realm: String
    private var generation: UInt64 = 0
    private var detailGenerations: [Int: UInt64] = [:]
    private var didFocus = false
    nonisolated public static let permissionDeniedTitle = "没有权限查看报名名册"
    public init(clubID: Int, focusTopicID: Int? = nil, clubName: String? = nil, access: any ClubGovernanceAccess) {
        self.clubID = clubID; self.focusTopicID = focusTopicID; self.clubName = clubName; self.access = access
        authorization = access.authorizationGeneration; namespace = access.storageNamespace; realm = access.journalRealm
    }
    public var headerLine: String {
        Self.formatHeaderLine(clubName: clubName, teamCount: teams.count)
    }
    public var failureTitle: String? {
        Self.failureTitle(for: failure)
    }
    nonisolated public static func formatHeaderLine(clubName: String?, teamCount: Int) -> String {
        let count = max(teamCount, 0)
        if let trimmed = clubName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return "\(trimmed) · \(count) 个团"
        }
        return "\(count) 个团"
    }
    nonisolated public static func formatPaymentRefundSummary(paidCount: Int, refundableCount: Int?) -> String {
        let paid = max(paidCount, 0)
        let refundableText = refundableCount.map { String(max($0, 0)) } ?? "待确认"
        return "已支付 \(paid) / 可退款 \(refundableText)"
    }
    nonisolated public static func failureTitle(for failure: ClubGovernanceFailure?) -> String? {
        guard let failure else { return nil }
        switch failure {
        case .forbidden:
            return permissionDeniedTitle
        case .rejected(let code, _):
            return code == 403 ? permissionDeniedTitle : nil
        default:
            return nil
        }
    }
    public var isCurrentAccess: Bool {
        access.isConfigured && access.authorizationGeneration == authorization &&
            access.storageNamespace == namespace && access.journalRealm == realm
    }
    public func usesAccess(_ candidate: any ClubGovernanceAccess) -> Bool {
        ObjectIdentifier(access) == ObjectIdentifier(candidate) && isCurrentAccess
    }
    public func activate(identity: ClubReadIdentity?) async {
        if self.identity != identity { clear(); self.identity = identity }
        if !hasLoaded && !loading { await refresh() }
    }
    public func suspend() { generation &+= 1; detailGenerations.removeAll(); detailLoading.removeAll(); loading = false }
    private func clear() {
        presentationRevision &+= 1
        suspend(); teams = []; rosters = [:]; expanded = []; detailFailures = [:]
        failure = nil; hasLoaded = false; didFocus = false
    }
    private func current(_ expected: ClubReadIdentity?, _ revision: UInt64) -> Bool {
        isCurrentAccess && generation == revision && identity == expected && access.identity == expected && !Task.isCancelled
    }
    private func check(_ snapshot: ClubGovernanceSnapshot, operation: ClubGovernanceRead, scope: ClubGovernanceScope) throws {
        guard snapshot.operation == operation, snapshot.scope == scope else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows("club:member:list:read", scope: scope) == true else { throw ClubGovernanceFailure.forbidden }
    }
    private func error(_ error: Error) -> ClubGovernanceFailure { error as? ClubGovernanceFailure ?? .rejected(code: nil, message: nil) }
    private func clearsSnapshot(_ error: ClubGovernanceFailure) -> Bool { [.signedOut, .forbidden, .targetChanged].contains(error) }
    public func refresh() async {
        guard identity?.isSignedIn == true, identity == access.identity else { clear(); failure = .signedOut; return }
        guard access.isConfigured else { clear(); failure = .notConfigured; return }
        guard isCurrentAccess else { clear(); failure = .staleReview; return }
        presentationRevision &+= 1
        generation &+= 1; let revision = generation, expected = identity
        detailGenerations.removeAll(); detailLoading.removeAll(); loading = true; failure = nil
        do {
            let scope = ClubGovernanceScope(clubID: clubID)
            let snapshot = try await access.read(.topics, scope: scope, options: [:], check: {
                guard self.current(expected, revision) else { throw ClubGovernanceFailure.staleReview }
            })
            guard current(expected, revision) else { return }
            try check(snapshot, operation: .topics, scope: scope)
            let accepted = try ClubEnrollmentTeam.list(snapshot.value, clubID: clubID)
            teams = accepted; hasLoaded = true; loading = false
            let ids = Set(accepted.map(\.id)); expanded.formIntersection(ids)
            rosters = rosters.filter { expanded.contains($0.key) }; detailFailures = [:]
            if !didFocus, let focusTopicID, ids.contains(focusTopicID) { expanded.insert(focusTopicID); didFocus = true }
            // Refresh expanded details too: a changed count must not retain pre-checkin rows.
            for id in expanded.sorted() {
                guard current(expected, revision) else { return }
                await loadDetail(topicID: id)
            }
            guard current(expected, revision), detailFailures.isEmpty else { return }
            completedRefreshRevision &+= 1
        } catch {
            guard current(expected, revision) else { return }
            let issue = self.error(error)
            if clearsSnapshot(issue) { clear() }
            failure = issue; loading = false
        }
    }
    public func toggle(topicID: Int) async {
        guard isCurrentAccess, teams.contains(where: { $0.id == topicID }), !loading else { return }
        if expanded.contains(topicID) { expanded.remove(topicID) }
        else { expanded.insert(topicID); if rosters[topicID] == nil { await loadDetail(topicID: topicID) } }
    }
    public func loadDetail(topicID: Int) async {
        guard isCurrentAccess, identity?.isSignedIn == true, identity == access.identity, teams.contains(where: { $0.id == topicID }), !detailLoading.contains(topicID) else { return }
        presentationRevision &+= 1
        let expected = identity, revision = generation
        let detailRevision = (detailGenerations[topicID] ?? 0) &+ 1
        detailGenerations[topicID] = detailRevision; detailLoading.insert(topicID); detailFailures[topicID] = nil
        do {
            let scope = ClubGovernanceScope(clubID: clubID, topicID: topicID)
            let snapshot = try await access.read(.registrations, scope: scope, options: [:], check: {
                guard self.current(expected, revision), self.detailGenerations[topicID] == detailRevision else {
                    throw ClubGovernanceFailure.staleReview
                }
            })
            guard current(expected, revision), detailGenerations[topicID] == detailRevision else { return }
            try check(snapshot, operation: .registrations, scope: scope)
            rosters[topicID] = try ClubEnrollmentRoster(value: snapshot.value, scope: scope)
        } catch {
            guard current(expected, revision), detailGenerations[topicID] == detailRevision else { return }
            let issue = self.error(error)
            if clearsSnapshot(issue) { clear(); failure = issue; return }
            detailFailures[topicID] = issue
        }
        detailLoading.remove(topicID)
    }
}

extension ClubEnrollmentRoster {
    public var paymentRefundSummaryText: String {
        ClubEnrollmentReader.formatPaymentRefundSummary(paidCount: paidCount, refundableCount: refundableCount)
    }
}
