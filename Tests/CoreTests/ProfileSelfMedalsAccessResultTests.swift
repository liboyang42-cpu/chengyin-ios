import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProfileSelfMedalsAccessResultTests: XCTestCase {
    private func rows() throws -> [ProfileMedal] {
        try JSONDecoder().decode([ProfileMedal].self, from: Data(#"[{"badgeCode":"walker","medalName":"Achievement","kind":"achievement"}]"#.utf8))
    }
    func testDirectDenialOrUnavailableClearsPriorMedalsButNotAsEmptySuccess() async throws {
        for error in [ProfileReadFailure(code: 403) as Error, ProfileReadFailure(httpStatus: 403), APIError.httpStatus(403), APIError.notConfigured] {
            let reader = AccessMedalReader(), social = AccessMedalAccount(), model = ProfileSelfMedalsController()
            reader.wall = .init(identities: [], medals: try rows())
            await model.load(memberID: 81, accountReader: social, profileReader: reader)
            reader.error = error
            await model.load(memberID: 81, accountReader: social, profileReader: reader)
            XCTAssertNil(model.medals); XCTAssertEqual(model.issue, .readFailed)
        }
    }
    func testRestrictedPartialClearsOldMedalsAndOrdinaryPartialRetainsThem() async throws {
        for restriction in [nil, ProfileMedalReadRestriction.denied, .unavailable] {
            let reader = AccessMedalReader(), social = AccessMedalAccount(), model = ProfileSelfMedalsController()
            reader.wall = .init(identities: [], medals: try rows())
            await model.load(memberID: 81, accountReader: social, profileReader: reader)
            reader.wall = .init(identities: [], medals: nil, medalReadRestriction: restriction)
            await model.load(memberID: 81, accountReader: social, profileReader: reader)
            if restriction == nil { XCTAssertEqual(model.medals?.count, 1) }
            else { XCTAssertNil(model.medals) }
            XCTAssertEqual(model.issue, .partial)
        }
    }
    func testOrdinaryNetworkFailureRetainsRowsAndFreshSuccessRecovers() async throws {
        let reader = AccessMedalReader(), social = AccessMedalAccount(), model = ProfileSelfMedalsController()
        reader.wall = .init(identities: [], medals: try rows())
        await model.load(memberID: 81, accountReader: social, profileReader: reader)
        reader.error = URLError(.timedOut)
        await model.load(memberID: 81, accountReader: social, profileReader: reader)
        XCTAssertEqual(model.medals?.count, 1); XCTAssertEqual(model.issue, .readFailed)
        reader.error = nil; reader.wall = .init(identities: [], medals: [])
        await model.load(memberID: 81, accountReader: social, profileReader: reader)
        XCTAssertEqual(model.medals, []); XCTAssertNil(model.issue)
    }
    func testRealServiceKeepsApprovedIdentitiesAndClassifiesOnlyMedalFailure() async throws {
        for code in [403, 503] {
            let wire = AccessMedalWire(code: code)
            let service = ProfileService(configuration: try APIConfiguration(baseURL: URL(string: "https://medals.example/native")!), transport: wire)
            let result = try await service.badgeWall(token: "synthetic")
            XCTAssertEqual(result.identities.map(\.badgeCode), ["ID"])
            XCTAssertNil(result.medals); XCTAssertTrue(result.isPartial)
            XCTAssertEqual(result.medalReadRestriction, code == 403 ? .denied : nil)
        }
    }
}

@MainActor private final class AccessMedalAccount: SocialAccountReading {
    let identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    let presentationRevision: UInt64 = 1
    let isConfigured = true, isOfflineExample = false
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    func informationList() async throws -> [SocialInformation] { [] }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}
@MainActor private final class AccessMedalReader: ProfileReading {
    let identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1)
    let isConfigured = true
    var wall = ProfileBadgeWall(identities: [], medals: [])
    var error: Error?
    func profileBadges() async throws -> ProfileBadgeWall { if let error { throw error }; return wall }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileParticipants() async throws -> [ProfileParticipant] { [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
}
private actor AccessMedalWire: HTTPTransport {
    let code: Int
    init(code: Int) { self.code = code }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.path.hasSuffix("badge/wall-v2") == true {
            return (Data(#"{"code":200,"data":{"identity":[{"badgeCode":"ID","unlocked":true}]}}"#.utf8), 200)
        }
        return (Data("{\"code\":\(code),\"msg\":\"Unavailable\"}".utf8), code)
    }
}
