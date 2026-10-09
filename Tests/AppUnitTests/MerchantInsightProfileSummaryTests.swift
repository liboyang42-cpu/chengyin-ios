import XCTest
@testable import Questify

@MainActor final class MerchantInsightProfileSummaryTests: XCTestCase {
    private func view(_ profile: MerchantMarketingValue, scoped: Bool = true) -> MerchantInsightProfileSummary {
        .init(profile: profile, origin: scoped ? .init(merchantID: 31, readerScope: UUID()) : nil, open: { _ in })
    }
    func testExplicitFalseRemainsUnconfiguredEvenWithCapacityOrDemand() {
        let value = view(.object(["configured": .bool(false), "capacity": .number(20), "demand": .string("A real request")]))
        XCTAssertEqual(value.configurationState, false); XCTAssertEqual(value.capacity, 20)
        XCTAssertEqual(value.demand, "A real request"); XCTAssertTrue(value.canOpen)
    }
    func testMissingNullOrMalformedConfiguredIsUnknownWithoutNavigation() {
        for state in [MerchantMarketingValue.null, .string("false"), .number(0), .object([:])] {
            let value = view(.object(["configured": state, "capacity": .number(20)]))
            XCTAssertNil(value.configurationState); XCTAssertFalse(value.canOpen)
        }
        XCTAssertNil(view(.object([:])).configurationState)
        XCTAssertFalse(view(.null).canOpen)
    }
    func testZeroCapacityIsKnownButMalformedCountsAreNotCoerced() {
        XCTAssertEqual(view(.object(["capacity": .number(0)])).capacity, 0)
        for capacity in [MerchantMarketingValue.bool(false), .string("12"), .number(-1), .number(1.5), .null] {
            XCTAssertNil(view(.object(["capacity": capacity])).capacity)
        }
    }
    func testKnownStateStillNeedsSourceStoreScopeAndTypedRoute() throws {
        XCTAssertFalse(view(.object(["configured": .bool(true)]), scoped: false).canOpen)
        let origin = try XCTUnwrap(MerchantInsightOrigin(merchantID: 31, readerScope: UUID()))
        XCTAssertEqual(MerchantInsightDestination.cooperationSettings(origin).sourcePath, "/merchant/decor/coop-setting")
        XCTAssertNil(MerchantInsightDestination(rawValue: "cooperationSettings"))
        XCTAssertNil(MerchantInsightDestination(rawValue: "/merchant/decor/coop-setting"))
    }
}
