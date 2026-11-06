import XCTest
import Observation
@testable import QuestifyCore

/// Synthetic leases only. Does not install a host selector or perform any read/write.
@MainActor final class OwnMediaReadExpiryTests: XCTestCase {
    private func context() throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://media.example/native")!, role: "player",
            session: try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-media", token: "synthetic-token"))
    }

    func testIdleExpiryPublishesRevocationWithoutAnotherRead() async throws {
        let context = try context()
        let lease = try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(0.05))
        defer { lease.revoke() }
        let changed = expectation(description: "Observable idle expiration")
        withObservationTracking { _ = lease.isRevoked } onChange: { changed.fulfill() }
        await fulfillment(of: [changed], timeout: 2)
        // Observation notifies before the setter finishes; resume on this actor after it completes.
        XCTAssertTrue(lease.isRevoked)
        XCTAssertFalse(lease.matches(context))
        XCTAssertFalse(lease.matches(context, now: .distantPast))
    }

    func testOldExpiryDoesNotRevokeReplacementLease() async throws {
        let context = try context()
        let old = try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(0.05))
        let replacement = try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(60))
        defer { old.revoke(); replacement.revoke() }
        let expired = expectation(description: "Old lease alone expires")
        withObservationTracking { _ = old.isRevoked } onChange: { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertTrue(old.isRevoked)
        XCTAssertNotEqual(old.revision, replacement.revision)
        XCTAssertFalse(replacement.isRevoked)
        XCTAssertTrue(replacement.matches(context))
    }

    func testExplicitRevocationStaysClosedAndDoesNotAffectAnotherLease() throws {
        let context = try context()
        let old = try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(60))
        let replacement = try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(60))
        defer { replacement.revoke() }
        old.revoke(); old.revoke()
        XCTAssertTrue(old.isRevoked)
        XCTAssertFalse(old.matches(context, now: .distantPast))
        XCTAssertTrue(replacement.matches(context))
    }

    func testTimerDoesNotRetainDiscardedLease() throws {
        let context = try context()
        var lease: OwnMediaReadApproval? = try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(60))
        weak var weakLease = lease
        XCTAssertNotNil(weakLease)
        lease = nil
        XCTAssertNil(weakLease)
    }

    func testExistingDeadlineAndMaximumDurationRemainClosed() throws {
        let context = try context()
        XCTAssertThrowsError(try OwnMediaReadApproval(context: context, expiresAt: .distantPast))
        XCTAssertThrowsError(try OwnMediaReadApproval(context: context, expiresAt: Date().addingTimeInterval(86_410)))
        let deadline = Date().addingTimeInterval(60)
        let lease = try OwnMediaReadApproval(context: context, expiresAt: deadline)
        defer { lease.revoke() }
        XCTAssertFalse(lease.matches(context, now: deadline))
        XCTAssertTrue(lease.matches(context, now: deadline.addingTimeInterval(-1)))
    }
}
