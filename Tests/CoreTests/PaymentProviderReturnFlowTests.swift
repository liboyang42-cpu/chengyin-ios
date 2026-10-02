import XCTest
@testable import QuestifyCore

@MainActor final class PaymentProviderReturnFlowTests: XCTestCase {
    private func detail(payment: Int?, registration: Int?) throws -> OrderLifecycleDetail {
        var body: [String: Any] = ["id": 701, "ownerType": 1, "ownerId": 77]
        if let payment { body["paymentStatus"] = payment }; if let registration { body["registrationStatus"] = registration }
        return try JSONDecoder().decode(OrderLifecycleDetail.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func testServerPaidAndFreeAcceptedRemainDistinct() async throws {
        let scope = UUID()
        for (payment, registration, expected) in [(2, 2, PaymentProviderReturnPhase.paid), (1, 2, .accepted), (3, 1, .failed)] {
            let value = try detail(payment: payment, registration: registration)
            let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in value })
            let flow = PaymentProviderReturnFlow(registrationID: 701, verifier: verifier, currentScope: { scope })
            await flow.reconcile(); XCTAssertEqual(flow.phase, expected); XCTAssertTrue(flow.canClose)
        }
    }
    func testPendingServerStatusEventuallyMeansUnknownNotSuccess() async throws {
        let scope = UUID(), value = try detail(payment: 1, registration: 1)
        let verifier = OrderPaymentVerifier(interval: 0.001, requestTimeout: 0.01, totalDeadline: 0.015, currentScope: { scope }, read: { _ in value })
        let flow = PaymentProviderReturnFlow(registrationID: 701, verifier: verifier, currentScope: { scope })
        await flow.reconcile(); XCTAssertEqual(flow.phase, .unknown); XCTAssertNil(flow.detail)
    }
    func testChangedScopeCannotPublishOldPaidResult() async throws {
        var scope = UUID(); let value = try detail(payment: 2, registration: 2)
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in scope = UUID(); return value })
        let flow = PaymentProviderReturnFlow(registrationID: 701, verifier: verifier, currentScope: { scope })
        await flow.reconcile(); XCTAssertEqual(flow.phase, .accessDenied); XCTAssertNil(flow.detail)
    }
    func testAccessDeniedNeverMeansFailureOrPaid() async {
        let scope = UUID()
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in throw APIError.unauthorized })
        let flow = PaymentProviderReturnFlow(registrationID: 701, verifier: verifier, currentScope: { scope })
        await flow.reconcile(); XCTAssertEqual(flow.phase, .accessDenied)
    }
}
