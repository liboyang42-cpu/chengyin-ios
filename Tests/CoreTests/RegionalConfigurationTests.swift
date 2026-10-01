import XCTest
@testable import QuestifyCore

final class RegionalConfigurationTests: XCTestCase {
    // Test-only URLs, never shipped deployment defaults or approval evidence.
    private let cnURL = "https://cn.example.com/api-root"
    private let usURL = "https://us.example.com/api-root"

    func testFirstLaunchDefaultsAndExistingChoices() {
        XCTAssertEqual(RegionalMarket.china.language(storedValue: nil), .simplifiedChinese)
        XCTAssertEqual(RegionalMarket.unitedStates.language(storedValue: nil), .english)
        for market in RegionalMarket.allCases {
            for language in AppLanguage.allCases {
                XCTAssertEqual(market.language(storedValue: language.rawValue), language)
            }
            XCTAssertEqual(market.language(storedValue: "legacy-unknown"), .system)
        }
    }
    func testMarketMustBeExplicit() throws {
        XCTAssertEqual(try RegionalConfiguration.market(buildValue: "CN"), .china)
        XCTAssertEqual(try RegionalConfiguration.market(buildValue: "US"), .unitedStates)
        for value in [nil, "", "en", "zh-Hans", "system", "GB", "cn"] as [String?] {
            XCTAssertThrowsError(try RegionalConfiguration.market(buildValue: value))
        }
    }
    func testDefaultProfilesHaveNoWorkingBackendOrCapabilities() throws {
        for market in RegionalMarket.allCases {
            let config = try RegionalConfiguration(market: market)
            XCTAssertNil(config.apiConfiguration)
            XCTAssertTrue(config.availableCapabilities.isEmpty)
        }
    }
    func testExactMarketAllowlistRejectsCrossMarketAndAlteredEndpoints() throws {
        let approvals: [RegionalMarket: Set<String>] = [.china: [cnURL], .unitedStates: [usURL]]
        let valid = try RegionalConfiguration(market: .china, baseURL: cnURL, approvedBaseURLs: approvals)
        XCTAssertEqual(valid.apiConfiguration?.baseURL.absoluteString, cnURL)
        for url in [usURL, cnURL + "/other", cnURL + "?token=x", "https://cn.example.com.evil.example/api-root", "http://cn.example.com/api-root", "https://cn.example.com:8443/api-root"] {
            XCTAssertThrowsError(try RegionalConfiguration(market: .china, baseURL: url, approvedBaseURLs: approvals))
        }
        XCTAssertThrowsError(try RegionalConfiguration(market: .china, baseURL: cnURL))
    }
    func testCNRequiresBothApprovedBackendAndVerifiedContract() throws {
        let noBackend = try RegionalConfiguration(market: .china, verifiedCapabilities: [.domesticChinaPhone])
        XCTAssertFalse(noBackend.canUseDomesticChinaPhone)
        let pending = try RegionalConfiguration(market: .china, baseURL: cnURL, approvedBaseURLs: [.china: [cnURL]])
        XCTAssertEqual(pending.availability(of: .domesticChinaPhone), .verificationPending)
        let ready = try RegionalConfiguration(market: .china, baseURL: cnURL,
            approvedBaseURLs: [.china: [cnURL]], verifiedCapabilities: [.domesticChinaPhone])
        XCTAssertTrue(ready.canUseDomesticChinaPhone)
        XCTAssertEqual(ready.availableCapabilities, [.domesticChinaPhone])
    }
    func testUSCannotEnableLegacyPhoneOrUnimplementedProviders() throws {
        let config = try RegionalConfiguration(market: .unitedStates, baseURL: usURL,
            approvedBaseURLs: [.unitedStates: [usURL]], verifiedCapabilities: Set(RegionalCapability.allCases))
        XCTAssertEqual(config.phoneContract, .internationalE164)
        XCTAssertFalse(config.canUseDomesticChinaPhone)
        XCTAssertEqual(config.availability(of: .domesticChinaPhone), .notRequested)
        XCTAssertTrue(config.availableCapabilities.isEmpty)
    }
    func testPaymentsPayoutsAndAppleRemainDisabledEvenWithVerificationFlags() throws {
        let config = try RegionalConfiguration(market: .china, baseURL: cnURL,
            approvedBaseURLs: [.china: [cnURL]], verifiedCapabilities: Set(RegionalCapability.allCases))
        for capability in [RegionalCapability.physicalEventPayment, .digitalContentPayment, .merchantPayout, .signInWithApple] {
            XCTAssertEqual(config.availability(of: capability), .implementationPending)
        }
    }
    func testLanguageSelectionCannotChangeMarketBackendOrCapability() throws {
        let config = try RegionalConfiguration(market: .china, baseURL: cnURL,
            approvedBaseURLs: [.china: [cnURL]], verifiedCapabilities: [.domesticChinaPhone])
        for language in AppLanguage.allCases {
            _ = config.market.language(storedValue: language.rawValue)
            XCTAssertEqual(config.market, .china)
            XCTAssertEqual(config.apiConfiguration?.baseURL.absoluteString, cnURL)
            XCTAssertEqual(config.availableCapabilities, [.domesticChinaPhone])
        }
    }
}
