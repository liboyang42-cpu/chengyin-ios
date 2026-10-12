import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfOrdersTests: XCTestCase {
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
    func testPreviewKeepsExactlyFirstEightWithoutSorting() throws {
        let rows=try (1...10).reversed().map { try row($0) }
        XCTAssertEqual(ProfileSelfOrdersPreview(rows:rows).rows.map(\.id),[10,9,8,7,6,5,4,3])
    }
    func testCreationLabelUsesSourcePrefixOnly() {
        XCTAssertEqual(ProfileSelfOrdersPreview.createdLabel("2026-10-11T12:30:45"),"2026-10-11 12:30")
        XCTAssertNil(ProfileSelfOrdersPreview.createdLabel(nil));XCTAssertNil(ProfileSelfOrdersPreview.createdLabel(""))
    }
    func testOtherMemberGuestOrMissingApprovalCannotCapture() {
        XCTAssertNil(context(member:92));social.identity = .init(accountID:nil,epoch:1);XCTAssertNil(context())
        social.identity = .init(accountID:81,epoch:1);orders.isConfigured=false;XCTAssertNil(context())
    }
    func testPrivateOwnerMustMatchPublicOwner() { orders.identity = .init(accountID:92,epoch:1);XCTAssertNil(context()) }
    func testInvalidatedParentCannotCapture() { current=false;XCTAssertNil(context()) }
    func testReaderReplacementAndRevisionChangeContext() throws {
        let first=try XCTUnwrap(context());social.presentationRevision += 1;XCTAssertNotEqual(context(),first)
        let other=Orders();XCTAssertNotEqual(ProfileSelfOrdersContext.capture(memberID:81,social:social,orders:other,owner:social.identity,ordersOwner:other.identity,isCurrent:true),context())
    }
    func testFreshEmptyIsAuthoritative() async throws { let r=try reader();await model.load(reader:r);XCTAssertEqual(model.rows,[]);XCTAssertNil(model.issue) }
    func testInitialFailureIsNotEmptyAndCanRetry() async throws {
        let r=try reader();orders.error=APIError.httpStatus(503);await model.load(reader:r);XCTAssertNil(model.rows);XCTAssertEqual(model.issue,.readFailed)
        orders.error=nil;await model.load(reader:r);XCTAssertEqual(model.rows,[]);XCTAssertEqual(orders.reads,2)
    }
    func testFailedRefreshRetainsButDisablesStaleCard() async throws {
        let r=try reader();orders.rows=[try row()];await model.load(reader:r);XCTAssertTrue(model.canOpen(orders.rows[0],reader:r))
        orders.error=APIError.httpStatus(503);await model.load(reader:r);XCTAssertEqual(model.rows?.count,1);XCTAssertFalse(model.canOpen(orders.rows[0],reader:r))
    }
    func testSuccessfulEmptyReplacesPriorRows() async throws {
        let r=try reader();orders.rows=[try row()];await model.load(reader:r);orders.rows=[];await model.load(reader:r);XCTAssertEqual(model.rows,[])
    }
    func testUnauthorizedClearsPreviousRows() async throws {
        let r=try reader();orders.rows=[try row()];await model.load(reader:r);orders.error=ProfileReadFailure(code:401);await model.load(reader:r);XCTAssertNil(model.rows);XCTAssertEqual(model.issue,.signIn)
    }
    func testMalformedOwnerAndDuplicateIDsDoNotPublish() async throws {
        let r=try reader();for rows in [[try row(member:92)],[try row(),try row()]] {orders.rows=rows;await model.load(reader:r);XCTAssertNil(model.rows);XCTAssertEqual(model.issue,.readFailed)}
    }
    func testOnlyVisiblePreviewRowsCanOpen() async throws {
        let r=try reader();orders.rows=try (1...10).map { try row($0) };await model.load(reader:r)
        XCTAssertTrue(model.canOpen(orders.rows[7],reader:r));XCTAssertFalse(model.canOpen(orders.rows[8],reader:r))
    }
    func testDetailKeepsExactIDAndMember() async throws {
        let r=try reader();orders.rows=[try row(7)];let result=try await r.profileOrder(id:7);XCTAssertEqual(result.id,7)
        do {_ = try await r.profileOrder(id:8);XCTFail()} catch {XCTAssertEqual(error as? APIError,.malformedResponse)}
    }
    func testInvalidDetailNeverDispatches() async throws { let r=try reader();do {_ = try await r.profileOrder(id:0);XCTFail()} catch {};XCTAssertEqual(orders.details,0) }
    func testOtherProfileMethodsCannotDispatch() async throws {
        let r=try reader();do {_ = try await r.profileParticipants();XCTFail()} catch {};do {_ = try await r.profileBadges();XCTFail()} catch {};XCTAssertEqual(orders.reads,0)
    }
    func testSingleFlightAndSuspensionDiscardLateRows() async throws {
        let r=try reader();orders.waits=true;let task=Task { await model.load(reader:r) };await waitPending();await model.load(reader:r);XCTAssertEqual(orders.reads,1)
        model.suspend();orders.pending?.resume(returning:[try row()]);orders.pending=nil;await task.value;XCTAssertNil(model.rows)
    }
    func testRevocationBeforeDispatchMakesNoRead() async throws { let r=try reader();orders.isConfigured=false;await model.load(reader:r);XCTAssertEqual(orders.reads,0);XCTAssertNil(r.identity) }
    func testLateAccountChangeSuccessIsDiscarded() async throws {
        let r=try reader();orders.waits=true;let task=Task { await model.load(reader:r) };await waitPending();social.presentationRevision += 1
        orders.pending?.resume(returning:[try row()]);orders.pending=nil;await task.value;XCTAssertNil(model.rows)
    }
    func testLateUnauthorizedCannotChangeNewPresentation() async throws {
        let r=try reader();orders.waits=true;let task=Task { await model.load(reader:r) };await waitPending();current=false
        orders.pending?.resume(throwing:APIError.unauthorized);orders.pending=nil;await task.value;XCTAssertNil(model.issue)
    }
    func testOrderApprovalRevisionRetiresContext() throws {
        let r=try reader();orders.identity = .init(accountID:81,epoch:1,approvalRevision:UUID());XCTAssertFalse(r.isCurrentContext)
    }
    func testRetireClearsSnapshotAndScope() async throws { let r=try reader();orders.rows=[try row()];await model.load(reader:r);model.retire();XCTAssertNil(model.rows);XCTAssertNil(model.loadedScope) }
}
