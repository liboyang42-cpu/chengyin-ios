import XCTest
import Combine
@testable import Questify

@MainActor final class MerchantProjectRecentEventsModelTests: XCTestCase {
    private func setup() throws -> (MerchantProjectRecentEventsModel, ProjectEventsFake) {
        let m = MerchantProjectRecentEventsModel(); m.activate(); return (m, try ProjectEventsFake())
    }
    private func load(_ m: MerchantProjectRecentEventsModel, _ r: ProjectEventsFake, current: @escaping () -> Bool = { true }) async {
        await m.load(reader:r,project:r.project,merchantID:31,sourceIsCurrent:current)
    }
    func testFreshAccessProjectThenEvents() async throws { let (m,r)=try setup(); await load(m,r); XCTAssertEqual(r.calls,["access","projects","events"]); XCTAssertEqual(m.rows?.count,1); XCTAssertNil(m.errorKey) }
    func testOwnerDeniedNoDataReads() async throws { let (m,r)=try setup(); r.role="MERCHANT_FINANCE"; await load(m,r); XCTAssertEqual(r.calls,["access"]); XCTAssertNil(m.rows); XCTAssertEqual(m.errorKey,"merchant.access.denied") }
    func testChangedMerchantDenied() async throws { let (m,r)=try setup(); r.merchant=32; await load(m,r); XCTAssertEqual(r.calls,["access"]); XCTAssertNil(m.rows) }
    func testMissingProjectGrantDenied() async throws { let (m,r)=try setup(); r.permissions=[]; await load(m,r); XCTAssertEqual(r.calls,["access"]); XCTAssertNil(m.rows) }
    func testMissingSelectedProjectStopsEvents() async throws { let (m,r)=try setup(); r.includeProject=false; await load(m,r); XCTAssertEqual(r.calls,["access","projects"]); XCTAssertEqual(m.errorKey,"merchant.projectEvents.changed") }
    func testStaleSourceNoRead() async throws { let (m,r)=try setup(); await load(m,r,current:{false}); XCTAssertTrue(r.calls.isEmpty); XCTAssertNil(m.rows) }
    func testSignedOutNoRead() async throws { let (m,r)=try setup(); r.isSignedIn=false; await load(m,r); XCTAssertTrue(r.calls.isEmpty) }
    func testUnconfiguredNoRead() async throws { let (m,r)=try setup(); r.isConfigured=false; await load(m,r); XCTAssertTrue(r.calls.isEmpty) }
    func testRevisionAfterAccessStopsProjectRead() async throws { let (m,r)=try setup(); r.afterAccess={r.sessionRevision += 1}; await load(m,r); XCTAssertEqual(r.calls,["access"]); XCTAssertNil(m.rows) }
    func testSourceRevokedAfterProjectStopsEvents() async throws { let (m,r)=try setup(); var current=true; r.afterProjects={current=false}; await load(m,r,current:{current}); XCTAssertEqual(r.calls,["access","projects"]); XCTAssertNil(m.rows) }
    func testLogoutAfterEventsSuppressesResult() async throws { let (m,r)=try setup(); r.afterEvents={r.isSignedIn=false}; await load(m,r); XCTAssertNil(m.rows) }
    func testRetireSuppressesLateResult() async throws { let (m,r)=try setup(); r.afterEvents={m.retire()}; await load(m,r); XCTAssertNil(m.rows); XCTAssertFalse(m.loading) }
    func testRefreshClearsOldRowsBeforeRead() async throws { let (m,r)=try setup(); await load(m,r); XCTAssertNotNil(m.rows); r.afterAccess={XCTAssertNil(m.rows); XCTAssertTrue(m.loading)}; await load(m,r); XCTAssertNotNil(m.rows) }
    func testErrorAndExplicitRetry() async throws { let (m,r)=try setup(); r.failEvents=true; await load(m,r); XCTAssertEqual(m.errorKey,"merchant.loadFailed"); XCTAssertNil(m.rows); r.failEvents=false; await load(m,r); XCTAssertNil(m.errorKey); XCTAssertEqual(m.rows?.count,1) }
    func testEmptyIsSuccessfulResult() async throws { let (m,r)=try setup(); r.events=[]; await load(m,r); XCTAssertEqual(m.rows,[]); XCTAssertNil(m.errorKey) }
    func testRetiredCannotReloadUntilActivated() async throws { let (m,r)=try setup(); m.retire(); await load(m,r); XCTAssertTrue(r.calls.isEmpty); m.activate(); await load(m,r); XCTAssertNotNil(m.rows) }
    func testOverlappingReadLatestResultWins() async throws {
        let (m,r)=try setup(); let entered=expectation(description:"first events suspended")
        r.suspendFirstEvents={entered.fulfill()}
        let first=Task { await self.load(m,r) }
        await fulfillment(of:[entered],timeout:1)
        r.events=[.init(content:"new",time:"later",projectOwnerType:"1",projectOwnerID:"7")]
        await load(m,r)
        r.pendingEvents?.resume(returning:[.init(content:"old",time:"earlier",projectOwnerType:"1",projectOwnerID:"7")]); r.pendingEvents=nil
        await first.value
        XCTAssertEqual(m.rows?.first?.content,"new")
    }
}

