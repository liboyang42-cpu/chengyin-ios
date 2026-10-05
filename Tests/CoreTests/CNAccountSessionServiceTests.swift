import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor CNAccountSessionTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let response: (String, Int)
    private let failure: Error?
    private let suspend: Bool
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    var isSuspended: Bool { continuation != nil }
    init(response: (String, Int) = (#"{"code":200,"appUser":{"userId":17,"nickName":"Restored fixture","role":"player"}}"#, 200),
         failure: Error? = nil, suspend: Bool = false) {
        self.response = response; self.failure = failure; self.suspend = suspend
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return (Data(response.0.utf8), response.1)
    }
    func finish() {
        let pending = continuation; continuation = nil
        pending?.resume(returning: (Data(response.0.utf8), response.1))
    }
}

@MainActor
final class CNAccountSessionServiceTests: XCTestCase {
    private let endpoint = "https://cn.example.com/gateway"
    private func configuration(_ capabilities: Set<RegionalCapability> = [.domesticChinaPhone],
                               market: RegionalMarket = .china, endpoint: String? = nil) throws -> RegionalConfiguration {
        let value = endpoint ?? self.endpoint
        return try RegionalConfiguration(market: market, baseURL: value,
            approvedBaseURLs: [market: [value]], verifiedCapabilities: capabilities)
    }
    private func scope(_ config: RegionalConfiguration, realm: String = "cn-fixture") throws -> RegionalSessionStorageScope {
        try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.native", realm: realm)
    }
    private func service(_ transport: CNAccountSessionTransport,
                         capabilities: Set<RegionalCapability> = [.domesticChinaPhone]) throws -> CNAccountSessionService {
        let config = try configuration(capabilities)
        return try CNAccountSessionService(configuration: config, storageScope: scope(config), transport: transport)
    }

