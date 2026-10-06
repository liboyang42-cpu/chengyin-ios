import XCTest
@testable import QuestifyCore

@MainActor enum WorkshopPurchasedTestData {
    static let item: [String: Any] = ["licenseId":"w18-paid-11","moduleId":"synthetic-module","purchasedVersionId":"synthetic-version","contentHash":String(repeating:"a",count:64),"status":"ACTIVE","acquiredAt":"2026-10-05T00:00:00Z","termsVersion":"terms-1","termsHash":String(repeating:"b",count:64),"commercialUse":"PROHIBITED","adaptation":"LOCAL_ADAPTATION","translation":"PROHIBITED","updates":"EXACT_PURCHASED_VERSION","redistribution":"PROHIBITED","allowedRegions":["synthetic-region"],"themeLimit":["unlimited":false,"maximum":1],"merchantLimit":["unlimited":false,"maximum":0],"runLimit":["unlimited":false,"maximum":10],"acquisition":"PAID","buyerKind":"INDIVIDUAL","useDuration":"PERPETUAL_PURCHASED_VERSION","contentUseStatus":"PAID_INSTALL_AUTHORITY_UNAVAILABLE","purchaseActionStatus":"CHANNEL_APPROVAL_REQUIRED"]
    static let header: [String: Any] = ["schema":"workshop-purchased-owned-v1","scope":"PAID_INDIVIDUAL_PURCHASED_VERSION_METADATA_ONLY","checkedAt":"2026-10-05T00:00:00Z"]
    static func page(_ rows: [[String:Any]] = [item], next: Int64? = nil) -> [String:Any] { var data=header;data["items"]=rows;data["hasMore"]=next != nil;data["nextBeforeOrderLineId"]=next.map{$0 as Any} ?? NSNull();return data }
    static func detail(_ value:[String:Any] = item)->[String:Any]{var data=header;data["item"]=value;return data}
    static func envelope(_ object:[String:Any]) throws -> Data {try JSONSerialization.data(withJSONObject:["code":200,"data":object])}
    static func decode<T:Decodable>(_ value:[String:Any]) throws -> T {try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:value))}
}
@MainActor final class WorkshopPurchasedContractsTests: XCTestCase {
    func testExplicitPurchasedDurationDoesNotDependOnExpiryFieldOrSubscription() throws {
        let item:WorkshopPurchasedItem=try WorkshopPurchasedTestData.decode(WorkshopPurchasedTestData.item)
        XCTAssertEqual(item.purchasedVersionId,"synthetic-version");XCTAssertEqual(item.status,.active);XCTAssertFalse(item.permitsPurchase);XCTAssertFalse(item.permitsContentUse)
        for key in ["useDuration","acquisition","termsHash"] { var object=WorkshopPurchasedTestData.item;object.removeValue(forKey:key);XCTAssertThrowsError(try WorkshopPurchasedTestData.decode(object) as WorkshopPurchasedItem) }
    }
    func testFreeExpiredUnknownRightsAndExtraProtectedFieldsCannotMasqueradeAsPurchased() throws {
        for pair in [("acquisition","FREE"),("useDuration","SUBSCRIPTION"),("status","EXPIRED"),("status","UNKNOWN"),("redistribution","ALLOWED"),("purchaseActionStatus","ENABLED"),("contentUseStatus","AUTHORIZED"),("sourceJSON","private answer")] {
            var value=WorkshopPurchasedTestData.item;value[pair.0]=pair.1;XCTAssertThrowsError(try WorkshopPurchasedTestData.decode(value) as WorkshopPurchasedItem)
        }
    }
    func testFrozenSuspendedAndRevokedRightsRemainExplicit() throws {
        for status in ["ACTIVE","SUSPENDED","REVOKED"] { var data=WorkshopPurchasedTestData.item;data["status"]=status;let item:WorkshopPurchasedItem=try WorkshopPurchasedTestData.decode(data);XCTAssertEqual(item.status.rawValue,status);XCTAssertEqual(item.merchantLimit.maximum,0) }
    }
    func testExactPageDetailAndPaginationBounds() throws {
        let page:WorkshopPurchasedPage=try WorkshopPurchasedTestData.decode(WorkshopPurchasedTestData.page());XCTAssertEqual(page.items.count,1);XCTAssertNil(page.nextBeforeOrderLineId)
        let detail:WorkshopPurchasedDetail=try WorkshopPurchasedTestData.decode(WorkshopPurchasedTestData.detail());XCTAssertEqual(detail.item.id,"w18-paid-11")
        XCTAssertThrowsError(try WorkshopPurchasedTestData.decode(WorkshopPurchasedTestData.page([WorkshopPurchasedTestData.item,WorkshopPurchasedTestData.item])) as WorkshopPurchasedPage)
        XCTAssertThrowsError(try WorkshopPurchasedTestData.decode(WorkshopPurchasedTestData.page(next:1)) as WorkshopPurchasedPage)
        var extra=WorkshopPurchasedTestData.detail();extra["owner"]=7;XCTAssertThrowsError(try WorkshopPurchasedTestData.decode(extra) as WorkshopPurchasedDetail)
    }
    func testLimitsIdentifiersRegionAndHashFailures() throws {
        for pair:(String,Any) in [("licenseId","w18-paid-01"),("licenseId","w18-paid-9223372036854775808"),("contentHash",String(repeating:"A",count:64)),("allowedRegions",["r","r"]),("themeLimit",["unlimited":true,"maximum":1]),("themeLimit",["unlimited":false,"maximum":-1])] {
            var value=WorkshopPurchasedTestData.item;value[pair.0]=pair.1;XCTAssertThrowsError(try WorkshopPurchasedTestData.decode(value) as WorkshopPurchasedItem)
        }
    }
    func testPurchasedApprovalBindsFullContextIncludingNestedRole() throws {
        let session=try PlayExperienceSession(accountID:7,epoch:1,namespace:"synthetic",token:"synthetic")
        let context=RuntimeDependencyContext(market:.china,baseURL:URL(string:"https://example.com/native")!,role:"merchant",session:session)
        let approval=try WorkshopPurchasedReadApproval(context:context,expiresAt:.distantFuture);XCTAssertTrue(approval.matches(context))
        let changed=RuntimeDependencyContext(market:.china,baseURL:context.baseURL,role:"merchant",session:try .init(accountID:7,epoch:1,namespace:"synthetic",token:"synthetic",role:"merchant"))
        XCTAssertFalse(approval.matches(changed))
    }
}
