import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor LifecycleDormantTransport: HTTPTransport {
    var calls = 0
    let body: String
    init(_ body: String = #"{"code":200,"data":{}}"#) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; return (Data(body.utf8), 200) }
}
final class OrderLifecycleDormantAdapterTests: XCTestCase {
    private let baseURL = URL(string: "https://example.com/test/")!
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testDefaultAdapterRejectsEveryCredentialOrVerificationDispatch() async throws {
        let t = LifecycleDormantTransport(), config = try APIConfiguration(baseURL: baseURL)
        let adapter = OrderLifecycleDormantAdapter(configuration: config, transport: t)
        do { _ = try await adapter.issueTicket(registrationID: 7, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? OrderLifecycleFailure, .notDispatched) }
        do { _ = try await adapter.issueCoupon(historyID: 7, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? OrderLifecycleFailure, .notDispatched) }
        do { _ = try await adapter.paymentParameters(registrationID: 7, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? OrderLifecycleFailure, .notDispatched) }
        do { _ = try await adapter.verifyDynamicTicket(code: "not-a-real-code", token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? OrderLifecycleFailure, .notDispatched) }
        do { _ = try await adapter.verifyCoupon(code: "not-a-real-code", token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? OrderLifecycleFailure, .notDispatched) }
        do { _ = try await adapter.verifyLegacy(type: "activity", code: "not-a-real-code", token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? OrderLifecycleFailure, .notDispatched) }
        let calls = await t.calls; XCTAssertEqual(calls, 0)
        XCTAssertFalse(adapter.isProductionDispatchEnabled)
    }
    func testExactIssueAndPaymentForms() throws {
        let ticket = try OrderLifecycleRequestContract.issueTicket(registrationID: 7, baseURL: baseURL, token: "synthetic")
        XCTAssertEqual(ticket.url?.path, "/test/api/verify/dyncode/issue")
        XCTAssertTrue(body(ticket).contains("name=\"registrationId\"\r\n\r\n7"))
        let coupon = try OrderLifecycleRequestContract.issueCoupon(historyID: 8, baseURL: baseURL, token: "synthetic")
        XCTAssertEqual(coupon.url?.path, "/test/api/coupon/qr-token")
        XCTAssertTrue(body(coupon).contains("name=\"couponHistoryId\"\r\n\r\n8"))
        let pay = try OrderLifecycleRequestContract.paymentParameters(registrationID: 7, baseURL: baseURL, token: "synthetic")
        XCTAssertEqual(pay.url?.path, "/test/api/registration/pay/app")
        XCTAssertTrue(body(pay).contains("name=\"id\"\r\n\r\n7"))
    }
    func testDynamicRequestPreservesCapturedValueAndOmitsClientType() throws {
        let request = try OrderLifecycleRequestContract.verifyDynamicTicket(code: " sample opaque fixture ", baseURL: baseURL, token: "synthetic")
        XCTAssertTrue(body(request).contains("\r\n\r\n sample opaque fixture \r\n"))
        XCTAssertFalse(body(request).contains("name=\"type\""))
        XCTAssertEqual(request.url?.path, "/test/api/registration/scan_dynamic_code")
    }
    func testChoiceRequestRequiresCandidateAndDedicatedStationKey() throws {
        let receipt = try JSONDecoder().decode(OrderVerificationReceipt.self, from: Data(OrderLifecycleSyntheticFixtures.stationChoice.utf8))
        XCTAssertThrowsError(try OrderLifecycleRequestContract.verifyChoice(receipt: receipt, choiceID: 9999, code: "fixture", baseURL: baseURL, token: "synthetic"))
        let request = try OrderLifecycleRequestContract.verifyChoice(receipt: receipt, choiceID: 9731, code: "fixture", baseURL: baseURL, token: "synthetic")
        XCTAssertEqual(request.url?.path, "/test/api/registration/scan_qr_code_station")
        XCTAssertTrue(body(request).contains("name=\"registrationMerchantId\""))
        XCTAssertFalse(body(request).contains("name=\"stationId\""))
    }
    func testChoiceBearingErrorEnvelopeSurvivesFakeAdapter() async throws {
        let t = LifecycleDormantTransport(OrderLifecycleSyntheticFixtures.chapterChoice)
        let adapter = try OrderLifecycleDormantAdapter(fixtureConfiguration: APIConfiguration(baseURL: baseURL), fixtureTransport: t)
        let result = try await adapter.verifyLegacy(type: "activity", code: "fixture", token: "synthetic")
        XCTAssertEqual(result.outcome, .needsChoice); XCTAssertEqual(result.choices.count, 2)
    }
    func testIncompleteProviderParametersNeverGetDefaults() throws {
        let result = try JSONDecoder().decode(OrderPaymentParameterMetadata.self, from: Data(#"{"payParams":{"appId":"sample","timeStamp":"1"}}"#.utf8))
        XCTAssertFalse(result.hasCompleteFields)
    }
    @MainActor func testCancellationRequestHasNoFabricatedServerIdempotencyKey() throws {
        let detail = try OrderLifecycleSyntheticFixtures.detail()
        let review = OrderLifecycleReview(id: UUID(), accountID: 100, scope: UUID(), detail: detail, action: .cancel, expiresAt: Date().addingTimeInterval(10), localAttemptID: UUID())
        let request = try OrderLifecycleRequestContract.cancellation(review: review, baseURL: baseURL, token: "synthetic")
        XCTAssertEqual(request.url?.path, "/test/api/registration/cancel")
        XCTAssertFalse(body(request).contains("requestId")); XCTAssertFalse(body(request).contains("localAttemptID"))
    }
}

extension OrderLifecycleDormantAdapterTests {
    func testRefundRequestCannotFallBackToUnpaidCancellation() throws {
        let detail = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        let review = OrderLifecycleReview(id: UUID(), accountID: 100, scope: UUID(), detail: detail, action: .refund, expiresAt: Date().addingTimeInterval(10), localAttemptID: UUID())
        let request = try OrderLifecycleRequestContract.cancellation(review: review, baseURL: baseURL, token: "synthetic")
        XCTAssertEqual(request.url?.path, "/test/api/registration/cancel-refund")
        let wrong = OrderLifecycleReview(id: UUID(), accountID: 100, scope: UUID(), detail: detail, action: .cancel, expiresAt: Date().addingTimeInterval(10), localAttemptID: UUID())
        XCTAssertThrowsError(try OrderLifecycleRequestContract.cancellation(review: wrong, baseURL: baseURL, token: "synthetic"))
    }
}

extension OrderLifecycleDormantAdapterTests {
    func testNumericProviderTimestampIsAcceptedWithoutFabricatingSignature() throws {
        let raw = #"{"payParams":{"appId":"sample","partnerId":"sample","prepayId":"sample","packageValue":"sample","nonceStr":"sample","timeStamp":1,"sign":"synthetic-not-valid"}}"#
        let value = try JSONDecoder().decode(OrderPaymentParameterMetadata.self, from: Data(raw.utf8))
        XCTAssertTrue(value.hasCompleteFields)
    }
}