    func testPhoneOnlyConfigurationRestoresWithoutPasswordCapabilityOrLoginRequest() async throws {
        let config = try configuration()
        XCTAssertEqual(config.availability(of: .usernamePassword), .implementationPending)
        XCTAssertEqual(config.availableCapabilities, [.domesticChinaPhone])
        let transport = CNAccountSessionTransport()
        let api = try CNAccountSessionService(configuration: config, storageScope: scope(config), transport: transport)
        let account = try await api.currentAccount(token: "synthetic-phone-session")
        XCTAssertEqual(account.id, 17)
        XCTAssertEqual(account.nickname, "Restored fixture")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, endpoint + "/api/userInfo")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-phone-session")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }
    func testPasswordFlagCannotEnableIncompatibleNativeRestoration() async throws {
        let transport = CNAccountSessionTransport()
        XCTAssertThrowsError(try service(transport, capabilities: [.usernamePassword])) {
            XCTAssertEqual($0 as? APIError, .notConfigured)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testPhoneOnlyLogoutUsesExistingRevocationContractWithoutLoginOrSMS() async throws {
        let transport = CNAccountSessionTransport(response: (#"{"code":200}"#, 200))
        try await service(transport).logout(token: "synthetic-phone-session")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/gateway/api/logout")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-phone-session")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertFalse(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!.contains("name="))
    }
    func testUnverifiedCNConfigurationCannotConstructRestorerOrDispatch() async throws {
        let transport = CNAccountSessionTransport()
        let capabilitySets: [Set<RegionalCapability>] = [[], [.signInWithApple], [.internationalPhone]]
        for capabilities in capabilitySets {
            let config = try configuration(capabilities)
            XCTAssertThrowsError(try CNAccountSessionService(configuration: config, storageScope: scope(config), transport: transport)) {
                XCTAssertEqual($0 as? APIError, .notConfigured)
            }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testUSCannotUseLegacyCNRestorationEvenWithEveryVerificationFlag() async throws {
        let transport = CNAccountSessionTransport()
        let config = try configuration(Set(RegionalCapability.allCases), market: .unitedStates)
        XCTAssertThrowsError(try CNAccountSessionService(configuration: config, storageScope: scope(config), transport: transport)) {
            XCTAssertEqual($0 as? APIError, .notConfigured)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(USAppleProductionGate.enabled)
    }
    func testDifferentEndpointOrMarketCannotReuseVaultScope() async throws {
        let transport = CNAccountSessionTransport()
        let cn = try configuration()
        let original = try scope(cn)
        for other in [try configuration(endpoint: "https://cn2.example.com/gateway"),
                      try configuration(endpoint: endpoint + "/other"),
                      try configuration(market: .unitedStates)] {
            XCTAssertFalse(original.matches(configuration: other))
            XCTAssertThrowsError(try CNAccountSessionService(configuration: other, storageScope: original, transport: transport))
        }
        let offline = try RegionalConfiguration(market: .china, verifiedCapabilities: [.domesticChinaPhone])
        XCTAssertFalse(original.matches(configuration: offline))
        XCTAssertThrowsError(try CNAccountSessionService(configuration: offline, storageScope: original, transport: transport))
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testRealmChangesKeepRestorationAndTombstoneIdentitiesDistinct() throws {
        let config = try configuration()
        let first = try CNAccountSessionService(configuration: config, storageScope: scope(config, realm: "cn-first"), transport: CNAccountSessionTransport())
        let next = try CNAccountSessionService(configuration: config, storageScope: scope(config, realm: "cn-next"), transport: CNAccountSessionTransport())
        XCTAssertNotEqual(first.storageScope, next.storageScope)
        XCTAssertNotEqual(first.storageScope.service, next.storageScope.service)
        XCTAssertNotEqual(first.storageScope.restoreBlockedKey, next.storageScope.restoreBlockedKey)
    }
    func testInvalidSavedCredentialsDoNotDispatch() async throws {
        let transport = CNAccountSessionTransport()
        let api = try service(transport)
        for token in ["", " ", "bad\nheader", "非ASCII"] {
            do { _ = try await api.currentAccount(token: token); XCTFail("Invalid saved token must not dispatch") }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testUnauthorizedIsDistinctFromOfflineAndServerFailure() async throws {
        for (response, expected) in [(("{}", 401), APIError.unauthorized),
                                    ((#"{"code":401}"#, 200), APIError.unauthorized),
                                    (("{}", 503), APIError.httpStatus(503))] {
            let transport = CNAccountSessionTransport(response: response)
            do { _ = try await service(transport).currentAccount(token: "fixture"); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? APIError, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        let transport = CNAccountSessionTransport(failure: URLError(.notConnectedToInternet))
        do { _ = try await service(transport).currentAccount(token: "fixture"); XCTFail("Must preserve network failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
    func testLoginShapeAndMalformedCurrentAccountCannotRestore() async throws {
        for json in [#"{"code":200,"data":{"id":17},"token":"must-not-replace"}"#,
                     #"{"code":200,"appUser":{"id":0}}"#, #"{"code":200}"#, "not-json"] {
            let transport = CNAccountSessionTransport(response: (json, 200))
            do { _ = try await service(transport).currentAccount(token: "fixture"); XCTFail("Only valid current account is accepted") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testCancellationBeforeRestoreDoesNotDispatch() async throws {
        let transport = CNAccountSessionTransport(); let api = try service(transport)
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await api.currentAccount(token: "fixture"); return false }
            catch { return error is CancellationError }
        }
        let cancelled = await task.value
        let requests = await transport.requests
        XCTAssertTrue(cancelled); XCTAssertTrue(requests.isEmpty)
    }
    func testCancellationAfterTransportPreventsReturningSavedAccount() async throws {
        let transport = CNAccountSessionTransport(suspend: true)
        let api = try service(transport)
        let task = Task { () -> Bool in
            do { _ = try await api.currentAccount(token: "fixture"); return false }
            catch { return error is CancellationError }
        }
        while !(await transport.isSuspended) { await Task.yield() }
        task.cancel(); await transport.finish()
        let cancelled = await task.value
        let requests = await transport.requests
        XCTAssertTrue(cancelled); XCTAssertEqual(requests.count, 1)
    }
    func testExactNativeSMSAndSessionRequestShapes() throws {
        let config = try configuration(), api = try XCTUnwrap(config.apiConfiguration)
        let builder = AuthRequestBuilder(configuration: api)
        let valid = [try builder.make(.smsSend, fields: ["phone": "10000000000"], boundary: "CN-CONTRACT"),
                     try builder.make(.phone, fields: ["phone": "10000000000", "code": "123456"], boundary: "CN-CONTRACT"),
                     try builder.make(.userInfo, token: "synthetic-session"),
                     try builder.make(.logout, token: "synthetic-session", boundary: "CN-CONTRACT")]
        for request in valid { XCTAssertTrue(CNAccountSessionService.accepts(request, configuration: api)) }
        XCTAssertEqual(String(data: try XCTUnwrap(valid[1].httpBody), encoding: .utf8),
            "--CN-CONTRACT\r\nContent-Disposition: form-data; name=\"code\"\r\n\r\n123456\r\n--CN-CONTRACT\r\nContent-Disposition: form-data; name=\"phone\"\r\n\r\n10000000000\r\n--CN-CONTRACT--\r\n")
        let denied = [try builder.make(.password, fields: ["username": "synthetic", "password": "synthetic"]),
                      try builder.make(.apple, fields: ["identityToken": "synthetic"]),
                      try builder.make(.phone, fields: ["phone": "10000000000", "code": "123456", "role": "merchant"]),
                      try builder.make(.phone, fields: ["phone": "20000000000", "code": "123456"]),
                      try builder.make(.phone, fields: ["phone": "10000000000", "code": "123"]),
                      try builder.make(.smsSend, fields: ["phone": "10000000000"], token: "synthetic"),
                      try builder.make(.userInfo), try builder.make(.logout)]
        for request in denied { XCTAssertFalse(CNAccountSessionService.accepts(request, configuration: api)) }
        var tampered = valid[1]
        tampered.httpBody?.append(Data("extra".utf8))
        XCTAssertFalse(CNAccountSessionService.accepts(tampered, configuration: api))
        tampered = valid[1]; tampered.url = URL(string: api.url(for: .phone).absoluteString + "?role=merchant")
        XCTAssertFalse(CNAccountSessionService.accepts(tampered, configuration: api))
        tampered = valid[2]; tampered.httpBody = Data()
        XCTAssertFalse(CNAccountSessionService.accepts(tampered, configuration: api))
    }
    func testAnonymousPhoneRequestRejectsForeignTokenAndSessionBodyInjection() throws {
        let config = try configuration(), api = try XCTUnwrap(config.apiConfiguration)
        let builder = AuthRequestBuilder(configuration: api)
        var request = try builder.make(.phone, fields: ["phone": "10000000000", "code": "123456"])
        request.setValue("synthetic", forHTTPHeaderField: "Authorization")
        XCTAssertFalse(CNAccountSessionService.accepts(request, configuration: api))
        request = try builder.make(.logout, fields: ["userId": "8"], token: "synthetic")
        XCTAssertFalse(CNAccountSessionService.accepts(request, configuration: api))
        request = try builder.make(.phone, fields: ["phone": "10000000000", "code": "123456"])
        request.httpMethod = "GET"
        XCTAssertFalse(CNAccountSessionService.accepts(request, configuration: api))
    }
    func testMissingOrUnknownRoleCannotRestoreFromLegacyCachedProjection() async throws {
        for role in ["", "unexpected", "administrator", "Player", " player", "player ", "merchant/admin"] {
            let transport = CNAccountSessionTransport(response: ("{\"code\":200,\"appUser\":{\"userId\":17,\"userType\":2,\"role\":\"\(role)\"}}", 200))
            do { _ = try await service(transport).currentAccount(token: "synthetic"); XCTFail("Unverified role restored") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testCanonicalAllowlistRejectsDuplicateFramingOversizeAndAuthorityChanges() throws {
        let config = try configuration(), api = try XCTUnwrap(config.apiConfiguration)
        let builder = AuthRequestBuilder(configuration: api)
        let original = try builder.make(.phone, fields: ["phone": "10000000000", "code": "123456"], boundary: "CN-REVIEW")
        let body = try XCTUnwrap(String(data: try XCTUnwrap(original.httpBody), encoding: .utf8))
        var candidates: [URLRequest] = []
        var request = original
        request.httpBody = Data(body.replacingOccurrences(of: "--CN-REVIEW--\r\n",
            with: "--CN-REVIEW\r\nContent-Disposition: form-data; name=\"code\"\r\n\r\n654321\r\n--CN-REVIEW--\r\n").utf8)
        candidates.append(request)
        request = original; request.httpBody = Data(body.replacingOccurrences(of: "\r\n", with: "\n").utf8)
        candidates.append(request)
        request = original; request.httpBody = Data(repeating: 0x41, count: 1025)
        candidates.append(request)
        request = original; request.setValue("multipart/form-data; boundary=\"CN-REVIEW\"", forHTTPHeaderField: "Content-Type")
        candidates.append(request)
        request = original; request.setValue("text/plain", forHTTPHeaderField: "Accept")
        candidates.append(request)
        request = original; request.httpBodyStream = InputStream(data: try XCTUnwrap(original.httpBody))
        candidates.append(request)
        for suffix in ["?phone=10000000001", "#fragment", "/"] {
            request = original; request.url = URL(string: api.url(for: .phone).absoluteString + suffix)
            candidates.append(request)
        }
        request = original; request.url = URL(string: "https://other.example.com/gateway/api/login/phone")
        candidates.append(request)
        request = original; request.url = URL(string: "https://cn.example.com/api/login/phone")
        candidates.append(request)
        for candidate in candidates {
            XCTAssertFalse(CNAccountSessionService.accepts(candidate, configuration: api))
        }
        XCTAssertTrue(CNAccountSessionService.accepts(original, configuration: api))
    }
    func testExplicitRoleOverridesLegacyPresentationAliasWithoutInventingOne() async throws {
        for role in ["player", "club", "merchant"] {
            let transport = CNAccountSessionTransport(response: (
                "{\"code\":200,\"appUser\":{\"id\":17,\"userId\":17,\"nickname\":\"Current\",\"role\":\"\(role)\",\"userType\":2}}", 200))
            let account = try await service(transport).currentAccount(token: "synthetic")
            XCTAssertEqual(account.id, 17); XCTAssertEqual(account.role, role)
            XCTAssertEqual(account.effectiveRole, role)
        }
    }

}
