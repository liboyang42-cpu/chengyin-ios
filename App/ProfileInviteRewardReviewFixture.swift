#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable final class ProfileInviteRewardReviewFixtureReader: SocialAccountReading, SquareReading {
    var identity=SocialAccountIdentity(accountID:81,epoch:1,role:"player")
    var presentationRevision:UInt64=1;var scope=UUID();var isConfigured=true
    let isOfflineExample=true
    var isSignedIn:Bool { identity.accountID != nil }
    var reads=0;var scenario:String
    init(_ scenario:String="complete") {self.scenario=scenario;if scenario == "guest" {identity = .init(accountID:nil,epoch:1)}}
    func publicProfile(memberID:Int) async throws -> SocialPublicProfile {try JSONDecoder().decode(SocialPublicProfile.self,from:Data("{\"id\":\(memberID),\"nickname\":\"Synthetic invited member\"}".utf8))}
    func informationList() async throws -> [SocialInformation] {[]}
    func information(id:Int) async throws -> SocialInformation {throw APIError.notConfigured}
    func invitationHistory(page:Int) async throws -> SocialInviteHistory {
        reads += 1
        if scenario == "failure" && reads == 1 {throw APIError.httpStatus(503)}
        let raw=page == 1 ? #"[{"id":201,"nickname":"Synthetic Ada","createTime":"2026-10-01 10:00:00"},{"id":202,"nickname":"Synthetic Bea","createTime":"2026-10-02 10:00:00"}]"# : #"[{"id":203,"nickname":"Synthetic Cy","createTime":"2026-09-01 10:00:00"}]"#
        let members=try JSONDecoder().decode([SocialInvitedMember].self,from:Data(raw.utf8))
        let ledgerRows = #"[{"eventType":5,"eventId":"201","changePoints":"1.25"},{"eventType":5,"eventId":"0201","changePoints":"1.25"},{"eventType":5,"eventId":"202","changePoints":"5.25"},{"eventType":5,"eventId":"999","changePoints":"3.25"}]"#
        let total=(scenario == "partial" && reads == 1) ? 201 : scenario == "invalid" ? 3 : 4
        let ledger=scenario == "zero" ? #"{"rows":[],"total":0}"# : "{\"rows\":\(ledgerRows),\"total\":\(total)}"
        let scan = scenario == "unavailable" && reads == 1 ? nil : try JSONDecoder().decode(SocialRewardScan.self,from:Data(ledger.utf8))
        return .init(page:.init(members:members,total:3,pageNumber:page,pageSize:2),rewardScan:scan)
    }
    func squareFeed(query:SquareQuery,cursor:SquareCursor?) async throws -> SquareFeedPage {.init(items:[],hasMore:false)}
    func squareDetail(id:Int) async throws -> SquarePost {throw APIError.notConfigured}
    func squareComments(postID:Int,pageNumber:Int) async throws -> SquareCommentPage {.init(items:[],pageNumber:pageNumber)}
}
@MainActor struct ProfileInviteRewardReviewFixtureHost: View {
    @State private var reader:ProfileInviteRewardReviewFixtureReader
    init(scenario:String="complete") {_reader=State(initialValue:.init(scenario))}
    var body:some View {
        NavigationStack {
            SocialInviteHistoryView(reader:reader,squareReader:reader)
                .safeAreaInset(edge:.bottom) {
                    VStack {
                        Text(verbatim:"Invitation reads: \(reader.reads)").accessibilityIdentifier("profile.inviteRewardsFixture.reads")
                        Button("Retire synthetic account") {
                            reader.identity = .init(accountID:nil,epoch:2);reader.presentationRevision += 1;reader.scope=UUID()
                        }.accessibilityIdentifier("profile.inviteRewardsFixture.retire")
                    }.font(.caption)
                }
        }
    }
}
#endif
