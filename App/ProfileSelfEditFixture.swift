#if DEBUG
import SwiftUI
import Observation

/// One synthetic backing store drives the real existing editor and real public-profile view.
@MainActor @Observable final class ProfileSelfEditFixtureData: SocialAccountReading, SquareReading, ProfileEditServing {
    var identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    var presentationRevision: UInt64 = 1
    var scope = UUID()
    var isConfigured = true
    let isOfflineExample = true
    var isSignedIn: Bool { identity.accountID != nil }
    var editSession: ProfileEditSession?
    var nickname = "Synthetic profile"
    var introduction = "Original public introduction"
    var publicReads = 0, editorReads = 0, writes = 0
    var failNextPublic = false
    init(scenario: String = "own") {
        editSession = try! .init(accountID: 81, epoch: 1, token: "synthetic-not-a-credential", viewerRevision: 1)
        if scenario == "guest" { identity = .init(accountID: nil, epoch: 1); editSession = nil }
    }
    func retireAccount() { identity = .init(accountID: 82, epoch: 2); presentationRevision += 1; editSession = nil; scope = UUID() }
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile {
        publicReads += 1
        if failNextPublic { failNextPublic = false; throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(SocialPublicProfile.self, from: JSONSerialization.data(withJSONObject:
            ["id":memberID,"nickname":nickname,"introduction":introduction,"casePics":"","sysCategoryList":[]]))
    }
    func read(token: String) async throws -> ProfileEditSnapshot {
        editorReads += 1
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id":81,"nickname":nickname,"introduction":introduction,"avatar":"","wechat":"","casePics":"","tagIds":"","caseIntroducton":""]))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        writes += 1; nickname = payload.name; introduction = payload.introduction
    }
    func informationList() async throws -> [SocialInformation] { [] }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage { .init(items:[],hasMore:false) }
    func squareDetail(id: Int) async throws -> SquarePost { throw APIError.notConfigured }
    func squareComments(postID: Int,pageNumber: Int) async throws -> SquareCommentPage { .init(items:[],pageNumber:pageNumber) }
}
@MainActor struct ProfileSelfEditFixtureHost: View {
    private let data: ProfileSelfEditFixtureData
    private let coordinator: ProfileEditCoordinator
    private let memberID: Int
    init(scenario: String = "own") {
        let data = ProfileSelfEditFixtureData(scenario: scenario)
        self.data = data; memberID = scenario == "other" ? 92 : 81
        coordinator = .init(service: data, currentSession: { data.editSession })
    }
    var body: some View {
        NavigationStack {
            SocialPublicProfileView(memberID: memberID, reader: data, squareReader: data,
                selfEditAccess: .init(coordinator: coordinator, sessionRevision: data.presentationRevision))
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        Text(verbatim: "Reads: \(data.publicReads) Writes: \(data.writes)").accessibilityIdentifier("profile.selfEditFixture.counts")
                        Button("Fail next synthetic public read") { data.failNextPublic = true }.accessibilityIdentifier("profile.selfEditFixture.failRead")
                        Button("Retire synthetic account") { data.retireAccount() }.accessibilityIdentifier("profile.selfEditFixture.retire")
                    }.font(.caption)
                }
        }
    }
}
#endif
