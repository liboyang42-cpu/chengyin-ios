import XCTest
import Combine
@testable import Questify

@MainActor private final class CenterDeniedMerchant:MerchantReading {
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
@MainActor private final class CenterDeniedOfficial:OfficialEventReading {
    var injectedError: Error?
    var accessCount:()->Int={0}
    var isConfigured=true,isAuthenticated=true,isOfflineExample=true,scope=UUID(),fail=false
    var calls:[String]=[],accessCallsAtRead:[Int]=[]
    var beforeReturn:(()->Void)?
    var raw=#"[{"id":7,"title":"Recruit","status":2,"fulfillmentPolicy":"REQUIRED_FULFILLMENT","recruitmentBlocked":true},{"id":8,"title":"Live","status":3,"fulfillmentPolicy":"OPTIONAL_PARTNERS"}]"#
    func events(city:String?)async throws->[OfficialEvent]{calls.append("events");accessCallsAtRead.append(accessCount());beforeReturn?();if let injectedError { throw injectedError };if fail{throw APIError.httpStatus(503)};return try JSONDecoder().decode([OfficialEvent].self,from:Data(raw.utf8))}
    func detail(id:Int)async throws->OfficialEvent{calls.append("detail");accessCallsAtRead.append(accessCount());beforeReturn?();return try JSONDecoder().decode([OfficialEvent].self,from:Data(raw.utf8))[0]}
    func myEvents()async throws->[OfficialEvent]{XCTFail();throw APIError.invalidRequest}
    func partyInbox()async throws->[OfficialPartyInvite]{XCTFail();throw APIError.invalidRequest}
    func canPublish()async throws->Bool{XCTFail();return false}
    func myPublished()async throws->OfficialPublished{XCTFail();throw APIError.invalidRequest}
    func broadcastStats(id:Int)async throws->OfficialBroadcastStats{XCTFail();throw APIError.invalidRequest}
}

@MainActor private final class CenterUnusedWire: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) { XCTFail("No plaza request"); throw APIError.invalidRequest }
}
@MainActor final class MerchantCoopOfficialDenialTests: XCTestCase {
    private func load(_ model: MerchantCoopCenterModel) async {
        model.loadEvents()
        for _ in 0..<200 where model.eventsLoading { await Task.yield() }
        XCTAssertFalse(model.eventsLoading)
    }
    func testFreshMembershipRevocationWithoutSourceSignalRetiresOnlyOfficialRowsAndCanRecover() async throws {
        let merchant = CenterDeniedMerchant(), official = CenterDeniedOfficial()
        let reader = MerchantOfficialRecruitmentReader(merchant: merchant, official: official, sourceIsCurrent: { true })
        let content = MerchantContentService(configuration: nil, transport: CenterUnusedWire(), currentSession: { nil })
        let model = MerchantCoopCenterModel(content: content, official: reader, focusTopicID: nil, now: Date.init)
        await load(model)
        XCTAssertEqual(model.events.map(\.id), [7])
        let scope = reader.scope
        merchant.active = false
        await load(model)
        XCTAssertEqual(reader.scope, scope)
        XCTAssertTrue(model.events.isEmpty); XCTAssertEqual(model.eventsIssue, .denied)
        XCTAssertEqual(official.calls, ["events"])
        XCTAssertTrue(model.routes.isEmpty); XCTAssertNil(model.routesIssue)
        merchant.active = true
        await load(model)
        XCTAssertEqual(model.events.map(\.id), [7]); XCTAssertNil(model.eventsIssue)
    }
    func testOrdinaryOfficialFailureRetainsOriginalVisibleRows() async throws {
        let merchant = CenterDeniedMerchant(), official = CenterDeniedOfficial()
        let reader = MerchantOfficialRecruitmentReader(merchant: merchant, official: official, sourceIsCurrent: { true })
        let content = MerchantContentService(configuration: nil, transport: CenterUnusedWire(), currentSession: { nil })
        let model = MerchantCoopCenterModel(content: content, official: reader, focusTopicID: nil, now: Date.init)
        await load(model)
        official.fail = true
        await load(model)
        XCTAssertEqual(model.events.map(\.id), [7]); XCTAssertEqual(model.eventsIssue, .failed(nil))
    }
    func testExplicitOfficialRefusalOrAuthenticationFailureClearsRows() async throws {
        let errors: [Error] = [OfficialReadFailure.forbidden, APIError.unauthorized]
        for error in errors {
            let merchant = CenterDeniedMerchant(), official = CenterDeniedOfficial()
            let reader = MerchantOfficialRecruitmentReader(merchant: merchant, official: official, sourceIsCurrent: { true })
            let content = MerchantContentService(configuration: nil, transport: CenterUnusedWire(), currentSession: { nil })
            let model = MerchantCoopCenterModel(content: content, official: reader, focusTopicID: nil, now: Date.init)
            await load(model); XCTAssertFalse(model.events.isEmpty)
            official.injectedError = error
            await load(model)
            XCTAssertTrue(model.events.isEmpty)
            XCTAssertEqual(model.eventsIssue, error as? APIError == .unauthorized ? .signIn : .denied)
        }
    }

}
