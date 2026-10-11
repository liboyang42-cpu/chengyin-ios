#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable final class ProfileSelfMedalsFixturePublicReader: SocialAccountReading, SquareReading {
    var identity = SocialAccountIdentity(accountID:81,epoch:1,role:"player")
    var presentationRevision: UInt64 = 1
    var scope = UUID()
    var isConfigured = true
    let isOfflineExample = true
    var isSignedIn: Bool { identity.accountID != nil }
    func publicProfile(memberID:Int) async throws -> SocialPublicProfile {
        try JSONDecoder().decode(SocialPublicProfile.self,from:Data("{\"id\":\(memberID),\"nickname\":\"Synthetic medal owner\"}".utf8))
    }
    func informationList() async throws -> [SocialInformation] { [] }
    func information(id:Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page:Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    func squareFeed(query:SquareQuery,cursor:SquareCursor?) async throws -> SquareFeedPage { .init(items:[],hasMore:false) }
    func squareDetail(id:Int) async throws -> SquarePost { throw APIError.notConfigured }
    func squareComments(postID:Int,pageNumber:Int) async throws -> SquareCommentPage { .init(items:[],pageNumber:pageNumber) }
}
@MainActor @Observable final class ProfileSelfMedalsFixtureReader: ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID:81,epoch:1)
    var isConfigured = true
    var reads = 0
    var scenario: String
    init(_ scenario:String="content") { self.scenario=scenario }
    static func rows() throws -> [ProfileMedal] {
        try JSONDecoder().decode([ProfileMedal].self,from:Data(#"[{"templateId":101,"medalName":"Synthetic city medal","getTime":"2026-01-01","kind":"city"},{"badgeCode":"walker","medalName":"Synthetic achievement medal","kind":"achievement"}]"#.utf8))
    }
    func profileBadges() async throws -> ProfileBadgeWall {
        reads += 1;let count=reads
        if scenario == "delayed" { try? await Task.sleep(nanoseconds:800_000_000) }
        if scenario == "failure",count == 1 { throw APIError.httpStatus(503) }
        if scenario == "refreshFailure",count == 2 { throw APIError.httpStatus(503) }
        if scenario == "partial",count == 1 { return .init(identities:[],medals:nil) }
        let empty=scenario == "empty" || (scenario == "emptyRefresh" && count >= 2)
        let medals: [ProfileMedal]
        if empty { medals = [] } else { medals = try Self.rows() }
        return .init(identities:[],medals:medals)
    }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id:Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileParticipants() async throws -> [ProfileParticipant] { [] }
    func profileParticipant(id:Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
}
@MainActor struct ProfileSelfMedalsFixtureHost: View {
    private let social: ProfileSelfMedalsFixturePublicReader
    private let reader: ProfileSelfMedalsFixtureReader
    private let memberID: Int
    init(scenario:String="content") {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader(scenario)
        if scenario == "guest" { social.identity = .init(accountID:nil,epoch:1);reader.identity=nil }
        self.social=social;self.reader=reader;memberID=scenario == "other" ? 92 : 81
    }
    var body: some View {
        NavigationStack {
            SocialPublicProfileView(memberID:memberID,reader:social,squareReader:social,selfMedalsReader:reader)
                .safeAreaInset(edge:.bottom) {
                    VStack {
                        Text(verbatim:"Medal reads: \(reader.reads)").accessibilityIdentifier("profile.selfMedalsFixture.reads")
                        Button("Retire synthetic account") {
                            social.identity = .init(accountID:82,epoch:2);social.presentationRevision += 1
                            reader.identity = .init(accountID:82,epoch:2)
                        }.accessibilityIdentifier("profile.selfMedalsFixture.retire")
                    }.font(.caption)
                }
        }
    }
}
#endif
