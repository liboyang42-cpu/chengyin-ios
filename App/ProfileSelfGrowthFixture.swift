#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable final class ProfileSelfGrowthFixturePublicReader: SocialAccountReading, SquareReading {
    var identity = SocialAccountIdentity(accountID:81,epoch:1,role:"player")
    var presentationRevision: UInt64 = 1
    var scope = UUID()
    var isConfigured = true
    let isOfflineExample = true
    var isSignedIn: Bool { identity.accountID != nil }
    func publicProfile(memberID:Int) async throws -> SocialPublicProfile {
        try JSONDecoder().decode(SocialPublicProfile.self,from:Data("{\"id\":\(memberID),\"nickname\":\"Synthetic growth owner\"}".utf8))
    }
    func informationList() async throws -> [SocialInformation] { [] }
    func information(id:Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page:Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    func squareFeed(query:SquareQuery,cursor:SquareCursor?) async throws -> SquareFeedPage { .init(items:[],hasMore:false) }
    func squareDetail(id:Int) async throws -> SquarePost { throw APIError.notConfigured }
    func squareComments(postID:Int,pageNumber:Int) async throws -> SquareCommentPage { .init(items:[],pageNumber:pageNumber) }
}
@MainActor @Observable final class ProfileSelfGrowthFixtureReader: GrowthCenterReading {
    var scope=UUID();var isAuthenticated=true;var isConfigured=true;let isOfflineExample=true
    var reads=0,boardReads=0;var scenario:String
    private let source: GrowthCenterFixtureReader
    init(_ scenario:String="content") {
        self.scenario=scenario
        let mode:GrowthCenterFixtureReader.Scenario
        switch scenario { case "partialCenter":mode = .partialCenter;case "partialProgress":mode = .partialMileage;case "zero":mode = .empty;default:mode = .content }
        source=GrowthCenterFixtureReader(scenario:mode)
    }
    func overview() async throws -> GrowthCenterOverview {
        reads += 1
        if scenario == "failure",reads == 1 { throw APIError.httpStatus(503) }
        return try await source.overview()
    }
    func leaderboard(query:GrowthBoardQuery) async throws -> GrowthLeaderboard { boardReads += 1;return try await source.leaderboard(query:query) }
}
@MainActor struct ProfileSelfGrowthFixtureHost: View {
    private let social:ProfileSelfGrowthFixturePublicReader
    private let growth:ProfileSelfGrowthFixtureReader
    private let memberID:Int
    init(scenario:String="content") {
        let social=ProfileSelfGrowthFixturePublicReader(),growth=ProfileSelfGrowthFixtureReader(scenario)
        if scenario == "guest" { social.identity = .init(accountID:nil,epoch:1);growth.isAuthenticated=false }
        self.social=social;self.growth=growth;memberID=scenario == "other" ? 92 : 81
    }
    var body:some View {
        NavigationStack {
            SocialPublicProfileView(memberID:memberID,reader:social,squareReader:social,
                selfGrowthAccess:.init(reader:growth,owner:social.identity))
                .safeAreaInset(edge:.bottom) {
                    VStack {
                        Text(verbatim:"Growth reads: \(growth.reads)").accessibilityIdentifier("profile.selfGrowthFixture.reads")
                        Button("Retire synthetic account") {
                            social.identity = .init(accountID:82,epoch:2);social.presentationRevision += 1;growth.scope=UUID()
                        }.accessibilityIdentifier("profile.selfGrowthFixture.retire")
                    }.font(.caption)
                }
        }
    }
}
#endif
