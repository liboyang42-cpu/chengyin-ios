#if DEBUG
import SwiftUI
import Observation

/// Dedicated local fixture. The production reader/service and central launch router are untouched.
@MainActor @Observable final class ProfileAuthorPostsRefreshFixtureReader: SocialAccountReading, SquareReading {
    var identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    var presentationRevision: UInt64 = 0
    var scope = UUID()
    var isConfigured = true
    let isOfflineExample = true
    var isSignedIn: Bool { identity.accountID != nil }
    var scenario: String
    private(set) var reads = 0
    private var firstPages = 0
    private var morePages = 0
    init(scenario: String = "content") { self.scenario = scenario }
    func switchAccount() {
        identity = .init(accountID: 82, epoch: identity.epoch + 1, role: "player")
        presentationRevision &+= 1; scope = UUID()
    }
    func signOut() {
        identity = .init(accountID: nil, epoch: identity.epoch + 1)
        presentationRevision &+= 1; scope = UUID()
    }
    func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage {
        reads += 1
        if cursor == nil { firstPages += 1 } else { morePages += 1 }
        let first = firstPages, more = morePages, capturedAccount = identity.accountID
        if scenario == "delayed" { try? await Task.sleep(nanoseconds: 800_000_000) }
        if scenario == "refreshFailure", cursor == nil, first == 2 { throw APIError.httpStatus(503) }
        if scenario == "moreFailure", cursor != nil, more == 1 { throw APIError.httpStatus(503) }
        if scenario == "denied", first >= 2 { throw APIError.httpStatus(403) }
        if scenario == "emptyRefresh", cursor == nil, first >= 2 { return .init(items: [], hasMore: false) }
        let id = capturedAccount == 82 ? 821 : (cursor == nil ? (first == 1 ? 101 : 301) : 201)
        let row = try Self.post(id: id, memberID: query.authorID ?? 91)
        return .init(items: [row], hasMore: cursor == nil,
                     nextCursor: cursor == nil && scenario != "invalidCursor" ? .init(id: id) : nil)
    }
    static func post(id: Int, memberID: Int = 91) throws -> SquarePost {
        let json = try JSONSerialization.data(withJSONObject: ["id": id, "authorId": memberID, "body": "Synthetic author post \(id)"])
        return try JSONDecoder().decode(SquarePost.self, from: json).qualified(as: .communityV1)
    }
    func squareDetail(id: Int) async throws -> SquarePost { try Self.post(id: id) }
    func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage { .init(items: [], pageNumber: pageNumber) }
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}

@MainActor struct ProfileAuthorPostsRefreshFixtureHost: View {
    @State private var reader: ProfileAuthorPostsRefreshFixtureReader
    @State private var showsPosts = true
    init(scenario: String = "content") {
        _reader = State(initialValue: ProfileAuthorPostsRefreshFixtureReader(scenario: scenario))
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: "Reads: \(reader.reads)").accessibilityIdentifier("profile.postsFixture.reads")
                    Button("Switch synthetic account") { reader.switchAccount() }.accessibilityIdentifier("profile.postsFixture.switch")
                    Button("Sign out synthetic account") { reader.signOut() }.accessibilityIdentifier("profile.postsFixture.logout")
                    Button("Toggle author posts") { showsPosts.toggle() }.accessibilityIdentifier("profile.postsFixture.toggle")
                }
                if showsPosts { ProfileAuthorPostsSection(memberID: 91, accountReader: reader, squareReader: reader) }
            }
        }
    }
}
#endif
