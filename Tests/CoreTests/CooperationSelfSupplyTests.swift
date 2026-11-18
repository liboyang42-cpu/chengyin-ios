import XCTest
@testable import QuestifyCore

/// F10 author self-supply ("自己承接") route contract. Synthetic values only.
final class CooperationSelfSupplyTests: XCTestCase {
    private func perk(name: String = "示例权益", rule: String = "8 折，到店出示", end: String = "2030-12-31", capacity: Int = 20) throws -> CoopFlowSelfSupplyPerk {
        try .init(name: name, redeemRule: rule, validEnd: end, capacity: capacity)
    }
    func testExactRouteAndBody() throws {
        let request = try CoopFlowSelfSupplyRequest(topicID: 71, chapterID: 31, perk: perk())
        XCTAssertEqual(request.path, "api/topic/chapter/self-supply")
        XCTAssertEqual(request.body, .object(["topicId": .id(71), "chapterId": .id(31), "perk": .object([
            "name": .string("示例权益"), "redeemRule": .string("8 折，到店出示"), "validEnd": .string("2030-12-31"), "capacity": .id(20)])]))
        let withdraw = try CoopFlowSelfSupplyWithdrawal(topicID: 71, offerID: 9)
        XCTAssertEqual(withdraw.path, "api/topic/chapter/self-supply/withdraw")
        XCTAssertEqual(withdraw.body, .object(["topicId": .id(71), "offerId": .id(9)]))
    }
    func testInvalidPerkAndTargetsAreRejected() {
        XCTAssertThrowsError(try perk(name: "  "))
        XCTAssertThrowsError(try perk(rule: ""))
        XCTAssertThrowsError(try perk(end: "2030-02-30"))
        XCTAssertThrowsError(try perk(end: "2030/12/31"))
        XCTAssertThrowsError(try perk(capacity: 0))
        XCTAssertThrowsError(try CoopFlowSelfSupplyRequest(topicID: 0, chapterID: 31, perk: perk()))
        XCTAssertThrowsError(try CoopFlowSelfSupplyWithdrawal(topicID: 71, offerID: 0))
    }
    func testResponsesNeverDefaultToSuccess() throws {
        XCTAssertEqual(try CoopFlowSelfSupplyRequest.offerID(.object(["offerId": .id(9)])), 9)
        XCTAssertThrowsError(try CoopFlowSelfSupplyRequest.offerID(.object([:])))
        XCTAssertEqual(try CoopFlowSelfSupplyWithdrawal.lifecycle(.object(["lifecycle": .id(1)])), 1)
        XCTAssertThrowsError(try CoopFlowSelfSupplyWithdrawal.lifecycle(.null))
    }
}
