import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class I00UserInfoTransport: HTTPTransport {
    let response: String
    var requests: [URLRequest] = []
    init(_ response: String) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), 200) }
}

/// I00 baseline: the unconfigured build stays OFF, and a current-account projection that carries no
/// explicit server role (the hengyin master userInfo whitelist) never establishes a native session.
@MainActor final class I00SessionAdmissionBaselineTests: XCTestCase {
    private let endpoint = "https://cn.example.com/gateway"
    /// Exact key set of the master `userInfoView` whitelist, with sanitized synthetic values only.
    private func masterProjection(userType: Int) -> String {
        #"{"code":200,"msg":"操作成功","appUser":{"createBy":null,"createTime":null,"updateBy":null,"updateTime":null,"remark":null,"#
        + #""userId":17,"userName":"synthetic","nickName":"Synthetic","email":"","mobile":"","sex":"0","avatar":"","#
        + #""status":"1","delFlag":"0","loginIp":"","loginDate":null,"userType":\#(userType)}}"#
    }
    private func configuration() throws -> RegionalConfiguration {
        try RegionalConfiguration(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]],
            verifiedCapabilities: [.domesticChinaPhone])
    }

    func testUnconfiguredBuildHasNoEndpointCapabilityOrVault() throws {
        for market in RegionalMarket.allCases {
            let config = try RegionalConfiguration(market: market)
            XCTAssertNil(config.apiConfiguration)
            XCTAssertTrue(config.availableCapabilities.isEmpty)
            XCTAssertThrowsError(try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.native", realm: "cn-fixture"))
        }
        XCTAssertThrowsError(try RegionalConfiguration(market: .china, baseURL: endpoint)) {
            XCTAssertEqual($0 as? RegionalConfigurationError, .unapprovedBackend)
        }
        let unverified = try RegionalConfiguration(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]])
        XCTAssertEqual(unverified.availability(of: .domesticChinaPhone), .verificationPending)
        XCTAssertFalse(unverified.canUseDomesticChinaPhone)
        let scope = try RegionalSessionStorageScope(configuration: unverified, bundleIdentifier: "example.native", realm: "cn-fixture")
        XCTAssertThrowsError(try CNAccountSessionService(configuration: unverified, storageScope: scope, transport: I00UserInfoTransport("{}")))
    }

    func testMasterUserInfoProjectionWithoutRoleCannotRestoreOrCompleteLogin() async throws {
        let config = try configuration()
        let scope = try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.native", realm: "cn-fixture")
        let api = try XCTUnwrap(config.apiConfiguration)
        for userType in [1, 2] {
            let raw = masterProjection(userType: userType)
            struct Envelope: Decodable { let appUser: Account }
            let decoded = try JSONDecoder().decode(Envelope.self, from: Data(raw.utf8)).appUser
            XCTAssertEqual(decoded.id, 17); XCTAssertEqual(decoded.role, "", "The master whitelist carries no role key")
            XCTAssertEqual(decoded.effectiveRole, userType == 2 ? "merchant" : "player", "Presentation fallback exists but is never an admission")
            let restore = I00UserInfoTransport(raw)
            do { _ = try await CNAccountSessionService(configuration: config, storageScope: scope, transport: restore).currentAccount(token: "synthetic-session"); XCTFail("userType must not stand in for a server role") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            XCTAssertEqual(restore.requests.count, 1)
            let readback = I00UserInfoTransport(raw)
            do { _ = try await AuthChannelService(configuration: api, transport: readback).currentAccount(token: "synthetic-session"); XCTFail("Login readback must not default a role") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testExplicitServerRoleInSameProjectionIsTheOnlyAdmission() async throws {
        let config = try configuration()
        let scope = try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.native", realm: "cn-fixture")
        let raw = masterProjection(userType: 1).replacingOccurrences(of: #""userType":1}"#, with: #""userType":1,"role":"club"}"#)
        let account = try await CNAccountSessionService(configuration: config, storageScope: scope, transport: I00UserInfoTransport(raw))
            .currentAccount(token: "synthetic-session")
        XCTAssertEqual(account.id, 17); XCTAssertEqual(account.role, "club"); XCTAssertEqual(account.effectiveRole, "club")
    }
}
