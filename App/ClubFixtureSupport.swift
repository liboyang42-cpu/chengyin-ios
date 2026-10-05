#if DEBUG
import SwiftUI

/// Synthetic, in-memory fixtures only. Never creates a host, transport or credential.
enum ClubFixtureScenario: String {
    case owner, member, visitor, administrator, empty, retry, forbidden, guest, missingMembers
    case customerOwner, customerAdministrator, customerDenied, customerInvalidHistory
    case merchantLocality, merchantLocalityRetry, merchantLocalityUnknown, merchantLocalityEmpty, merchantLocalityDelayed
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-club-fixture"), arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

@MainActor
struct ClubFixtureRootView: View {
    private var profileReader: SocialAccountFixtureReader { reader.profileReader }
    private var squareReader: SquareFixtureReader { reader.squareReader }
    private var governanceAccess: ClubGovernanceFixtureAccess { reader.governanceAccess }
    private let scenario: ClubFixtureScenario
    @State private var viewerRevision: UInt64 = 0
    @StateObject private var reader: ClubFixtureReader
    init(scenario: ClubFixtureScenario) { self.scenario = scenario; _reader = StateObject(wrappedValue: ClubFixtureReader(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("club.fixtureNotice").font(.caption.bold()).accessibilityIdentifier("club.fixture.notice")
                HStack {
                    Button("club.fixtureSwitchAccount") { reader.switchAccount() }.accessibilityIdentifier("club.fixture.switchAccount")
                    Button("club.fixtureSignOut") { reader.signOut() }.accessibilityIdentifier("club.fixture.signOut")
                    if reader.isLocalityFixture {
                        Button("Toggle player / merchant") { reader.toggleLocalityRole() }.accessibilityIdentifier("club.fixture.toggleLocalityRole")
                        Button("Switch merchant") { reader.switchLocalityMerchant() }.accessibilityIdentifier("club.fixture.switchMerchant")
                    }
                    if [.customerOwner, .customerAdministrator, .customerDenied, .customerInvalidHistory].contains(scenario) {
                        Button("Revoke fixture role") { governanceAccess.readFailure = .forbidden; viewerRevision &+= 1 }
                            .accessibilityIdentifier("club.fixture.revokeRole")
                        Button("Restore fixture role") { governanceAccess.readFailure = nil; viewerRevision &+= 1 }
                            .accessibilityIdentifier("club.fixture.restoreRole")
                    }
                }.font(.caption)
                if scenario == .merchantLocalityDelayed {
                    HStack {
                        Text(verbatim: String(reader.pendingLocalityCount)).accessibilityIdentifier("club.fixture.locality.pending")
                        Button("Release oldest locality") { reader.releaseLocality() }.disabled(reader.pendingLocalityCount == 0)
                            .accessibilityIdentifier("club.fixture.locality.release")
                        Button("Fail oldest locality") { reader.releaseLocality(failing: true) }.disabled(reader.pendingLocalityCount == 0)
                            .accessibilityIdentifier("club.fixture.locality.fail")
                    }.font(.caption)
                }
            }.padding(8).frame(maxWidth: .infinity).background(.yellow.opacity(0.15))
            NavigationStack {
                if [.customerOwner, .customerAdministrator, .customerDenied, .customerInvalidHistory].contains(scenario) {
                    ClubMembersView(id: 81, reader: reader,
                                    profile: .init(reader: profileReader, squareReader: squareReader),
                                    governance: .init(viewerRevision: viewerRevision, access: governanceAccess, coordinator: ClubGovernanceCoordinator(access: governanceAccess), topicDestination: { id in
                                        AnyView(Text(verbatim: "Synthetic history topic \(id)").accessibilityIdentifier("club.fixture.historyTopic.\(id)"))
                                    }))
                } else {
                ClubHomeView(reader: reader, onSignIn: { reader.signIn() }, topicDestination: { id in
                    AnyView(Text(verbatim: "Synthetic topic \(id)")
                        .accessibilityIdentifier("club.fixture.topic.\(id)")
                        .navigationTitle(Text(verbatim: "Synthetic topic")))
                })
                }
            }
            .environment(\.clubEnrollmentProfile, ClubEnrollmentProfileContext(reader: profileReader, squareReader: squareReader))
            .id(reader.clubIdentity)
        }
    }

}

@MainActor
final class ClubFixtureReader: ObservableObject, ClubReading {
    let isClubConfigured = true
    // Own companion readers with the same lifetime as the published club identity.
    let profileReader = SocialAccountFixtureReader(.content)
    let squareReader = SquareFixtureReader()
    let governanceAccess = ClubGovernanceFixtureAccess()
    @Published private(set) var clubIdentity: ClubReadIdentity
    private let scenario: ClubFixtureScenario
    var isLocalityFixture: Bool {
        [.merchantLocality, .merchantLocalityRetry, .merchantLocalityUnknown, .merchantLocalityEmpty, .merchantLocalityDelayed].contains(scenario)
    }
    @Published private var localityRole = "merchant"
    @Published private var localityRevision: UInt64 = 0
    @Published private var alternateMerchant = false
    @Published private(set) var pendingLocalityCount = 0
    private var firstLocalityAttempt = true
    private var pendingLocalities: [(CheckedContinuation<MerchantClubLocality, Error>, MerchantClubLocality)] = []
    var clubDiscoveryScope: ClubDiscoveryScope {
        .init(identity: clubIdentity, role: isLocalityFixture ? localityRole : "player",
              viewerRevision: localityRevision, merchantID: isLocalityFixture ? (alternateMerchant ? 32 : 31) : nil,
              merchantRevision: localityRevision)
    }
    func toggleLocalityRole() { localityRevision &+= 1; localityRole = localityRole == "merchant" ? "player" : "merchant" }
    func switchLocalityMerchant() { localityRevision &+= 1; alternateMerchant.toggle() }
    func clubMerchantLocality() async throws -> MerchantClubLocality {
        guard isLocalityFixture, clubDiscoveryScope.isMerchantViewer else { throw APIError.notConfigured }
        let first = firstLocalityAttempt; firstLocalityAttempt = false
        if scenario == .merchantLocalityRetry && first { throw URLError(.notConnectedToInternet) }
        let city = scenario == .merchantLocalityEmpty ? "Other City" : (alternateMerchant ? "B City" : "A City")
        let value: MerchantClubLocality = try decode(["id": alternateMerchant ? 32 : 31,
            "city": scenario == .merchantLocalityUnknown && first ? "" : city])
        if scenario == .merchantLocalityDelayed {
            return try await withCheckedThrowingContinuation { continuation in
                pendingLocalities.append((continuation, value)); pendingLocalityCount = pendingLocalities.count
            }
        }
        return value
    }
    func releaseLocality(failing: Bool = false) {
        guard !pendingLocalities.isEmpty else { return }
        let (continuation, value) = pendingLocalities.removeFirst(); pendingLocalityCount = pendingLocalities.count
        if failing { continuation.resume(throwing: APIError.unauthorized) }
        else { continuation.resume(returning: value) }
    }
    private var firstHomeAttempt = true
    private var alternateAccount = false
    init(scenario: ClubFixtureScenario) {
        self.scenario = scenario
        clubIdentity = .init(accountID: scenario == .guest ? nil : 701, epoch: 0)
        synchronizeCompanions(with: clubIdentity)
    }
    func signIn() { setIdentity(.init(accountID: alternateAccount ? 702 : 701, epoch: clubIdentity.epoch &+ 1)) }
    func signOut() { setIdentity(.init(accountID: nil, epoch: clubIdentity.epoch &+ 1)) }
    func switchAccount() { alternateAccount.toggle(); signIn() }
    private func setIdentity(_ identity: ClubReadIdentity) {
        // Synchronize non-observable companions before publishing the new render identity.
        synchronizeCompanions(with: identity)
        clubIdentity = identity
    }
    private func synchronizeCompanions(with identity: ClubReadIdentity) {
        governanceAccess.identity = identity
        governanceAccess.allowsOfflineWrites = false
        governanceAccess.readFailure = scenario == .customerDenied ? .forbidden : nil
        if scenario == .customerInvalidHistory {
            var value = ClubGovernanceFixtures.value(.customer).object ?? [:]
            value["records"] = .array([
                .object(["key": .string("missing-topic"), "title": .string("Missing topic history"), "statusCode": .string("PENDING")]),
                .object(["key": .string("foreign-scope"), "topicId": .integer(92), "memberId": .integer(705), "title": .string("Foreign scope history"), "statusCode": .string("REGISTERED")])
            ])
            governanceAccess.overrideValue[.customer] = .object(value)
        }
        profileReader.identity = .init(accountID: identity.accountID, epoch: identity.epoch, role: "player")
    }
    func clubHome() async throws -> ClubHome {
        try authorize()
        if scenario == .retry && firstHomeAttempt { firstHomeAttempt = false; throw URLError(.notConnectedToInternet) }
        if scenario == .empty { return try decode(["owned": [], "joined": [], "nearby": [], "events": []]) }
        if isLocalityFixture {
            return try decode([
                "owned": [["id": 81, "name": "Owned fixture", "isOwner": true]],
                "joined": [["id": 82, "name": "Joined fixture", "isJoined": true]],
                "nearby": [localityClub(id: 83), localityClub(id: 84), localityClub(id: 85)], "events": []
            ])
        }
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
        if isLocalityFixture, [81, 82, 83, 84, 85].contains(id) { return try decode(localityClub(id: id)) }
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
                ["memberId": 701, "nickname": "Fixture creator", "role": 1, "isOwner": true,
                 "levelId": 7, "joinTime": "2026-01-01 09:00:00"],
                ["memberId": 703, "nickname": "Fixture administrator", "role": 1, "isOwner": false,
                 "levelId": 4, "joinTime": "2026-02-03 10:15:00"],
                ["memberId": 704, "nickname": "", "role": 0, "isOwner": false,
                 "levelId": 0, "joinTime": "  "]
            ])
        }
        return ClubMemberDirectory(club: club, members: members)
    }
    private func authorize() throws {
        try Task.checkCancellation()
        guard clubIdentity.isSignedIn else { throw ClubReadFailure.unauthorized(message: nil) }
        if scenario == .forbidden { throw ClubReadFailure.forbidden(message: "Fixture access was denied by the server") }
    }
    private func localityClub(id: Int) -> [String: Any] {
        var value: [String: Any] = ["id": id, "name": "Locality fixture club \(id)"]
        if id == 83 { value["city"] = "A City" }
        if id == 84 { value["city"] = "B City" }
        return value
    }
    private func clubJSON(id: Int) -> [String: Any] {
        let owned = id == 81 && !alternateAccount && [.owner, .retry, .missingMembers, .customerOwner, .customerDenied, .customerInvalidHistory].contains(scenario)
        let joined = id == 81 && !alternateAccount && (owned || [.member, .customerAdministrator].contains(scenario))
        return [
            "id": id, "name": alternateAccount ? "Second account fixture club \(id)" : "Fixture club \(id)",
            "description": "Offline sample club description.", "style": "An in-memory read-only example",
            "city": "Fixture city", "leaderName": "Fixture creator", "clubType": "Fixture type",
            "memberCount": 3, "isOwner": owned, "isJoined": joined,
            "viewerIsAdmin": id == 81 && [.administrator, .customerAdministrator].contains(scenario) && !alternateAccount,
            "activityPrefs": "walking,photography", "myJoinStatus": joined ? 1 : 2,
            "joinPolicy": 1, "joinPolicySupported": true, "level": 2
        ]
    }
    private func decode<T: Decodable>(_ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
