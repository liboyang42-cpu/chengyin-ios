import XCTest
@testable import QuestifyCore

final class CoopFinanceProfitTests: XCTestCase {
    private func decode(_ json: String) throws -> CoopFlowJSON { try JSONDecoder().decode(CoopFlowJSON.self, from: Data(json.utf8)) }

    func testClearedIncomeTotalsAndPendingRowsSortFirst() throws {
        let profit = try CoopFinanceProfit(decode("""
        {"isOwner":true,"topics":[
          {"topicId":1,"topicName":"Done","settled":true,"myIncome":12.5,"myIncomeArrived":true,"merchantTotal":10,"merchantPaid":10,"merchantPayoutTime":"2026-10-01 10:00:00"},
          {"topicId":2,"topicName":"Open","settled":false,"myIncome":5},
          {"topicId":3,"settled":true,"myIncome":0,"myIncomeArrived":false,"merchantTotal":0}
        ]}
        """))
        XCTAssertEqual(profit.topics.map(\.topicID), [2, 1, 3])
        XCTAssertEqual(profit.topics[0].status, .unsettled)
        XCTAssertEqual(profit.topics[1].status, .credited); XCTAssertEqual(profit.topics[1].status.badge, .success)
        XCTAssertEqual(profit.topics[1].merchantStatus, .paid); XCTAssertEqual(profit.topics[1].payoutDate, "2026-10-01")
        XCTAssertEqual(profit.topics[2].status, .noIncomeDue); XCTAssertEqual(profit.topics[2].merchantStatus, .noMerchantShare)
        XCTAssertEqual(profit.myIncomeTotal, Decimal(string: "12.5"))
        XCTAssertEqual(profit.withdrawState, .positive); XCTAssertTrue(profit.canWithdraw)
        XCTAssertEqual(profit.pendingCount, 1); XCTAssertTrue(profit.isOwner)
    }

    func testUnknownIncomeNeverBecomesZeroAndBlocksWithdrawal() throws {
        let profit = try CoopFinanceProfit(decode("""
        {"topics":[{"topicId":4,"settled":true,"myIncome":"8.00","myIncomeArrived":true},
                   {"topicId":5,"settled":true,"myIncome":3}]}
        """))
        XCTAssertNil(profit.myIncomeTotal)
        XCTAssertEqual(profit.withdrawState, .unknown); XCTAssertFalse(profit.canWithdraw)
        XCTAssertEqual(profit.topics.map(\.status), [.amountUnknown, .arrivalUnknown])
        XCTAssertEqual(profit.stats.first, .init(key: .income, amount: nil))
        XCTAssertFalse(profit.isOwner)
    }

    func testMerchantPayoutStatesAndNegativeMoneyIsUnknown() throws {
        let profit = try CoopFinanceProfit(decode("""
        {"topics":[{"topicId":1,"settled":true,"myIncome":0,"merchantTotal":10,"merchantPaid":4},
                   {"topicId":2,"settled":true,"myIncome":0,"merchantTotal":10,"merchantPaid":0},
                   {"topicId":3,"settled":true,"myIncome":0,"merchantTotal":10},
                   {"topicId":4,"settled":true,"myIncome":0,"merchantTotal":-1}]}
        """))
        XCTAssertEqual(profit.topics.map(\.merchantStatus), [.partiallyPaid, .unpaid, .payoutUnknown, .amountUnknown])
        XCTAssertEqual(profit.myIncomeTotal, 0); XCTAssertEqual(profit.withdrawState, .zero)
    }

    func testAdjustmentStatsHideZeroButKeepUnknown() throws {
        let zero = try CoopFinanceProfit(decode(#"{"topics":[],"adjustments":{"pendingAmount":0,"executedAmount":"0"}}"#))
        XCTAssertEqual(zero.stats.map(\.key), [.income])
        let known = try CoopFinanceProfit(decode(#"{"topics":[],"adjustments":{"pendingAmount":"3.5","executedAmount":2,"pendingReason":"  refund  "}}"#))
        XCTAssertEqual(known.stats, [.init(key: .income, amount: 0), .init(key: .adjustPending, amount: Decimal(string: "3.5")), .init(key: .adjustExecuted, amount: 2)])
        XCTAssertEqual(known.adjustReason, "refund")
        let unknown = try CoopFinanceProfit(decode(#"{"topics":[],"adjustments":{"pendingAmount":"abc"}}"#))
        XCTAssertEqual(unknown.stats.map(\.amount), [0, nil, nil])
    }

    func testMalformedEnvelopeRejectsWholeRead() throws {
        XCTAssertThrowsError(try CoopFinanceProfit(decode(#"{"topics":{}}"#)))
        XCTAssertThrowsError(try CoopFinanceProfit(decode(#"{"topics":[1]}"#)))
        XCTAssertThrowsError(try CoopFinanceProfit(decode(#"[]"#)))
    }

    func testIssueClassesAndPlainAmountText() {
        XCTAssertEqual(CoopFinanceProfit.issue(for: APIError.unauthorized), .authRequired)
        XCTAssertEqual(CoopFinanceProfit.issue(for: CoopFlowFailure.server(403, nil)), .accessDenied)
        XCTAssertEqual(CoopFinanceProfit.issue(for: CoopFlowFailure.malformed), .failed)
        XCTAssertEqual(CoopFinanceProfit.plainText(Decimal(string: "1234.5")!), "1234.50")
    }
}
