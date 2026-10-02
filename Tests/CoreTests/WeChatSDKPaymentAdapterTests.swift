import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class WeChatSDKPaymentAdapterTests: XCTestCase {
    private func configuration() throws -> WeChatSDKPaymentConfiguration {
        try .init(sdk: .init(appID: "wxSynthetic", universalLink: URL(string: "https://example.com/payment/")!,
            urlCallbacks: [.init(host: "pay", path: "/reply")], universalLinkCallbacks: [.init(host: "example.com", path: "/payment/reply")]), merchantIDs: ["12345"])
    }
    private func context(epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.com/api/")!, role: "player",
              session: try .init(accountID: 7, epoch: epoch, namespace: "fixture", token: "synthetic"))
    }
    private var parameters: [String: String] { ["appId":"wxSynthetic", "partnerId":"12345", "prepayId":"synthetic-prepay", "nonceStr":"synthetic-nonce", "timeStamp":"123", "packageValue":"Sign=WXPay", "sign":"synthetic-signature"] }
    func testExactProviderRequestMapsVerifiedFields() throws {
        let value = try WeChatSDKPaymentRequest(parameters: parameters, configuration: configuration())
        XCTAssertEqual(value.partnerID, "12345"); XCTAssertEqual(value.prepayID, "synthetic-prepay")
        XCTAssertEqual(value.timestamp, 123); XCTAssertEqual(value.package, "Sign=WXPay")
    }
    func testAppMerchantTimestampAndMissingFieldsFailClosed() throws {
        for (key, value) in [("appId","other"),("partnerId","999"),("timeStamp","4294967296"),("timeStamp","0"),("sign",""),("nonceStr","bad nonce")] {
            var fields = parameters; fields[key] = value
            XCTAssertThrowsError(try WeChatSDKPaymentRequest(parameters: fields, configuration: configuration()))
        }
    }
    func testDefaultGateNeverRegistersOrSends() async throws {
        let driver = Driver(), scope = try context()
        let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), context: { scope })
        let outcome = await adapter.pay(registrationID: 701, parameters: parameters)
        XCTAssertEqual(outcome, .unknown); XCTAssertEqual(driver.registrations, 0); XCTAssertTrue(driver.requests.isEmpty)
    }
    func testProviderZeroOnlyReturnsToServerVerification() async throws {
        let driver = Driver(), scope = try context(); driver.immediate = 0
        let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), allowed: { true }, context: { scope })
        let result = await adapter.pay(registrationID: 701, parameters: parameters)
        XCTAssertEqual(result, .returned); XCTAssertNil(adapter.pendingRegistrationID); XCTAssertEqual(driver.requests.count, 1)
        // There is intentionally no paid/success receipt in this provider enum.
    }
    func testProviderCancelAndErrorsAreDistinctReturns() async throws {
        for (code, expected) in [(-2, TopicSelfPlayProviderReturn.cancelled), (-1, .failed), (-3, .failed), (-5, .failed)] {
            let driver = Driver(), scope = try context(); driver.immediate = Int32(code)
            let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), allowed: { true }, context: { scope })
            let result = await adapter.pay(registrationID: 701, parameters: parameters); XCTAssertEqual(result, expected)
        }
    }
    func testOnePendingOrderAndExactCallbackRoutes() async throws {
        let driver = Driver(), scope = try context()
        let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), allowed: { true }, context: { scope })
        let task = Task { await adapter.pay(registrationID: 701, parameters: self.parameters) }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(adapter.pendingRegistrationID, 701)
        XCTAssertTrue(adapter.acceptsURL(URL(string: "wxSynthetic://pay/reply?opaque=synthetic")!))
        XCTAssertFalse(adapter.acceptsURL(URL(string: "wxSynthetic://auth/reply")!))
        XCTAssertFalse(adapter.acceptsUniversalLink(URL(string: "https://example.com/other/reply")!))
        let second = await adapter.pay(registrationID: 702, parameters: parameters)
        XCTAssertEqual(second, .unknown); XCTAssertEqual(driver.requests.count, 1)
        driver.responses.first?(0); let first = await task.value; XCTAssertEqual(first, .returned)
        XCTAssertFalse(adapter.acceptsURL(URL(string: "wxSynthetic://pay/reply")!))
    }
    func testChangedContextCannotCompleteOldProviderWait() async throws {
        let driver = Driver(); var scope = try context()
        let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), allowed: { true }, context: { scope })
        let task = Task { await adapter.pay(registrationID: 701, parameters: self.parameters) }
        for _ in 0..<30 { await Task.yield() }
        scope = try context(epoch: 2); driver.responses.first?(0)
        let result = await task.value; XCTAssertEqual(result, .unknown); XCTAssertNil(adapter.pendingRegistrationID)
    }
    func testDuplicateOldCallbackCannotFinishNewLocalAttempt() async throws {
        let driver = Driver(), scope = try context(); driver.immediate = 0
        let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), allowed: { true }, context: { scope })
        _ = await adapter.pay(registrationID: 701, parameters: parameters)
        driver.immediate = nil
        let task = Task { await adapter.pay(registrationID: 702, parameters: self.parameters) }
        for _ in 0..<30 { await Task.yield() }
        driver.responses[0](0); XCTAssertEqual(adapter.pendingRegistrationID, 702)
        adapter.cancelPending(); let result = await task.value; XCTAssertEqual(result, .unknown)
    }
    func testTimeoutReturnsUnknownAndDetaches() async throws {
        let driver = Driver(), scope = try context()
        let adapter = WeChatSDKPaymentAdapter(driver: driver, configuration: try configuration(), allowed: { true }, context: { scope }, timeoutNanoseconds: 1_000_000)
        let outcome = await adapter.pay(registrationID: 701, parameters: parameters)
        XCTAssertEqual(outcome, .unknown); XCTAssertNil(adapter.pendingRegistrationID); XCTAssertEqual(driver.detaches, 1)
    }
    private final class Driver: WeChatSDKPaymentDriving {
        var isLinked = true; var isInstalledAndSupported = true
        var registrations = 0; var detaches = 0; var immediate: Int32?
        var requests: [WeChatSDKPaymentRequest] = []; var responses: [(Int32) -> Void] = []
        func register(_ configuration: WeChatSDKConfiguration) -> Bool { registrations += 1; return true }
        func send(_ request: WeChatSDKPaymentRequest, launched: @escaping (Bool) -> Void, response: @escaping (Int32) -> Void) {
            requests.append(request); responses.append(response); launched(true); if let immediate { response(immediate) }
        }
        func detach() { detaches += 1 }
    }
}
