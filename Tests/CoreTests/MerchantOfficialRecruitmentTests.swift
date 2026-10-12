import XCTest
@testable import QuestifyCore

final class MerchantOfficialRecruitmentTests: XCTestCase {
    private func event(status: Int? = 1, policy: String? = "OPTIONAL_PARTNERS", blocked: Bool = false, id: Int = 7, title: String = "Event") throws -> OfficialEvent {
        var raw:[String:Any] = ["id":id,"title":title,"recruitmentBlocked":blocked]
        raw["status"]=status; raw["fulfillmentPolicy"]=policy
        return try JSONDecoder().decode(OfficialEvent.self,from:JSONSerialization.data(withJSONObject:raw))
    }
    func testUpcomingOptionalIncluded() throws { XCTAssertTrue(try MerchantOfficialRecruitment.includes(event())) }
    func testRegistrationRequiredIncluded() throws { XCTAssertTrue(try MerchantOfficialRecruitment.includes(event(status:2,policy:"REQUIRED_FULFILLMENT"))) }
    func testBothPoliciesBothStatuses() throws { for s in [1,2] { for p in ["OPTIONAL_PARTNERS","REQUIRED_FULFILLMENT"] { XCTAssertTrue(try MerchantOfficialRecruitment.includes(event(status:s,policy:p))) } } }
    func testOtherStatusesExcluded() throws { for s in [0,3,4,5,6,9,99] { XCTAssertFalse(try MerchantOfficialRecruitment.includes(event(status:s))) } }
    func testUnknownStatusExcluded() throws { XCTAssertFalse(try MerchantOfficialRecruitment.includes(event(status:nil))) }
    func testOtherPoliciesExcluded() throws { for p in ["NONE","OPTIONAL_PARTNERS ","optional_partners",""] { XCTAssertFalse(try MerchantOfficialRecruitment.includes(event(policy:p))) } }
    func testMissingPolicyExcluded() throws { XCTAssertFalse(try MerchantOfficialRecruitment.includes(event(policy:nil))) }
    func testBlockedEventStaysVisible() throws { let e=try event(blocked:true); XCTAssertTrue(MerchantOfficialRecruitment.includes(e)); XCTAssertEqual(e.recruitmentBlocked,true) }
    func testServerGapReasonPreserved() throws { let e=try JSONDecoder().decode(OfficialEvent.self,from:Data(#"{"id":7,"title":"E","status":2,"fulfillmentPolicy":"REQUIRED_FULFILLMENT","recruitmentBlocked":true,"recruitmentBlockedReason":"Needs partner"}"#.utf8)); XCTAssertTrue(MerchantOfficialRecruitment.includes(e)); XCTAssertEqual(e.recruitmentWarningReason,"Needs partner") }
    func testIncompleteIdentityExcluded() throws { XCTAssertFalse(try MerchantOfficialRecruitment.includes(event(id:0))); XCTAssertFalse(try MerchantOfficialRecruitment.includes(event(title:"  "))) }
    func testOrderPreserved() throws { let a=try event(id:9),b=try event(status:2,id:2),c=try event(status:3,id:3); XCTAssertEqual(MerchantOfficialRecruitment.visible([a,c,b]),[a,b]) }
    func testLegacyOfficialRecordStillDecodes() throws { let e=try event(policy:nil); XCTAssertEqual(e.status,1); XCTAssertEqual(e.statusKey,"official.status.upcoming"); XCTAssertNil(e.fulfillmentPolicy) }
    func testEmptyList() { XCTAssertEqual(MerchantOfficialRecruitment.visible([]),[]) }
}
