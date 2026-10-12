import XCTest
@testable import QuestifyCore
final class MerchantPersonalIncomeEligibilityTests:XCTestCase {
    private func snapshot(route:String="COOP_ORDER",finance:Bool=true,list:Bool=false)throws->MerchantBusinessSnapshot {
        var access=try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        if !finance { access["permissions"] = .array([]);access["canManageOperators"] = .bool(false) }
        let query:MerchantBusinessQuery=list ? .redemptions(filter:"all",page:1):.redemption(recordID:"64001")
        var payload=try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.redemption).object);payload["settlementRoute"] = .string(route)
        let data:MerchantBusinessValue=list ? try MerchantBusinessSyntheticFixtures.payload(query):.object(payload)
        return try .init(access:.init(access),document:.init(query:query,payload:data))
    }
    func testCoopDetailAllowed()throws{let s=try snapshot();XCTAssertTrue(MerchantPersonalIncomeEligibility.matches(row:s.document.rows[0],snapshot:s))}
    func testFinanceRequired()throws{let s=try snapshot(finance:false);XCTAssertFalse(MerchantPersonalIncomeEligibility.matches(row:s.document.rows[0],snapshot:s))}
    func testOtherRouteDenied()throws{for route in ["PUBLIC_TRANSFER","","coop_order"]{let s=try snapshot(route:route);XCTAssertFalse(MerchantPersonalIncomeEligibility.matches(row:s.document.rows[0],snapshot:s))}}
    func testListDoesNotExposeDetailHandoff()throws{let s=try snapshot(list:true);XCTAssertFalse(MerchantPersonalIncomeEligibility.matches(row:s.document.rows[0],snapshot:s))}
}
