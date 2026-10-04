#if DEBUG
import SwiftUI

/// Offline synthetic fixture: no URL, credentials, transport or persistence.
enum ClubManagementFixtureScenario: String {
    case owner, admin, ordinary, empty, unknown, denied, delayed, readbackUnavailable, unknownDelayedRefresh, detailReturn, detailReturnUnavailable
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-club-management-fixture"), arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}
@MainActor
struct ClubManagementFixtureRootView: View {
    @StateObject private var store: ClubManagementFixtureStore
    init(scenario: ClubManagementFixtureScenario) { _store = StateObject(wrappedValue: ClubManagementFixtureStore(scenario: scenario)) }
    var body: some View {
        VStack {
            Text("club.management.fixture")
            HStack {
                Button("club.management.switch_account") { store.switchAccount() }
                    .accessibilityIdentifier("club.management.switch")
                    // Read-only evidence of the real fixture action, without changing layout.
                    .accessibilityValue(Text(verbatim: "account=\(store.identity?.accountID ?? 0);epoch=\(store.identity?.epoch ?? 0)"))
                Button("club.management.sign_out") { store.signOut() }.accessibilityIdentifier("club.management.signout")
                Text(store.writeCount, format: .number).accessibilityIdentifier("club.management.writes")
                Text(store.membershipChanges, format: .number).accessibilityIdentifier("club.management.changes")
            }
            NavigationStack {
                if store.scenario == .detailReturn || store.scenario == .detailReturnUnavailable {
                    ClubDetailView(id: 81, reader: store, management: .init(access: store, coordinator: store.coordinator))
                } else {
                    ClubManagementView(clubID: 81, identity: store.identity, access: store, coordinator: store.coordinator, onMembershipChanged: { store.membershipChanges += 1 })
                }
            }.id(store.identity)
        }
    }
}
@MainActor
private final class ClubManagementFixtureStore: ObservableObject, ClubManagementAccess, ClubReading {
    @Published var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 0)
    @Published var writeCount = 0
    @Published var membershipChanges = 0
    let isConfigured = true
    let scenario: ClubManagementFixtureScenario
    private var completed: Set<Int> = []
    lazy var coordinator = ClubManagementCoordinator(access: self)
    init(scenario: ClubManagementFixtureScenario) { self.scenario = scenario }
    func switchAccount() {
        identity = .init(accountID: identity?.accountID == 701 ? 702 : 701, epoch: (identity?.epoch ?? 0) + 1)
        coordinator.synchronizeSession()
    }
    func signOut() { identity = nil; coordinator.synchronizeSession() }
    func snapshot(clubID: Int) async throws -> ClubManagementSnapshot {
        try Task.checkCancellation()
        guard let account = identity?.accountID else { throw APIError.unauthorized }
        guard scenario != .ordinary else { throw ClubReadFailure.forbidden(message: nil) }
        if scenario == .readbackUnavailable, completed.contains(account) { throw APIError.malformedResponse }
        if scenario == .unknownDelayedRefresh, completed.contains(account) { try await Task.sleep(nanoseconds: 5_000_000_000) }
        let owner = scenario != .admin
        let club = try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":81,\"name\":\"Fixture club\",\"isOwner\":\(owner),\"viewerIsAdmin\":true,\"isJoined\":true,\"memberCount\":2}".utf8))
        let done = completed.contains(account) || scenario == .empty
        let requests = try JSONDecoder().decode([ClubManagementRequest].self, from: Data((done ? "[]" : #"[{"memberId":703,"nickname":"Fixture applicant","joinMessage":"Night walks please 👋","joinTime":"2026-09-01T10:30:00"}]"#).utf8))
        let members = try JSONDecoder().decode([ClubMember].self, from: Data((done ? #"[{"memberId":701,"nickname":"Fixture owner","isOwner":true}]"# : #"[{"memberId":701,"nickname":"Fixture owner","isOwner":true},{"memberId":704,"nickname":"Fixture member","role":0}]"#).utf8))
        return .init(club: club, requests: requests, members: owner ? members : [])
    }
    var isClubConfigured: Bool { isConfigured }
    var clubIdentity: ClubReadIdentity { identity ?? .init(accountID: nil, epoch: 0) }
    func clubHome() async throws -> ClubHome { throw APIError.invalidRequest }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.invalidRequest }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.invalidRequest }
    func clubDetail(id: Int) async throws -> ClubRecord {
        guard let account = identity?.accountID else { throw APIError.unauthorized }
        if completed.contains(account), scenario == .detailReturnUnavailable { throw APIError.malformedResponse }
        let name = completed.contains(account) ? "Fixture club refreshed" : "Fixture club"
        return try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":81,\"name\":\"\(name)\",\"isOwner\":true,\"viewerIsAdmin\":true,\"isJoined\":true,\"memberCount\":2}".utf8))
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory {
        let snapshot = try await snapshot(clubID: id)
        return .init(club: snapshot.club, members: snapshot.members)
    }
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        guard identity == expectedIdentity, let account = identity?.accountID else { throw ClubActionWriteError.notSent(.unauthorized) }
        let fresh = try await snapshot(clubID: clubID)
        guard fresh.allows(action, memberID: memberID) else { throw ClubActionWriteError.eligibilityChanged }
        writeCount += 1
        if scenario == .denied { throw ClubActionWriteError.rejected(.init(code: 403, message: "Fixture server denial")) }
        if scenario == .delayed { try await Task.sleep(nanoseconds: 2_000_000_000) }
        completed.insert(account)
        guard identity == expectedIdentity else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
        if scenario == .unknown || scenario == .unknownDelayedRefresh { throw ClubActionWriteError.outcomeUnknown(.transport) }
        return .init(state: nil, message: nil)
    }
}
#endif
