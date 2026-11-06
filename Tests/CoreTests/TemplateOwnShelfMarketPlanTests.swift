import XCTest
@testable import QuestifyCore

final class TemplateOwnShelfMarketPlanTests: XCTestCase {
    private func state(_ json: String) throws -> TemplateOwnShelfStateProjection {
        try JSONDecoder().decode(TemplateOwnShelfStateProjection.self, from: Data(json.utf8))
    }
    private let approved = #""draftStatus":1,"status":1,"checkStatus":1"#
    func testApprovedWithoutMarketRecordOffersSubmissionOnly() throws {
        let plan = TemplateOwnShelfMarketPlan(try state("{\(approved)}"))
        XCTAssertEqual(plan.action, .submitReview); XCTAssertNil(plan.action?.publishTarget)
        XCTAssertFalse(plan.isDispatchable)
    }
    func testRejectedMarketplaceRecordCanBeResubmitted() throws {
        let plan = TemplateOwnShelfMarketPlan(try state("{\(approved),\"marketTemplateId\":9,\"marketStatus\":2}"))
        XCTAssertEqual(plan.action, .submitReview)
    }
    func testPendingAndListedTargetZeroWithDistinctLabels() throws {
        let pending = TemplateOwnShelfMarketPlan(try state("{\(approved),\"marketTemplateId\":9,\"marketStatus\":0}"))
        XCTAssertEqual(pending.action, .withdrawReview); XCTAssertEqual(pending.action?.publishTarget, 0)
        XCTAssertEqual(pending.action?.labelKey, "templateOwnShelf.market.withdraw")
        let listed = TemplateOwnShelfMarketPlan(try state("{\(approved),\"marketTemplateId\":9,\"marketStatus\":1,\"marketPublishStatus\":1}"))
        XCTAssertEqual(listed.action, .delist); XCTAssertEqual(listed.action?.publishTarget, 0)
    }
    func testUnlistedNeedsPersonalApprovalToRelist() throws {
        let unlisted = "\"marketTemplateId\":9,\"marketStatus\":1,\"marketPublishStatus\":0"
        XCTAssertEqual(TemplateOwnShelfMarketPlan(try state("{\(approved),\(unlisted)}")).action, .list)
        XCTAssertEqual(TemplateOwnShelfMarketPlan(try state("{\(approved),\(unlisted)}")).action?.publishTarget, 1)
        XCTAssertNil(TemplateOwnShelfMarketPlan(try state("{\"draftStatus\":1,\"status\":0,\(unlisted)}")).action)
    }
    func testPersonalPublishStatusNeverDrivesTheMarketplaceAction() throws {
        XCTAssertNil(TemplateOwnShelfMarketPlan(try state(#"{"draftStatus":0,"publishStatus":1}"#)).action)
        XCTAssertNil(TemplateOwnShelfMarketPlan(.unknown).action)
    }
    func testCardFactsFollowSourceFallbacks() throws {
        let facts = try JSONDecoder().decode(TemplateOwnShelfCardFacts.self, from: Data(#"{"rating":4.5,"useNum":"12","duration":0,"createTime":" 2026-10-01 10:00:00 ","reason":"需补充说明"}"#.utf8))
        XCTAssertEqual(facts.rating, Decimal(string: "4.5")); XCTAssertEqual(facts.useCount, 12)
        XCTAssertEqual(facts.durationMinutes, 0); XCTAssertEqual(facts.createTime, "2026-10-01 10:00:00")
        XCTAssertEqual(facts.reviewFeedback, "需补充说明")
    }
    func testMalformedCardColumnsAreAbsentNotInvented() throws {
        let facts = try JSONDecoder().decode(TemplateOwnShelfCardFacts.self, from: Data(#"{"rating":"high","useNum":-1,"reason":"  "}"#.utf8))
        XCTAssertNil(facts.rating); XCTAssertNil(facts.useCount); XCTAssertNil(facts.reviewFeedback); XCTAssertNil(facts.createTime)
    }
    func testDeleteCopyHasTwoConsequences() {
        XCTAssertEqual(TemplateOwnShelfDeleteCopy.consequenceKeys.count, 2)
    }
}
