import Foundation
import XCTest
@testable import Questify

@MainActor final class ProfileSavedMediaExpiryTests: XCTestCase {
    func testDelayIsCapturedOnceAndBoundedToOriginalDuration() {
        let start = Date(timeIntervalSince1970: 1_800_000_000), expires = start.addingTimeInterval(300)
        let delay = ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: expires, observedAt: start)
        let clock = ContinuousClock(), first = clock.now
        let deadline = first.advanced(by: .nanoseconds(delay))
        XCTAssertEqual(delay, 300_000_000_000)
        // No later wall-clock value is used to rebuild the captured deadline.
        let rolledBackWallClock = start.addingTimeInterval(-3600)
        XCTAssertGreaterThan(ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: expires, observedAt: rolledBackWallClock), delay)
        XCTAssertEqual(first.duration(to: deadline), .seconds(300))
    }
    func testExpiredAndNonfiniteInputNeverCreateLongTimer() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: start, observedAt: start), 0)
        XCTAssertEqual(ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: start.addingTimeInterval(-1), observedAt: start), 0)
        XCTAssertEqual(ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: Date(timeIntervalSince1970: .infinity), observedAt: start), 0)
    }
    func testDistantFutureCannotOverflowSignedDurationNanoseconds() {
        let delay = ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: .distantFuture, observedAt: Date())
        XCTAssertGreaterThan(delay, 0); XCTAssertLessThan(delay, Int64.max)
    }
    func testFractionalDeadlineNeverRoundsPastItsInitialWindow() {
        let start = Date(timeIntervalSince1970: 0)
        let delay = ProfileSavedMediaSourceSelection.expirationDelay(expiresAt: start.addingTimeInterval(0.125), observedAt: start)
        XCTAssertEqual(delay, 125_000_000)
    }
    private func approval(_ kind: ProfileCurrentMediaKind, duration: TimeInterval) throws -> ProfileSavedMediaReadApproval {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://expiry.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "saved-expiry", token: "synthetic-expiry", role: "player"))
        return try .init(context: context, viewerRevision: 3, kind: kind,
            approvedOrigins: ["https://images.example.test"], expiresAt: Date().addingTimeInterval(duration))
    }
    func testOldTimerCannotRevokeReplacementIssuanceOrOtherPurpose() async throws {
        let selector = ProfileSavedMediaSourceSelection(), old = try approval(.contactQR, duration: 0.5)
        try selector.replace(.contactQR, with: old)
        let newer = try approval(.contactQR, duration: 30), work = try approval(.caseImage, duration: 30)
        try selector.replace(.contactQR, with: newer); try selector.replace(.caseImage, with: work)
        defer { selector.revoke(.contactQR); selector.revoke(.caseImage) }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(old.revoked); XCTAssertFalse(newer.revoked); XCTAssertFalse(work.revoked)
        XCTAssertTrue(selector.approval(.contactQR, for: newer.context) === newer)
        XCTAssertTrue(selector.approval(.caseImage, for: work.context) === work)
    }
    func testOneDeadlineRevokesOnlyItsExactPurpose() async throws {
        let selector = ProfileSavedMediaSourceSelection(), qr = try approval(.contactQR, duration: 0.5), work = try approval(.caseImage, duration: 30)
        try selector.replace(.contactQR, with: qr); try selector.replace(.caseImage, with: work)
        defer { selector.revoke(.contactQR); selector.revoke(.caseImage) }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(qr.revoked); XCTAssertFalse(work.revoked)
        XCTAssertNil(selector.approval(.contactQR, for: qr.context)); XCTAssertTrue(selector.approval(.caseImage, for: work.context) === work)
    }
}
