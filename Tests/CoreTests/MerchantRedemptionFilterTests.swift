import XCTest
@testable import QuestifyCore

final class MerchantRedemptionFilterTests: XCTestCase {
    func testSourceChoicesAndOrderingMatchServerContract() {
        XCTAssertEqual(MerchantRedemptionFilter.allCases.map(\.rawValue), ["all", "pending", "handled", "no_cash"])
        XCTAssertEqual(Set(MerchantRedemptionFilter.allCases.map(\.rawValue)).count, 4)
    }
    func testProcessedIsDistinctFromUnsupportedSettledWireValue() {
        XCTAssertEqual(MerchantRedemptionFilter(rawValue: "handled"), .handled)
        XCTAssertNil(MerchantRedemptionFilter(rawValue: "settled"))
        XCTAssertEqual(MerchantRedemptionFilter.handled.titleKey, "merchant.redemptionFilter.handled")
    }
    func testEveryChoiceUsesExistingReadRouteExactWireValueAndPermissions() throws {
        for option in MerchantRedemptionFilter.allCases {
            let query = MerchantBusinessQuery.redemptions(filter: option.rawValue, page: 1)
            let request = try query.request()
            XCTAssertEqual(request.path, "api/merchant/finance/redemptions")
            XCTAssertEqual(request.query, [:])
            XCTAssertEqual(request.body, .json(["pageNum": .int(1), "pageSize": .int(20), "filter": .string(option.rawValue)]))
            XCTAssertEqual(query.permissions, ["merchant:finance:read"])
        }
    }
    func testNextPageKeepsEachSelectedServerFilter() throws {
        for option in MerchantRedemptionFilter.allCases {
            let query = MerchantBusinessQuery.redemptions(filter: option.rawValue, page: 1).paged(3)
            XCTAssertEqual(query, .redemptions(filter: option.rawValue, page: 3))
            guard case .json(let fields) = try query.request().body else { return XCTFail() }
            XCTAssertEqual(fields["pageNum"], .int(3)); XCTAssertEqual(fields["filter"], .string(option.rawValue))
        }
    }
    func testUnknownAndLegacyInputsRemainUnchangedUntilExplicitSelection() throws {
        for raw in ["settled", "future-filter", "", "HANDLED", " handled "] {
            XCTAssertNil(MerchantRedemptionFilter(rawValue: raw))
            let query = MerchantBusinessQuery.redemptions(filter: raw, page: 2)
            XCTAssertEqual(query.paged(3), .redemptions(filter: raw, page: 3))
            guard case .json(let fields) = try query.request().body else { return XCTFail() }
            XCTAssertEqual(fields["filter"], .string(raw))
        }
    }
    func testFilterOptionDoesNotReclassifyServerRowsOrRecomputeSummary() throws {
        let query = MerchantBusinessQuery.redemptions(filter: "no_cash", page: 1)
        var fields = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(query).object)
        fields["summary"] = .object(["count": .int(71), "pendingAmount": .string("100.00")])
        let payload = MerchantBusinessValue.object(fields)
        let document = try MerchantBusinessDocument(query: query, payload: payload)
        XCTAssertEqual(document.query, query)
        XCTAssertEqual(document.payload, payload)
        XCTAssertEqual(document.summary, payload.object?["summary"]?.object ?? [:])
    }
}
