import XCTest
@testable import QuestifyCore

final class RegionalSessionStorageScopeTests: XCTestCase {
    private func scope(_ market: RegionalMarket = .china,
                       endpoint: String = "https://cn.example.com/api-root",
                       realm: String? = "cn-pilot", bundle: String? = "example.native") throws -> RegionalSessionStorageScope {
        let config = try RegionalConfiguration(market: market, baseURL: endpoint,
            approvedBaseURLs: [market: [endpoint]])
        return try RegionalSessionStorageScope(configuration: config, bundleIdentifier: bundle, realm: realm)
    }
    func testExactScopeIsStable() throws {
        XCTAssertEqual(try scope(), try scope())
        XCTAssertEqual(try scope().restoreBlockedKey, try scope().service + ".preventRestore")
    }
    func testEveryDeploymentDimensionSeparatesCredentialsAndRestoreMarkers() throws {
        let original = try scope()
        for other in [try scope(.unitedStates), try scope(endpoint: "https://cn2.example.com/api-root"),
                      try scope(endpoint: "https://cn.example.com/other"), try scope(endpoint: "https://cn.example.com:8443/api-root"),
                      try scope(realm: "cn-next"), try scope(bundle: "example.other")] {
            XCTAssertNotEqual(original.service, other.service)
            XCTAssertNotEqual(original.restoreBlockedKey, other.restoreBlockedKey)
        }
    }
    func testMissingOrMalformedIdentityFailsClosed() throws {
        for value in [nil, "", " ", "realm with spaces", "realm\n", "$(QUESTIFY_SESSION_REALM)", String(repeating: "x", count: 129)] as [String?] {
            XCTAssertThrowsError(try scope(realm: value))
            XCTAssertThrowsError(try scope(bundle: value))
        }
        let offline = try RegionalConfiguration(market: .china)
        XCTAssertThrowsError(try RegionalSessionStorageScope(configuration: offline,
            bundleIdentifier: "example.native", realm: "cn-pilot"))
    }
    func testCannotConstructStorageForUnapprovedEndpointOrInferMarket() {
        XCTAssertThrowsError(try RegionalConfiguration(market: .unitedStates,
            baseURL: "https://cn.example.com", approvedBaseURLs: [.china: ["https://cn.example.com"]]))
        for value in [nil, "", "en", "zh-Hans"] as [String?] {
            XCTAssertThrowsError(try RegionalConfiguration.market(buildValue: value))
        }
    }
    func testLanguageDoesNotChangeScopeOrEnableCapabilities() throws {
        for market in RegionalMarket.allCases {
            let config = try RegionalConfiguration(market: market, baseURL: "https://approved.example.com",
                approvedBaseURLs: [market: ["https://approved.example.com"]])
            let original = try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.native", realm: "pilot")
            for language in AppLanguage.allCases {
                _ = market.language(storedValue: language.rawValue)
                XCTAssertEqual(original, try RegionalSessionStorageScope(configuration: config,
                    bundleIdentifier: "example.native", realm: "pilot"))
                XCTAssertTrue(config.availableCapabilities.isEmpty)
                XCTAssertFalse(USAppleProductionGate.enabled)
            }
        }
    }
}
