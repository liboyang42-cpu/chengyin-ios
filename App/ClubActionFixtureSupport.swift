#if DEBUG
import SwiftUI

/// Synthetic in-memory membership server. It contains no URL, HTTP transport, token,
/// payment, credential, or persisted state, and is never included in release builds.
enum ClubActionFixtureScenario: String {
    case join, apply, leave, pending, owner, merchant, reapply, denied, unknown, readbackUnavailable, delayed, guest, refreshConsistency
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-club-action-fixture"), arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

@MainActor
struct ClubActionFixtureRootView: View {
    @StateObject private var store: ClubActionFixtureStore
    init(scenario: ClubActionFixtureScenario) { _store = StateObject(wrappedValue: ClubActionFixtureStore(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("club.action.fixtureNotice").font(.caption.bold()).accessibilityIdentifier("club.action.fixture.notice")
                HStack {
                    Button("club.fixtureSwitchAccount") { store.switchAccount() }.accessibilityIdentifier("club.action.fixture.switchAccount")
                    Button("club.fixtureSignOut") { store.signOut() }.accessibilityIdentifier("club.action.fixture.signOut")
                    Button("club.signIn") { store.signIn() }.accessibilityIdentifier("club.action.fixture.signIn")
                }.font(.caption)
                HStack { Text("club.action.fixtureWrites"); Text(store.writeCount, format: .number).accessibilityIdentifier("club.action.fixture.writeCount") }.font(.caption)
            }.padding(8).frame(maxWidth: .infinity).background(.yellow.opacity(0.15))
            NavigationStack {
                ClubDetailView(id: 81, reader: store, onSignIn: { store.signIn() }, actionCoordinator: store.coordinator)
            }.id(store.clubIdentity)
        }
    }
}

@MainActor
private final class ClubActionFixtureStore: ObservableObject, ClubReading, ClubActionWriting {
    let isConfigured = true
    let isClubConfigured = true
    @Published private(set) var clubIdentity: ClubReadIdentity
    @Published private(set) var writeCount = 0
    var identity: ClubReadIdentity? { clubIdentity.isSignedIn ? clubIdentity : nil }
    var viewerIsMerchant: Bool { scenario == .merchant }
    lazy var coordinator = ClubActionCoordinator(writer: self, reader: self)
    private let scenario: ClubActionFixtureScenario
    private var accountID = 701
    private var joined: [Int: Bool] = [:]
    private var pending: Set<Int> = []
    private var writtenAccounts: Set<Int> = []
    private var readsAfterWrite: [Int: Int] = [:]
    init(scenario: ClubActionFixtureScenario) {
        self.scenario = scenario
        clubIdentity = .init(accountID: scenario == .guest ? nil : 701, epoch: 0)
        if scenario == .leave || scenario == .owner { joined[701] = true }
        if scenario == .pending { pending.insert(701) }
    }
    func signOut() { clubIdentity = .init(accountID: nil, epoch: clubIdentity.epoch &+ 1); coordinator.synchronizeSession() }
    func signIn() { clubIdentity = .init(accountID: accountID, epoch: clubIdentity.epoch &+ 1); coordinator.synchronizeSession() }
    func switchAccount() { accountID = accountID == 701 ? 702 : 701; signIn() }
    func clubDetail(id: Int) async throws -> ClubRecord {
        try Task.checkCancellation()
        guard clubIdentity.isSignedIn else { throw ClubReadFailure.unauthorized(message: nil) }
        guard id == 81 else { throw APIError.invalidRequest }
        if scenario == .readbackUnavailable, writtenAccounts.contains(accountID) { throw APIError.malformedResponse }
        if scenario == .refreshConsistency, writtenAccounts.contains(accountID) {
            readsAfterWrite[accountID, default: 0] += 1
            // Simulate a subsequent server-side removal after the first joined readback.
            // The refresh response then equals the original pre-join snapshot.
            if readsAfterWrite[accountID, default: 0] > 1 { joined[accountID] = false }
        }
        let member = joined[accountID] == true
        let status: Int? = member ? 1 : pending.contains(accountID) ? 0 : scenario == .reapply ? 2 : nil
        var fields: [String: Any] = [
            "id": id, "name": "Fixture club", "description": "Offline synthetic membership example.",
            "isOwner": scenario == .owner && accountID == 701, "isJoined": member,
            "memberCount": member ? 4 : 3, "joinPolicy": [.apply, .reapply, .pending].contains(scenario) ? 1 : 0,
            "joinPolicySupported": true
        ]
        if let status { fields["myJoinStatus"] = status }
        return try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        guard identity == expectedIdentity, let account = expectedIdentity.accountID else { throw ClubActionWriteError.notSent(.unauthorized) }
        let detail = try await clubDetail(id: clubID)
        guard ClubActionAvailability.resolve(detail, viewerIsMerchant: viewerIsMerchant) == .available(action) else { throw ClubActionWriteError.eligibilityChanged }
        writeCount += 1
        if scenario == .denied { throw ClubActionWriteError.rejected(.init(code: 403, message: "Fixture server denied this request")) }
        if scenario == .delayed {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) }
            catch { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
        }
        // Server-side fixture membership stays with its captured account.
        if action == .apply { pending.insert(account) }
        else { joined[account] = action == .join; pending.remove(account) }
        writtenAccounts.insert(account); readsAfterWrite[account] = 0
        guard identity == expectedIdentity else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
        if scenario == .unknown { throw ClubActionWriteError.outcomeUnknown(.transport) }
        return ClubActionReceipt(state: action == .leave ? nil : action == .apply ? "pending" : "joined", message: nil)
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory {
        let detail = try await clubDetail(id: id)
        guard detail.canSeeMembers else { throw ClubReadFailure.membershipRequired }
        let rows = try JSONDecoder().decode([ClubMember].self, from: Data(#"[{"memberId":701,"nickname":"Fixture member","role":0,"isOwner":false}]"#.utf8))
        return ClubMemberDirectory(club: detail, members: rows)
    }
    func clubHome() async throws -> ClubHome { throw APIError.invalidRequest }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.invalidRequest }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.invalidRequest }
}
#endif
