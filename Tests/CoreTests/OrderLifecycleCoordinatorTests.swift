import XCTest
@testable import QuestifyCore

@MainActor private final class LifecycleTestReader: OrderLifecycleReading {
    var accountID: Int? = 100
    var scope = UUID()
    var isConfigured = true
    var isOfflineExample = true
    var value = try! OrderLifecycleSyntheticFixtures.detail()
    var reads = 0
    var failure: Error?
    var pending: [CheckedContinuation<OrderLifecycleDetail, Error>] = []
    var suspend = false
    func detail(id: Int) async throws -> OrderLifecycleDetail {
        reads += 1
        if let failure { throw failure }
        if suspend { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return value
    }
    func replace(accountID: Int?) { self.accountID = accountID; scope = UUID() }
}
@MainActor private final class LifecycleTestSimulator: OrderLifecycleFixtureSimulating {
    var calls = 0
    var pending: CheckedContinuation<OrderCancellationObservation, Error>?
    func simulate(_ review: OrderLifecycleReview) async throws -> OrderCancellationObservation {
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
}
@MainActor final class OrderLifecycleCoordinatorTests: XCTestCase {
    func testProductionConfirmationNeverCreatesAttempt() async throws {
        let reader = LifecycleTestReader()
        let c = OrderLifecycleCoordinator(reader: reader)
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        let review = try XCTUnwrap(c.review)
        await c.confirm(reviewID: review.id)
        XCTAssertFalse(c.canDispatch); XCTAssertFalse(c.canSimulate)
        XCTAssertEqual(c.issue, .dispatchDisabled); XCTAssertNil(c.attempt(orderID: 9701))
        XCTAssertEqual(c.detail?.registrationStatus, 1)
    }
    func testReviewUsesImmutableSnapshotAndExpires() async throws {
        let reader = LifecycleTestReader(); var now = Date(timeIntervalSince1970: 1000)
        let c = OrderLifecycleCoordinator(reader: reader, now: { now })
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        let review = try XCTUnwrap(c.review)
        reader.value = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        XCTAssertEqual(review.detail.registrationStatus, 1)
        now = now.addingTimeInterval(60)
        await c.confirm(reviewID: review.id)
        XCTAssertEqual(c.issue, .expiredReview); XCTAssertNil(c.attempt(orderID: 9701))
    }
    func testRefreshInvalidatesOpenReview() async throws {
        let reader = LifecycleTestReader()
        let c = OrderLifecycleCoordinator(reader: reader)
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        let id = try XCTUnwrap(c.review).id
        await c.load(id: 9701); await c.confirm(reviewID: id)
        XCTAssertNil(c.review); XCTAssertEqual(c.issue, .stale)
    }
    func testSameAccountNewEpochHidesDetailAndReview() async throws {
        let reader = LifecycleTestReader()
        let c = OrderLifecycleCoordinator(reader: reader)
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        reader.replace(accountID: 100)
        XCTAssertNil(c.detail); XCTAssertNil(c.review)
    }
    func testUnknownAttemptLocksOrderAcrossDismissalAndRelogin() async throws {
        let reader = LifecycleTestReader(), simulator = LifecycleTestSimulator()
        let c = OrderLifecycleCoordinator(reader: reader, fixtureSimulator: simulator)
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        let review = try XCTUnwrap(c.review)
        let task = Task { await c.confirm(reviewID: review.id) }
        while simulator.pending == nil { await Task.yield() }
        await c.confirm(reviewID: review.id)
        XCTAssertEqual(simulator.calls, 1)
        c.invalidateVisible(); reader.replace(accountID: nil)
        simulator.pending?.resume(throwing: URLError(.timedOut)); simulator.pending = nil
        await task.value
        reader.replace(accountID: 100)
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        XCTAssertEqual(c.issue, .alreadyAttempted); XCTAssertNil(c.review)
        XCTAssertEqual(c.attempt(orderID: 9701), .outcomeUnknown(localAttemptID: review.localAttemptID))
    }
    func testLateReceiptAfterSessionReplacementNeverAppearsForNewAccount() async throws {
        let reader = LifecycleTestReader(), simulator = LifecycleTestSimulator()
        let c = OrderLifecycleCoordinator(reader: reader, fixtureSimulator: simulator)
        await c.load(id: 9701); c.prepare(.cancel, orderID: 9701)
        let review = try XCTUnwrap(c.review)
        let task = Task { await c.confirm(reviewID: review.id) }
        while simulator.pending == nil { await Task.yield() }
        reader.replace(accountID: 101)
        let receipt = try JSONDecoder().decode(OrderCancellationObservation.self, from: Data(#"{"registrationId":9701,"cancellationStatus":"CANCELLED","cashRefundStatus":"UNCONFIRMED"}"#.utf8))
        simulator.pending?.resume(returning: receipt); simulator.pending = nil
        await task.value
        XCTAssertNil(c.attempt(orderID: 9701)); XCTAssertNil(c.detail)
        reader.replace(accountID: 100)
        XCTAssertEqual(c.attempt(orderID: 9701), .outcomeUnknown(localAttemptID: review.localAttemptID))
    }
    func testLaterRefreshWinsWhenTransportIgnoresCancellation() async throws {
        let reader = LifecycleTestReader(); reader.suspend = true
        let c = OrderLifecycleCoordinator(reader: reader)
        let old = Task { await c.load(id: 9701) }
        while reader.pending.count < 1 { await Task.yield() }
        let new = Task { await c.load(id: 9701) }
        while reader.pending.count < 2 { await Task.yield() }
        reader.pending[1].resume(returning: try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid))
        await new.value
        reader.pending[0].resume(returning: reader.value)
        await old.value
        XCTAssertEqual(c.detail?.paymentStatus, 2)
    }
    func testProductionReaderCannotAcquireFixtureSimulator() async {
        let reader = LifecycleTestReader(); reader.isOfflineExample = false
        let c = OrderLifecycleCoordinator(reader: reader, fixtureSimulator: LifecycleTestSimulator())
        XCTAssertFalse(c.canSimulate); XCTAssertFalse(c.canDispatch)
    }
    func testUnknownRefundabilityIsNotEligibility() async throws {
        let reader = LifecycleTestReader()
        reader.value = try JSONDecoder().decode(OrderLifecycleDetail.self, from: Data(#"{"id":9701,"registrationStatus":2,"paymentStatus":2,"verificationStatus":0}"#.utf8))
        let c = OrderLifecycleCoordinator(reader: reader)
        await c.load(id: 9701); c.prepare(.refund, orderID: 9701)
        XCTAssertNil(c.review); XCTAssertEqual(c.issue, .ineligible)
    }
    func testLogoutSuppressesDelayedRead() async throws {
        let reader = LifecycleTestReader(); reader.suspend = true
        let c = OrderLifecycleCoordinator(reader: reader)
        let task = Task { await c.load(id: 9701) }
        while reader.pending.isEmpty { await Task.yield() }
        reader.replace(accountID: nil)
        reader.pending[0].resume(returning: reader.value)
        await task.value
        XCTAssertNil(c.detail); XCTAssertNil(c.review)
    }
}

@MainActor extension OrderLifecycleCoordinatorTests {
    func testExplicitServerMessageIsNotTurnedIntoLocalizationKey() async {
        let reader = LifecycleTestReader()
        reader.failure = OrderLifecycleFailure.response(code: 500, message: "orderLifecycle.issue.failure")
        let c = OrderLifecycleCoordinator(reader: reader)
        await c.load(id: 9701)
        XCTAssertEqual(c.serverMessage, "orderLifecycle.issue.failure")
        reader.replace(accountID: nil)
        XCTAssertNil(c.serverMessage)
    }
}
