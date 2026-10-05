import XCTest
@testable import QuestifyCore

final class MerchantRedemptionContextTests: XCTestCase {
    private func body(_ raw: String) throws -> MerchantBusinessObject { try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(raw).object) }
    func testDynamicActivityAndTopicOnlyRouteWholeCode() throws {
        for type in ["activity", "topic"] {
            let code = "v1.synthetic.\(type).untrusted"
            let context = try MerchantRedemptionContext.parse(code)
            XCTAssertEqual(context.kind, .dynamicTicket); XCTAssertEqual(context.request().body, .form(["code":code]))
        }
    }
    func testGroupAndCouponUseDifferentEndpoints() throws {
        XCTAssertEqual(try MerchantRedemptionContext.parse("v1.synthetic.group_test.untrusted").endpoint, "api/verify/groupcode/redeem")
        XCTAssertEqual(try MerchantRedemptionContext.parse(#"{"type":"coupon","code":"synthetic"}"#).endpoint, "api/coupon/verification")
    }
    func testUnknownDynamicTypeIsUnsupportedNotAuthenticated() {
        XCTAssertThrowsError(try MerchantRedemptionContext.parse("v1.synthetic.admin.untrusted")) { XCTAssertEqual($0 as? MerchantRedemptionFailure, .unsupported) }
    }
    func testUnrelatedURLNeverOpensOrDispatches() { XCTAssertThrowsError(try MerchantRedemptionContext.parse("https://example.com")) }
    func testLegacyTypeRetainedWithoutInferringIdentity() throws {
        let context = try MerchantRedemptionContext.parse(#"{"type":"topic","code":"synthetic"}"#)
        XCTAssertEqual(context.request().body, .form(["type":"topic","code":"synthetic"]))
    }
    func testNeedsChapterChoicePrecedesErrorCode() throws {
        let result = try MerchantRedemptionResult(body: body(#"{"code":500,"msg":"Choose chapter","data":{"needChapterChoice":true,"chapterIds":[71,72]}}"#), kind: .legacyTicket)
        XCTAssertEqual(result.outcome, .needsChoice); XCTAssertEqual(result.choices.count, 2)
        XCTAssertEqual(result.choices[0].target, .chapter(try .init(71)))
    }
    func testStationChoiceUsesRegistrationMerchantIDNotStationID() throws {
        let result = try MerchantRedemptionResult(body: body(#"{"code":500,"data":{"needStationChoice":true,"stations":[{"id":999,"registrationMerchantId":81,"name":"Example station"}]}}"#), kind: .legacyTicket)
        XCTAssertEqual(result.choices[0].target, .stationRegistration(try .init(81)))
        let context = try MerchantRedemptionContext.parse(#"{"type":"topic","code":"synthetic"}"#)
        XCTAssertEqual(context.request(choice: result.choices[0].target).body, .form(["code":"synthetic","registrationMerchantId":"81"]))
    }
    func testStationChoiceWithoutDedicatedIDFailsClosed() throws {
        XCTAssertThrowsError(try MerchantRedemptionResult(body: body(#"{"code":500,"data":{"needStationChoice":true,"stations":[{"id":999}]}}"#), kind: .legacyTicket))
    }
    func testEmptyChoicesNeverBecomeSuccess() throws {
        XCTAssertThrowsError(try MerchantRedemptionResult(body: body(#"{"code":200,"data":{"needChapterChoice":true,"chapterIds":[]}}"#), kind: .legacyTicket))
    }
    func testDuplicateChoicesAndConflictingKindsRejected() throws {
        XCTAssertThrowsError(try MerchantRedemptionResult(body: body(#"{"code":500,"data":{"needChapterChoice":true,"chapterIds":[1,1]}}"#), kind: .legacyTicket))
        XCTAssertThrowsError(try MerchantRedemptionResult(body: body(#"{"code":500,"data":{"needChapterChoice":true,"needStationChoice":true}}"#), kind: .legacyTicket))
    }
    func test403NeverShowsSuccessEvenWithChoices() throws {
        XCTAssertThrowsError(try MerchantRedemptionResult(body: body(#"{"code":403,"data":{"needChapterChoice":true,"chapterIds":[1]}}"#), kind: .legacyTicket))
    }
    func testCode200DynamicReceiptPreservesChapterResult() throws {
        let result = try MerchantRedemptionResult(body: body(#"{"code":200,"data":{"chapterId":71}}"#), kind: .dynamicTicket)
        XCTAssertEqual(result.outcome, .redeemed); XCTAssertEqual(result.chapterID, try MerchantChapterID(71))
    }
}
