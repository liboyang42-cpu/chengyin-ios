import XCTest
import Combine
@testable import Questify

@MainActor final class MerchantOfficialRecruitmentReaderTests: XCTestCase {
    private func setup() -> (MerchantOfficialRecruitmentReader<RecruitmentMerchantFake>,RecruitmentMerchantFake,RecruitmentOfficialFake) {
        let m=RecruitmentMerchantFake(),o=RecruitmentOfficialFake(); o.accessCount={m.accessCalls}; return (.init(merchant:m,official:o,sourceIsCurrent:{true}),m,o)
    }
    func testFreshMerchantGateThenPublicList() async throws { let (r,m,o)=setup(); let rows=try await r.events(city:nil); XCTAssertEqual(m.accessCalls,1); XCTAssertEqual(o.calls,["events"]); XCTAssertEqual(rows.map(\.id),[7]); XCTAssertEqual(o.accessCallsAtRead,[1]) }
    func testDetailRechecksMembership() async throws { let (r,m,o)=setup(); _=try await r.events(city:nil); _=try await r.detail(id:7); XCTAssertEqual(m.accessCalls,2); XCTAssertEqual(o.calls,["events","detail"]); XCTAssertEqual(o.accessCallsAtRead,[1,2]) }
    func testInactiveMerchantCannotReadList() async { let (r,m,o)=setup(); m.active=false; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertTrue(o.calls.isEmpty) }
    func testSignedOutCannotProbeMembership() async { let (r,m,o)=setup(); m.isSignedIn=false; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertEqual(m.accessCalls,0); XCTAssertTrue(o.calls.isEmpty) }
    func testMissingOfficialSessionCannotRead() async { let (r,m,o)=setup(); o.isAuthenticated=false; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertEqual(m.accessCalls,0); XCTAssertTrue(o.calls.isEmpty) }
    func testSourceRevocationCannotRead() async { let m=RecruitmentMerchantFake(),o=RecruitmentOfficialFake(); let r=MerchantOfficialRecruitmentReader(merchant:m,official:o,sourceIsCurrent:{false}); do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertEqual(m.accessCalls,0) }
    func testUnconfiguredCannotRead() async { let (r,m,o)=setup(); o.isConfigured=false; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertEqual(m.accessCalls,0); XCTAssertTrue(o.calls.isEmpty) }
    func testMerchantChangeDuringGateStopsPublicRead() async { let (r,m,o)=setup(); m.afterAccess={m.sessionRevision += 1}; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertTrue(o.calls.isEmpty) }
    func testOfficialChangeDuringGateStopsPublicRead() async { let (r,m,o)=setup(); m.afterAccess={o.scope=UUID()}; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertTrue(o.calls.isEmpty) }
    func testSourceChangeDuringEventsSuppressesResult() async { let m=RecruitmentMerchantFake(),o=RecruitmentOfficialFake(); var current=true; let r=MerchantOfficialRecruitmentReader(merchant:m,official:o,sourceIsCurrent:{current}); o.beforeReturn={current=false}; do {_=try await r.events(city:nil); XCTFail()}catch{} }
    func testBackgroundSuppressesResult() async { let (r,_,o)=setup(); o.beforeReturn={r.setActive(false)}; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertFalse(r.isAuthenticated) }
    func testBackgroundThenForegroundRetiresInflightGeneration() async { let (r,_,o)=setup(); o.beforeReturn={r.setActive(false);r.setActive(true)}; do {_=try await r.events(city:nil); XCTFail()}catch{}; XCTAssertTrue(r.isAuthenticated) }
    func testScopeChangesForSceneAndIdentity() { let (r,m,_)=setup(); let a=r.scope; r.setActive(false); XCTAssertNotEqual(r.scope,a); r.setActive(true); let b=r.scope; m.sessionRevision += 1; XCTAssertNotEqual(r.scope,b); XCTAssertFalse(r.isAuthenticated) }
    func testReadFailureCanExplicitlyRetry() async throws { let (r,_,o)=setup(); o.fail=true; do {_=try await r.events(city:nil); XCTFail()}catch{}; o.fail=false; let rows=try await r.events(city:nil); XCTAssertEqual(rows.count,1) }
    func testUnsupportedPrivateReadsNeverDelegate() async { let (r,m,o)=setup(); do {_=try await r.myEvents(); XCTFail()}catch{}; do {_=try await r.partyInbox(); XCTFail()}catch{}; do {_=try await r.myPublished(); XCTFail()}catch{}; do {_=try await r.broadcastStats(id:7); XCTFail()}catch{}; let allowed=try? await r.canPublish(); XCTAssertEqual(allowed,false); XCTAssertEqual(m.accessCalls,0); XCTAssertTrue(o.calls.isEmpty) }
    func testInvalidCityAndIDNeverRead() async { let (r,m,o)=setup(); do {_=try await r.events(city:"city"); XCTFail()}catch{}; do {_=try await r.detail(id:0); XCTFail()}catch{}; XCTAssertEqual(m.accessCalls,0); XCTAssertTrue(o.calls.isEmpty) }
    func testMissingPolicyReturnsSuccessfulEmpty() async throws { let (r,_,o)=setup(); o.raw=#"[{"id":7,"title":"legacy","status":1}]"#; let rows=try await r.events(city:nil); XCTAssertTrue(rows.isEmpty) }
    func testStaffMembershipAddsNoNewGrant() async throws { let (r,m,_)=setup(); m.role="MERCHANT_MARKETING"; let rows=try await r.events(city:nil); XCTAssertEqual(rows.count,1) }
}

@MainActor private final class RecruitmentMerchantFake:MerchantReading {
    @Published var isConfigured=true
    @Published var isSignedIn=true
    @Published var sessionRevision:UInt64=1
    var active=true,role="MERCHANT_OWNER",accessCalls=0
    var afterAccess:(()->Void)?
    func merchantAccess()async throws->MerchantAccess {accessCalls += 1;afterAccess?();let raw:[String:Any]=["active":active,"merchant":["id":31],"roleCode":role,"permissions":[]];return try JSONDecoder().decode(MerchantAccess.self,from:JSONSerialization.data(withJSONObject:raw))}
    func merchantDashboard(access:MerchantAccess)async throws->MerchantDashboard{XCTFail();throw APIError.invalidRequest}
    func merchantTodo(access:MerchantAccess)async throws->MerchantTodo{XCTFail();throw APIError.invalidRequest}
    func merchantEvents(access:MerchantAccess)async throws->[MerchantEvent]{XCTFail();throw APIError.invalidRequest}
    func merchantOrders(access:MerchantAccess,filter:MerchantOrderFilter)async throws->[MerchantOrder]{XCTFail();throw APIError.invalidRequest}
    func merchantProjects(access:MerchantAccess)async throws->MerchantProjectPage{XCTFail();throw APIError.invalidRequest}
}
@MainActor private final class RecruitmentOfficialFake:OfficialEventReading {
    var accessCount:()->Int={0}
    var isConfigured=true,isAuthenticated=true,isOfflineExample=true,scope=UUID(),fail=false
    var calls:[String]=[],accessCallsAtRead:[Int]=[]
    var beforeReturn:(()->Void)?
    var raw=#"[{"id":7,"title":"Recruit","status":2,"fulfillmentPolicy":"REQUIRED_FULFILLMENT","recruitmentBlocked":true},{"id":8,"title":"Live","status":3,"fulfillmentPolicy":"OPTIONAL_PARTNERS"}]"#
    func events(city:String?)async throws->[OfficialEvent]{calls.append("events");accessCallsAtRead.append(accessCount());beforeReturn?();if fail{throw APIError.httpStatus(503)};return try JSONDecoder().decode([OfficialEvent].self,from:Data(raw.utf8))}
    func detail(id:Int)async throws->OfficialEvent{calls.append("detail");accessCallsAtRead.append(accessCount());beforeReturn?();return try JSONDecoder().decode([OfficialEvent].self,from:Data(raw.utf8))[0]}
    func myEvents()async throws->[OfficialEvent]{XCTFail();throw APIError.invalidRequest}
    func partyInbox()async throws->[OfficialPartyInvite]{XCTFail();throw APIError.invalidRequest}
    func canPublish()async throws->Bool{XCTFail();return false}
    func myPublished()async throws->OfficialPublished{XCTFail();throw APIError.invalidRequest}
    func broadcastStats(id:Int)async throws->OfficialBroadcastStats{XCTFail();throw APIError.invalidRequest}
}
