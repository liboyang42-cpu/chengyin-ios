import XCTest
@testable import QuestifyCore

final class SessionRestorationRetryTests: XCTestCase {
    func testNoAttemptWithoutFailedRestorationOffer() {
        var retry = SessionRestorationRetry()
        XCTAssertFalse(retry.isAvailable)
        XCTAssertNil(retry.begin(epoch: 1, namespace: "synthetic"))
    }
    func testOfferReservesOnlyOneAttemptAndStartsOnlyOnce() throws {
        var retry = SessionRestorationRetry(); retry.offer()
        let attempt = try XCTUnwrap(retry.begin(epoch: 1, namespace: "synthetic"))
        XCTAssertFalse(retry.isAvailable); XCTAssertTrue(retry.owns(attempt))
        XCTAssertNil(retry.begin(epoch: 1, namespace: "synthetic"))
        XCTAssertTrue(retry.start(attempt)); XCTAssertFalse(retry.start(attempt))
        retry.offer(); XCTAssertFalse(retry.isAvailable)
    }
    func testCancelReoffersButLateCompletionCannotChangeReplacement() throws {
        var retry = SessionRestorationRetry(); retry.offer()
        let old = try XCTUnwrap(retry.begin(epoch: 1, namespace: "synthetic"))
        XCTAssertTrue(retry.start(old)); retry.cancel()
        XCTAssertTrue(retry.isAvailable); XCTAssertFalse(retry.start(old))
        let fresh = try XCTUnwrap(retry.begin(epoch: 3, namespace: "synthetic"))
        retry.finish(old, retryable: true)
        XCTAssertTrue(retry.owns(fresh)); XCTAssertFalse(retry.isAvailable)
        XCTAssertTrue(retry.start(fresh))
    }
    func testFinishingTransientErrorRequiresANewExplicitAttempt() throws {
        var retry = SessionRestorationRetry(); retry.offer()
        let old = try XCTUnwrap(retry.begin(epoch: 1, namespace: "synthetic"))
        XCTAssertTrue(retry.start(old)); retry.finish(old, retryable: true)
        XCTAssertTrue(retry.isAvailable); XCTAssertNil(retry.pending)
        XCTAssertFalse(retry.start(old))
        let fresh = try XCTUnwrap(retry.begin(epoch: 1, namespace: "synthetic"))
        XCTAssertNotEqual(old, fresh); XCTAssertTrue(retry.start(fresh))
    }
    func testSuccessUnauthorizedOrLogoutDiscardsRetry() throws {
        var retry = SessionRestorationRetry(); retry.offer()
        let old = try XCTUnwrap(retry.begin(epoch: 1, namespace: "synthetic"))
        retry.finish(old, retryable: false)
        XCTAssertFalse(retry.isAvailable); XCTAssertNil(retry.pending)
        retry.offer()
        let fresh = try XCTUnwrap(retry.begin(epoch: 2, namespace: "synthetic"))
        retry.discard(); retry.finish(fresh, retryable: true); retry.cancel()
        XCTAssertFalse(retry.isAvailable); XCTAssertFalse(retry.start(fresh))
    }
    func testMissingNamespaceDoesNotConsumeAnOffer() throws {
        var retry = SessionRestorationRetry(); retry.offer()
        XCTAssertNil(retry.begin(epoch: 1, namespace: "")); XCTAssertTrue(retry.isAvailable)
        let attempt = try XCTUnwrap(retry.begin(epoch: 2, namespace: "synthetic"))
        XCTAssertEqual(attempt.epoch, 2); XCTAssertEqual(attempt.namespace, "synthetic")
    }
}
