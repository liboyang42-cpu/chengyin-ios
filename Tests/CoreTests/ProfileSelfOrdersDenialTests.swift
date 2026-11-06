import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfOrdersDenialTests: XCTestCase {
    private final class Social: SocialAccountReading {
        var identity=SocialAccountIdentity(accountID:81,epoch:1);var presentationRevision:UInt64=1
        var isConfigured=true;let isOfflineExample=false
        func publicProfile(memberID:Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws -> [SocialInformation] { [] }
        func information(id:Int) async throws -> SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page:Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    }
    private final class Orders: ProfileReading {
        var identity:ProfileReadIdentity? = .init(accountID:81,epoch:1);var isConfigured=true
        var rows:[ProfileOrder]=[];var error:Error?;var reads=0;var details=0;var waits=false
        var pending:CheckedContinuation<[ProfileOrder],Error>?
        func profileOrders() async throws -> [ProfileOrder] {
            reads += 1;if waits { return try await withCheckedThrowingContinuation { pending=$0 } }
            if let error { throw error };return rows
        }
        func profileOrder(id:Int) async throws -> ProfileOrder { details += 1;return rows[0] }
        func profileParticipants() async throws -> [ProfileParticipant] { XCTFail("out-of-scope read");return [] }
        func profileParticipant(id:Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
        func profileBadges() async throws -> ProfileBadgeWall { XCTFail("out-of-scope read");throw APIError.notConfigured }
    }
    private let social=Social(),orders=Orders(),model=ProfileSelfOrdersController()
    private var current=true
    private func row(_ id:Int=1,member:Int=81) throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self,from:Data("{\"id\":\(id),\"memberId\":\(member),\"cmsTopic\":{\"name\":\"Synthetic order\"}}".utf8))
    }
    private func context(member:Int=81)->ProfileSelfOrdersContext? {
        .capture(memberID:member,social:social,orders:orders,owner:social.identity,ordersOwner:orders.identity,isCurrent:current)
    }
    private func reader() throws -> ProfileSelfOrdersScopedReader {
        .init(context:try XCTUnwrap(context()),social:social,orders:orders,isCurrent:{ self.current })
    }
    private func waitPending() async { for _ in 0..<100 where orders.pending == nil { await Task.yield() };XCTAssertNotNil(orders.pending) }
    func testExplicitDenialClearsPrivateSummaryWithoutCreatingEmptySuccess() async throws {
        let r = try reader()
        let failures: [Error] = [ProfileReadFailure(httpStatus: 403),
            ProfileReadFailure(code: 403, message: "Denied"), APIError.httpStatus(403)]
        for failure in failures {
            orders.error = nil; orders.rows = [try row()]
            await model.load(reader: r)
            XCTAssertEqual(model.rows?.count, 1)
            orders.error = failure
            await model.load(reader: r)
            XCTAssertNil(model.rows)
            XCTAssertEqual(model.issue, .readFailed)
            XCTAssertFalse(model.canOpen(orders.rows[0], reader: r))
            XCTAssertTrue(r.isCurrentContext)
        }
        XCTAssertEqual(orders.reads, 6)
        XCTAssertEqual(orders.details, 0)
    }
    func testOrdinaryNetworkFailureKeepsStaleRowsButCannotOpen() async throws {
        let r = try reader(); orders.rows = [try row()]
        await model.load(reader: r)
        let failures: [Error] = [APIError.httpStatus(503), ProfileReadFailure(httpStatus: 503),
                                 URLError(.timedOut)]
        for failure in failures {
            orders.error = failure
            await model.load(reader: r)
            XCTAssertEqual(model.rows?.count, 1)
            XCTAssertEqual(model.issue, .readFailed)
            XCTAssertFalse(model.canOpen(orders.rows[0], reader: r))
        }
        XCTAssertEqual(orders.reads, 4)
    }
    func testExplicitRecoveryUsesFreshResultAfterDenial() async throws {
        let r = try reader(); orders.rows = [try row()]
        await model.load(reader: r)
        orders.error = ProfileReadFailure(code: 403)
        await model.load(reader: r)
        XCTAssertNil(model.rows); XCTAssertEqual(orders.reads, 2)
        orders.error = nil; orders.rows = [try row(9)]
        await model.load(reader: r)
        XCTAssertEqual(model.rows?.map(\.id), [9]); XCTAssertNil(model.issue)
        XCTAssertTrue(model.canOpen(orders.rows[0], reader: r))
        XCTAssertEqual(orders.reads, 3)
    }
}