@MainActor private final class ProjectEventsFake: MerchantReading {
    @Published var isConfigured=true
    @Published var isSignedIn=true
    @Published var sessionRevision:UInt64=1
    var role="MERCHANT_OWNER", merchant=31
    var permissions=["merchant:project:manage"]
    var includeProject=true, failEvents=false
    var calls:[String]=[]
    var afterAccess:(()->Void)?, afterProjects:(()->Void)?, afterEvents:(()->Void)?
    var suspendFirstEvents:(()->Void)?
    var pendingEvents:CheckedContinuation<[MerchantEvent],Never>?
    let project:MerchantProject
    var events:[MerchantEvent]=[.init(content:"mine",time:"as returned",projectOwnerType:"1",projectOwnerID:"7"),.init(content:"other type",time:"",projectOwnerType:"2",projectOwnerID:"7")]
    init()throws { project=try JSONDecoder().decode(MerchantProject.self,from:Data(#"{"id":7,"bizType":"topic","title":"Project"}"#.utf8)) }
    func merchantAccess()async throws->MerchantAccess {
        calls.append("access"); afterAccess?()
        let json:[String:Any]=["active":true,"merchant":["id":merchant],"roleCode":role,"permissions":permissions]
        return try JSONDecoder().decode(MerchantAccess.self,from:JSONSerialization.data(withJSONObject:json))
    }
    func merchantProjects(access:MerchantAccess)async throws->MerchantProjectPage {
        calls.append("projects"); afterProjects?()
        return try JSONDecoder().decode(MerchantProjectPage.self,from:Data((includeProject ? #"{"rows":[{"id":7,"bizType":"topic","title":"Project"}],"total":1}"# : #"{"rows":[],"total":0}"#).utf8))
    }
    func merchantEvents(access:MerchantAccess)async throws->[MerchantEvent] {
        calls.append("events"); afterEvents?()
        if let suspend=suspendFirstEvents { suspendFirstEvents=nil; return await withCheckedContinuation { pendingEvents=$0; suspend() } }
        if failEvents { throw APIError.httpStatus(503) }; return events
    }
    func merchantDashboard(access:MerchantAccess)async throws->MerchantDashboard { XCTFail("unexpected dashboard"); throw APIError.invalidRequest }
    func merchantTodo(access:MerchantAccess)async throws->MerchantTodo { XCTFail("unexpected todo"); throw APIError.invalidRequest }
    func merchantOrders(access:MerchantAccess,filter:MerchantOrderFilter)async throws->[MerchantOrder] { XCTFail("unexpected orders"); throw APIError.invalidRequest }
}
