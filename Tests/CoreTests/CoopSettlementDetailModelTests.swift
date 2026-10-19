import XCTest
@testable import QuestifyCore

final class CoopSettlementDetailModelTests: XCTestCase {
    private func decode(_ json: String) throws -> CoopFlowJSON { try JSONDecoder().decode(CoopFlowJSON.self, from: Data(json.utf8)) }
    private let hostRow = #"{"topicId":7,"topicName":"Lake walk","settled":true,"myIncome":20,"myIncomeArrived":false,"totalSales":100,"verifiedSales":80,"platformAmount":5,"merchantTotal":40,"merchantPayableTime":"2026-10-02"}"#

    func testHostDetailSelectsTopicAndMapsBreakdownAndTimeline() throws {
        let detail = try CoopSettlementDetailModel.resolve(source: .finance, data: decode(#"{"topics":["# + hostRow + "]}"), id: 7)
        XCTAssertEqual(detail.perspective, .host); XCTAssertEqual(detail.status, .awaitingCredit); XCTAssertEqual(detail.tone, .warning)
        XCTAssertEqual(detail.amount, 20); XCTAssertEqual(detail.topicName, "Lake walk")
        XCTAssertEqual(detail.lines.map(\.key), ["totalSales", "verifiedSales", "platform", "merchant", "income"])
        XCTAssertTrue(detail.lines.last!.strong)
        XCTAssertEqual(detail.timeline.map(\.key), ["hostSettled", "hostAwaiting", "merchantPayable"])
    }

    func testUnsettledHostHidesIncomeAndRejectsIncomeBeforeSettlement() throws {
        let unsettled = #"{"topicId":8,"settled":false,"myIncome":null,"myIncomeArrived":false,"totalSales":0,"verifiedSales":0,"platformAmount":0,"merchantTotal":0}"#
        let detail = try CoopSettlementDetailModel.resolve(source: .finance, data: decode(#"{"topics":["# + unsettled + "]}"), id: 8)
        XCTAssertNil(detail.amount); XCTAssertEqual(detail.status, .unsettled)
        XCTAssertEqual(detail.lines.last?.value, CoopSettlementDetailModel.Value.unavailable)
        let invalid = unsettled.replacingOccurrences(of: #""myIncome":null"#, with: #""myIncome":3"#)
        XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .finance, data: decode(#"{"topics":["# + invalid + "]}"), id: 8))
    }

    func testOneInvalidRowRejectsWholeResponseAndMissingRecordIsUnavailable() throws {
        let broken = #"{"topicId":9,"settled":"yes","myIncomeArrived":false}"#
        XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .finance, data: decode(#"{"topics":["# + hostRow + "," + broken + "]}"), id: 7)) {
            XCTAssertEqual($0 as? CoopFlowFailure, .malformed)
        }
        XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .finance, data: decode(#"{"topics":["# + hostRow + "]}"), id: 99)) {
            XCTAssertEqual($0 as? CoopFlowFailure, .unavailable)
        }
    }

    func testMerchantLedgerRowShareModesPayeeAndTimeline() throws {
        let row = #"{"id":31,"topicId":7,"payeeType":"club","verifiedSales":120.5,"verifiedHeads":6,"amount":30,"status":"1","shareMode":1,"shareRate":12.5,"createTime":"2026-10-01T09:30:00","payoutTime":"2026-10-05 10:00:00"}"#
        let detail = try CoopSettlementDetailModel.resolve(source: .mybiz, data: decode(#"{"settlements":["# + row + "]}"), id: 31)
        XCTAssertEqual(detail.status, .creditedBalance); XCTAssertEqual(detail.tone, .success)
        XCTAssertEqual(detail.lines.map(\.value), [.key("payee.club"), .money(Decimal(string: "120.5")!), .heads(6), .shareRate(Decimal(string: "12.5")!), .money(30)])
        XCTAssertEqual(detail.timeline, [.init("created", .date("2026-10-01 09:30")), .init("paid", .date("2026-10-05 10:00"))])
        let voided = row.replacingOccurrences(of: #""status":"1""#, with: #""status":2"#)
        XCTAssertEqual(try CoopSettlementDetailModel.resolve(source: .mybiz, data: decode(#"{"settlements":["# + voided + "]}"), id: 31).timeline.last, .init("void", .key("timeUnknown")))
    }

    func testMerchantValidationRejectsOutOfRangeTerms() throws {
        for bad in [#""shareMode":1,"shareRate":101"#, #""shareMode":3"#, #""shareMode":2,"fixedFee":-1"#] {
            let row = #"{"id":1,"verifiedSales":0,"verifiedHeads":0,"amount":0,"status":0,"# + bad + "}"
            XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .mybiz, data: decode(#"{"settlements":["# + row + "]}"), id: 1))
        }
        let fractionalHeads = #"{"id":1,"verifiedSales":0,"verifiedHeads":1.5,"amount":0,"status":0,"shareMode":0}"#
        XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .mybiz, data: decode(#"{"settlements":["# + fractionalHeads + "]}"), id: 1))
    }

    func testPermissionClassification() {
        XCTAssertTrue(CoopSettlementDetailModel.isPermission(APIError.unauthorized))
        XCTAssertTrue(CoopSettlementDetailModel.isPermission(CoopFlowFailure.server(403, nil)))
        XCTAssertTrue(CoopSettlementDetailModel.isPermission(CoopFlowFailure.server(500, "请先登录")))
        XCTAssertFalse(CoopSettlementDetailModel.isPermission(CoopFlowFailure.server(500, "busy")))
    }
}
