#if DEBUG
import SwiftUI

/// Synthetic, in-memory fixtures only. Never creates a host, transport or credential.
enum ClubFixtureScenario: String {
    case owner, member, visitor, administrator, empty, retry, forbidden, guest, missingMembers
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-club-fixture"), arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

@MainActor
struct ClubFixtureRootView: View {
    @StateObject private var reader: ClubFixtureReader
    init(scenario: ClubFixtureScenario) { _reader = StateObject(wrappedValue: ClubFixtureReader(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("club.fixtureNotice").font(.caption.bold()).accessibilityIdentifier("club.fixture.notice")
                HStack {
                    Button("club.fixtureSwitchAccount") { reader.switchAccount() }.accessibilityIdentifier("club.fixture.switchAccount")
                    Button("club.fixtureSignOut") { reader.signOut() }.accessibilityIdentifier("club.fixture.signOut")
                }.font(.caption)
            }.padding(8).frame(maxWidth: .infinity).background(.yellow.opacity(0.15))
            NavigationStack {
                ClubHomeView(reader: reader, onSignIn: { reader.signIn() }, topicDestination: { id in
                    AnyView(Text(verbatim: "Synthetic topic \(id)")
                        .accessibilityIdentifier("club.fixture.topic.\(id)")
                        .navigationTitle(Text(verbatim: "Synthetic topic")))
                })
            }.id(reader.clubIdentity)
        }
    }
}

@MainActor
private final class ClubFixtureReader: ObservableObject, ClubReading {
    let isClubConfigured = true
    @Published private(set) var clubIdentity: ClubReadIdentity
    private let scenario: ClubFixtureScenario
    private var firstHomeAttempt = true
    private var alternateAccount = false
    init(scenario: ClubFixtureScenario) {
        self.scenario = scenario
        clubIdentity = .init(accountID: scenario == .guest ? nil : 701, epoch: 0)
    }
    func signIn() { clubIdentity = .init(accountID: alternateAccount ? 702 : 701, epoch: clubIdentity.epoch &+ 1) }
    func signOut() { clubIdentity = .init(accountID: nil, epoch: clubIdentity.epoch &+ 1) }
    func switchAccount() { alternateAccount.toggle(); signIn() }
    func clubHome() async throws -> ClubHome {
        try authorize()
        if scenario == .retry && firstHomeAttempt { firstHomeAttempt = false; throw URLError(.notConnectedToInternet) }
        if scenario == .empty { return try decode(["owned": [], "joined": [], "nearby": [], "events": []]) }
        let mine = clubJSON(id: 81), nearby = clubJSON(id: 82)
        let owned = mine["isOwner"] as? Bool == true
        let joined = mine["isJoined"] as? Bool == true
        return try decode([
            "owned": owned ? [mine] : [], "joined": !owned && joined ? [mine] : [],
            "nearby": !owned && !joined ? [mine, nearby] : [nearby],
            "events": owned ? [["id": 91, "clubId": 81, "title": "Fixture club outing"]] : []
        ])
    }
    func clubOwned() async throws -> [ClubRecord] {
        try authorize()
        if scenario == .empty { return [] }
        let value = clubJSON(id: 81)
        return try decode(value["isOwner"] as? Bool == true ? [value] : [])
    }
    func clubDirectory(name: String?) async throws -> [ClubRecord] {
        try authorize()
        if scenario == .empty { return [] }
        let rows: [ClubRecord] = try decode([clubJSON(id: 81), clubJSON(id: 82)])
        guard let name, !name.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        try authorize()
        guard [81, 82].contains(id) else { throw ClubReadFailure.rejected(code: 404, message: "Fixture club is unavailable") }
        return try decode(clubJSON(id: id))
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory {
        let club = try await clubDetail(id: id)
        guard club.canSeeMembers else { throw ClubReadFailure.membershipRequired }
        let members: [ClubMember]
        if scenario == .missingMembers { members = [] }
        else {
            members = try decode([
                ["memberId": 701, "nickname": "Fixture creator", "role": 1, "isOwner": true],
                ["memberId": 703, "nickname": "Fixture administrator", "role": 1, "isOwner": false],
                ["memberId": 704, "nickname": "", "role": 0, "isOwner": false]
            ])
        }
        return ClubMemberDirectory(club: club, members: members)
    }
    private func authorize() throws {
        try Task.checkCancellation()
        guard clubIdentity.isSignedIn else { throw ClubReadFailure.unauthorized(message: nil) }
        if scenario == .forbidden { throw ClubReadFailure.forbidden(message: "Fixture access was denied by the server") }
    }
    private func clubJSON(id: Int) -> [String: Any] {
        let owned = id == 81 && !alternateAccount && [.owner, .retry, .missingMembers].contains(scenario)
        let joined = id == 81 && !alternateAccount && (owned || scenario == .member)
        return [
            "id": id, "name": alternateAccount ? "Second account fixture club \(id)" : "Fixture club \(id)",
            "description": "Offline sample club description.", "style": "An in-memory read-only example",
            "city": "Fixture city", "leaderName": "Fixture creator", "clubType": "Fixture type",
            "memberCount": 3, "isOwner": owned, "isJoined": joined,
            "viewerIsAdmin": id == 81 && scenario == .administrator && !alternateAccount,
            "activityPrefs": "walking,photography", "myJoinStatus": joined ? 1 : 2,
            "joinPolicy": 1, "joinPolicySupported": true, "level": 2
        ]
    }
    private func decode<T: Decodable>(_ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
