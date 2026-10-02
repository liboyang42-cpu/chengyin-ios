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
    public let clubID: Int
    private let focusTopicID: Int?
    private let access: any ClubGovernanceAccess
    private var generation: UInt64 = 0
    private var detailGenerations: [Int: UInt64] = [:]
    private var didFocus = false
    public init(clubID: Int, focusTopicID: Int? = nil, access: any ClubGovernanceAccess) {
        self.clubID = clubID; self.focusTopicID = focusTopicID; self.access = access
    }
    public func activate(identity: ClubReadIdentity?) async {
        if self.identity != identity { clear(); self.identity = identity }
        if !hasLoaded { await refresh() }
    }
    public func suspend() { generation &+= 1; detailGenerations.removeAll(); detailLoading.removeAll(); loading = false }
    private func clear() {
        suspend(); teams = []; rosters = [:]; expanded = []; detailFailures = [:]
        failure = nil; hasLoaded = false; didFocus = false
    }
    private func current(_ expected: ClubReadIdentity?, _ revision: UInt64) -> Bool {
        generation == revision && identity == expected && access.identity == expected && !Task.isCancelled
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
        generation &+= 1; let revision = generation, expected = identity
        detailGenerations.removeAll(); detailLoading.removeAll(); loading = true; failure = nil
        do {
            let scope = ClubGovernanceScope(clubID: clubID)
            let snapshot = try await access.read(.topics, scope: scope, options: [:])
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
        } catch {
            guard current(expected, revision) else { return }
            let issue = self.error(error)
            if clearsSnapshot(issue) { clear() }
            failure = issue; loading = false
        }
    }
    public func toggle(topicID: Int) async {
        guard teams.contains(where: { $0.id == topicID }), !loading else { return }
        if expanded.contains(topicID) { expanded.remove(topicID) }
        else { expanded.insert(topicID); if rosters[topicID] == nil { await loadDetail(topicID: topicID) } }
    }
    public func loadDetail(topicID: Int) async {
        guard identity?.isSignedIn == true, identity == access.identity, teams.contains(where: { $0.id == topicID }), !detailLoading.contains(topicID) else { return }
        let expected = identity, revision = generation
        let detailRevision = (detailGenerations[topicID] ?? 0) &+ 1
        detailGenerations[topicID] = detailRevision; detailLoading.insert(topicID); detailFailures[topicID] = nil
        do {
            let scope = ClubGovernanceScope(clubID: clubID, topicID: topicID)
            let snapshot = try await access.read(.registrations, scope: scope, options: [:])
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
