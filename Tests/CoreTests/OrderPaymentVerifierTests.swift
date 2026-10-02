import XCTest
@testable import QuestifyCore

@MainActor final class OrderPaymentVerifierTests: XCTestCase {
    func testServerPaymentFactCompletesReadback() async throws {
        let scope = UUID()
        let paid = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in paid })
        let result = await verifier.verify(registrationID: 9701)
        XCTAssertEqual(result, .observed(.paid, detail: paid))
    }
    func testMissingPaymentFactDoesNotBecomePaid() async throws {
        let scope = UUID()
        let accepted = try JSONDecoder().decode(OrderLifecycleDetail.self, from: Data(#"{"id":9701,"registrationStatus":2}"#.utf8))
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in accepted })
        let result = await verifier.verify(registrationID: 9701)
        XCTAssertEqual(result, .observed(.registrationAccepted, detail: accepted))
    }
    func testPendingUntilDeadlineBecomesUnknownNotFailed() async throws {
        let scope = UUID(), pending = try OrderLifecycleSyntheticFixtures.detail()
        let verifier = OrderPaymentVerifier(interval: 0.002, requestTimeout: 0.01, totalDeadline: 0.02, currentScope: { scope }, read: { _ in pending })
        let result = await verifier.verify(registrationID: 9701)
        XCTAssertEqual(result, .unknown)
    }
    func testScopeChangeMakesLatePaidResponseUnknown() async throws {
        var scope = UUID()
        let paid = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in scope = UUID(); return paid })
        let result = await verifier.verify(registrationID: 9701)
        XCTAssertEqual(result, .unknown)
    }
    func testUnauthorizedTerminatesWithoutRepeating() async {
        let scope = UUID(); var calls = 0
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in calls += 1; throw APIError.unauthorized })
        let result = await verifier.verify(registrationID: 9701)
        XCTAssertEqual(result, .accessDenied); XCTAssertEqual(calls, 1)
    }
    func testAbortNeverPublishesSyntheticPaidResponse() async throws {
        let scope = UUID()
        var pending: CheckedContinuation<OrderLifecycleDetail, Error>?
        let verifier = OrderPaymentVerifier(currentScope: { scope }, read: { _ in try await withCheckedThrowingContinuation { pending = $0 } })
        let task = Task { await verifier.verify(registrationID: 9701) }
        while pending == nil { await Task.yield() }
        verifier.abort()
        pending?.resume(returning: try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid))
        let result = await task.value
        XCTAssertEqual(result, .unknown)
    }
}

@MainActor extension OrderPaymentVerifierTests {
    func testIgnoringTransportCancellationCannotExtendDeadline() async throws {
        let scope = UUID()
        var pending: [CheckedContinuation<OrderLifecycleDetail, Error>] = []
        let verifier = OrderPaymentVerifier(interval: 0.001, requestTimeout: 0.01, totalDeadline: 0.015,
            currentScope: { scope }, read: { _ in try await withCheckedThrowingContinuation { pending.append($0) } })
        let result = await verifier.verify(registrationID: 9701)
        XCTAssertEqual(result, .unknown)
        let paid = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        for continuation in pending { continuation.resume(returning: paid) }
        XCTAssertEqual(result, .unknown)
    }
}
