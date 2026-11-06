import XCTest
@testable import QuestifyCore

/// Source ai-insight/index.js _buildValueCard delta rule.
final class MerchantInsightParityTests: XCTestCase {
    private func facts(_ json: String) throws -> MerchantMarketingValue { try JSONDecoder().decode(MerchantMarketingValue.self, from: Data(json.utf8)) }
    func testDeltaOnlyWithPositivePreviousAndChange() throws {
        XCTAssertEqual(MerchantInsightParity.visitorDelta(try facts(#"{"attribution":{"visitors":12,"prevVisitors":9}}"#)), 3)
        XCTAssertEqual(MerchantInsightParity.visitorDelta(try facts(#"{"attribution":{"visitors":4,"prevVisitors":9}}"#)), -5)
        XCTAssertNil(MerchantInsightParity.visitorDelta(try facts(#"{"attribution":{"visitors":4,"prevVisitors":0}}"#)))
        XCTAssertNil(MerchantInsightParity.visitorDelta(try facts(#"{"attribution":{"visitors":4,"prevVisitors":4}}"#)))
        XCTAssertNil(MerchantInsightParity.visitorDelta(try facts(#"{"attribution":{"visitors":4}}"#)))
        XCTAssertNil(MerchantInsightParity.visitorDelta(try facts(#"{"attribution":{"visitors":"4","prevVisitors":2}}"#)))
    }
    func testEmptyGuidanceCTAAndUnknownFactCopy() {
        XCTAssertEqual(MerchantInsightParity.emptyCTATitle(isEmpty: true), "去合作中心看看")
        XCTAssertNil(MerchantInsightParity.emptyCTATitle(isEmpty: false))
        XCTAssertEqual(MerchantInsightParity.factValueText(nil), "数据待同步")
        XCTAssertEqual(MerchantInsightParity.factValueText(" — "), "数据待同步")
        XCTAssertEqual(MerchantInsightParity.factValueText("32%"), "32%")
        XCTAssertEqual(MerchantInsightParity.factIntText(nil), "数据待同步")
        XCTAssertEqual(MerchantInsightParity.factIntText(18), "18")
    }
}
