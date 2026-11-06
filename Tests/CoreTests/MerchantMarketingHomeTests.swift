import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Source pages/merchant/utils/merchant-aggregate.js normalizeMarketingHome and marketing/index.js.
@MainActor final class MerchantMarketingHomeTests: XCTestCase {
    private func raw(_ json: String) throws -> MerchantMarketingValue { try JSONDecoder().decode(MerchantMarketingValue.self, from: Data(json.utf8)) }
    private func service(_ transport: MerchantMarketingFixtureTransport) throws -> MerchantMarketingService {
        let scope = try MerchantMarketingScope(namespace: "fixture-cn", accountID: 700, epoch: 1, token: "fixture-token")
        return try MerchantMarketingService(configuration: APIConfiguration(baseURL: URL(string: "https://merchant-marketing.example")!), transport: transport,
                                            gates: .init(reads: true), currentSession: { scope })
    }
    private func mutated(_ change: (inout [String: Any]) -> Void) throws -> MerchantMarketingValue {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(MerchantMarketingFixtureTransport.homeJSON.utf8)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(MerchantMarketingValue.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testHomeSendsThirtyDayWindowAsQueryAfterAccess() async throws {
        let transport = MerchantMarketingFixtureTransport()
        let (access, home) = try await service(transport).home()
        XCTAssertTrue(access.canReadMarketing); XCTAssertTrue(access.canManageProjects); XCTAssertFalse(access.canManageCoop)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/marketing-home"])
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(transport.requests.last?.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "windowDays", value: "30")])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "POST" && $0.httpBody == nil })
        XCTAssertEqual(home.recruiting.count, 2); XCTAssertEqual(home.coupons.couponTotal, 4)
        XCTAssertEqual(home.analytics?.stages.map(\.code), MerchantMarketingHome.stageCodes)
    }
    func testHomeDeniedBeforeAggregate() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "denied")
        do { _ = try await service(transport).home(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .denied) }
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/merchant/access/me"])
    }
    func testHeroUsesSignupAndVerifyCountsWithoutRates() throws {
        let home = try MerchantMarketingHome(raw(MerchantMarketingFixtureTransport.homeJSON))
        XCTAssertEqual(home.heroValue, "1.2万")
        XCTAssertEqual(home.heroSubtitle, .verified("3"))
        XCTAssertNil(home.verifiedAfterReceivePercent)
        XCTAssertTrue(home.hasCouponDeck); XCTAssertEqual(home.couponGhosts, 2); XCTAssertFalse(home.isAllZero)
    }
    func testCompactMatchesSourceRounding() {
        XCTAssertEqual(MerchantMarketingHome.compact(0), "0"); XCTAssertEqual(MerchantMarketingHome.compact(9999), "9999")
        XCTAssertEqual(MerchantMarketingHome.compact(10000), "1万"); XCTAssertEqual(MerchantMarketingHome.compact(12345), "1.2万")
        XCTAssertEqual(MerchantMarketingHome.compact(125_000), "12.5万")
    }
    func testAllZeroIsEmptyAndHasNoDeck() throws {
        let home = try MerchantMarketingHome(raw(MerchantMarketingFixtureTransport.emptyHomeJSON))
        XCTAssertTrue(home.isAllZero); XCTAssertFalse(home.hasCouponDeck); XCTAssertEqual(home.couponGhosts, 0)
        XCTAssertEqual(home.heroValue, "0"); XCTAssertEqual(home.heroSubtitle, .verified("0"))
    }
    func testStoppedCouponsKeepTheDeckThroughCouponTotal() throws {
        let home = try MerchantMarketingHome(mutated { root in
            root["coupons"] = ["couponCount": 0, "couponTotal": 2, "received": 4, "verified": 1]
        })
        XCTAssertTrue(home.hasCouponDeck); XCTAssertEqual(home.couponGhosts, 0); XCTAssertEqual(home.verifiedAfterReceivePercent, 25)
    }
    func testOldServerFallbacks() throws {
        let home = try MerchantMarketingHome(mutated { root in
            root["coupons"] = ["couponCount": "5", "received": 0, "verified": 0]
            root["recruiting"] = ["count": 3.7, "items": []]
        })
        XCTAssertEqual(home.coupons.couponTotal, 5); XCTAssertEqual(home.recruiting.count, 3)
        XCTAssertEqual(home.recruiting.openCount, 3); XCTAssertNil(home.recruiting.shownCount); XCTAssertFalse(home.recruiting.hasMoreOpen)
    }
    func testMissingRequiredCountsRejectWholeResponse() throws {
        for path in [("recruiting", "count"), ("coupons", "received"), ("content", "activityCount")] {
            XCTAssertThrowsError(try MerchantMarketingHome(mutated { root in
                var section = root[path.0] as! [String: Any]; section.removeValue(forKey: path.1); root[path.0] = section
            }), path.1)
        }
        XCTAssertThrowsError(try MerchantMarketingHome(mutated { root in root["recruiting"] = ["count": 1] }))
        XCTAssertThrowsError(try MerchantMarketingHome(mutated { root in root["coupons"] = ["couponCount": -1, "received": 0, "verified": 0] }))
        XCTAssertThrowsError(try MerchantMarketingHome(raw("{}")))
    }
    func testInvalidAnalyticsKeepsCountsButDropsStages() throws {
        let bad = try MerchantMarketingHome(raw(MerchantMarketingFixtureTransport.badAnalyticsHomeJSON))
        XCTAssertNil(bad.analytics); XCTAssertEqual(bad.heroValue, "0"); XCTAssertEqual(bad.coupons.couponCount, 3)
        let wrongRate = try MerchantMarketingHome(mutated { root in
            var analytics = root["analytics"] as! [String: Any]; var stages = analytics["stages"] as! [[String: Any]]
            stages[0]["changeRate"] = 0.5; analytics["stages"] = stages; root["analytics"] = analytics
        })
        XCTAssertNil(wrongRate.analytics)
        let misaligned = try MerchantMarketingHome(mutated { root in
            var analytics = root["analytics"] as! [String: Any]; var window = analytics["window"] as! [String: Any]
            window["endExclusive"] = (window["endExclusive"] as! Int) + 3_600_000; analytics["window"] = window; root["analytics"] = analytics
        })
        XCTAssertNil(misaligned.analytics)
        let attributed = try MerchantMarketingHome(mutated { root in
            var analytics = root["analytics"] as! [String: Any]; var points = analytics["touchpoints"] as! [String: Any]
            points["attributed"] = true; analytics["touchpoints"] = points; root["analytics"] = analytics
        })
        XCTAssertNil(attributed.analytics)
        let reordered = try MerchantMarketingHome(mutated { root in
            var analytics = root["analytics"] as! [String: Any]; var stages = analytics["stages"] as! [[String: Any]]
            stages.swapAt(0, 1); analytics["stages"] = stages; root["analytics"] = analytics
        })
        XCTAssertNil(reordered.analytics)
    }
    func testCoordinatorDashboardLoadsHomeAndClearsOnSessionChange() async throws {
        let transport = MerchantMarketingFixtureTransport()
        let model = MerchantMarketingCoordinator(service: try service(transport))
        await model.load(.dashboard)
        XCTAssertEqual(model.home?.recruiting.count, 2); XCTAssertNotNil(model.homeAccess); XCTAssertNil(model.failure)
        model.sessionChanged()
        XCTAssertNil(model.home); XCTAssertNil(model.homeAccess)
    }
}
