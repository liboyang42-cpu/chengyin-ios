import XCTest
@testable import QuestifyCore

final class CoopFinanceSummaryTests: XCTestCase {
    private func summary(_ json: String) throws -> CoopFinanceSummary {
        CoopFinanceSummary(try JSONDecoder().decode(CoopFlowJSON.self, from: Data(json.utf8)))
    }
    func testCreditedIncomeSumsOnlyClearedTopics() throws {
        let value = try summary(#"{"isOwner":true,"topics":[{"settled":true,"myIncome":12.5,"myIncomeArrived":true},{"settled":true,"myIncome":3,"myIncomeArrived":false},{"settled":false},{"settled":true,"myIncome":0}],"adjustments":{"pendingAmount":0,"executedAmount":2,"pendingReason":"  "}}"#)
        XCTAssertEqual(value.creditedIncome, Decimal(string: "12.5"))
        XCTAssertFalse(value.showsPendingAdjustment); XCTAssertTrue(value.showsExecutedAdjustment)
        XCTAssertEqual(value.executedAdjustment, 2); XCTAssertNil(value.pendingReason); XCTAssertTrue(value.isOwner)
    }
    func testUnknownFactsNeverBecomeZero() throws {
        for topic in [#"{"myIncome":1}"#, #"{"settled":true}"#, #"{"settled":true,"myIncome":"5","myIncomeArrived":true}"#,
                      #"{"settled":true,"myIncome":5}"#, #"{"settled":true,"myIncome":-1,"myIncomeArrived":true}"#] {
            XCTAssertNil(try summary("{\"topics\":[\(topic)]}").creditedIncome, topic)
        }
        let missing = try summary(#"{"topics":[]}"#)
        XCTAssertEqual(missing.creditedIncome, 0)
        XCTAssertNil(missing.pendingAdjustment); XCTAssertTrue(missing.showsPendingAdjustment)
        XCTAssertTrue(missing.showsExecutedAdjustment); XCTAssertFalse(missing.isOwner)
    }
    func testPendingReasonIsTrimmed() throws {
        XCTAssertEqual(try summary(#"{"adjustments":{"pendingAmount":4,"pendingReason":" 退款扣回 "}}"#).pendingReason, "退款扣回")
    }
}
