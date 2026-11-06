import XCTest
@testable import QuestifyCore

@MainActor private final class PresentationLocks: OfficialActionLockStore {
    var values = Set<String>()
    func contains(_ key: String) throws -> Bool { values.contains(key) }
    func insert(_ key: String) throws { values.insert(key) }
    func remove(_ key: String) throws { values.remove(key) }
}
@MainActor private final class PresentationAccess: OfficialActionAccess {
    var identity: OfficialActionIdentity? = .init(accountID: 71, epoch: UUID(), namespace: "synthetic")
    var enabled = true
    var reads = 0, writes = 0
    var pauseRead = false, pauseWrite = false
    var onRead: (() -> Void)?, onWrite: (() -> Void)?
    var readContinuation: CheckedContinuation<OfficialActionSnapshot, Error>?
    var writeContinuation: CheckedContinuation<OfficialActionReceipt, Error>?
    func facts() throws -> OfficialActionSnapshot {
        let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(#"{"id":8,"title":"Synthetic","status":3,"signed":false}"#.utf8))
        return .init(identity: try XCTUnwrap(identity), event: event)
    }
    func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot {
        reads += 1
        if pauseRead { return try await withCheckedThrowingContinuation { readContinuation = $0; onRead?() } }
        onRead?(); return try facts()
    }
    func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt {
        writes += 1
        if pauseWrite { return try await withCheckedThrowingContinuation { writeContinuation = $0; onWrite?() } }
        onWrite?(); return .acknowledged
    }
}
@MainActor final class OfficialActionPresentationOwnershipTests: XCTestCase {
    func testReplacementReviewSurvivesOldCancellation() async throws {
        let access = PresentationAccess(), locks = PresentationLocks()
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let old = coordinator.beginPresentation()
        _ = try await coordinator.prepare(.signup(8), presentation: old)
        let current = coordinator.beginPresentation()
        let review = try await coordinator.prepare(.signup(8), presentation: current)
        coordinator.cancelReview(presentation: old)
        XCTAssertTrue(coordinator.ownsPresentation(current))
        let receipt = try await coordinator.confirm(review, presentation: current)
        XCTAssertEqual(receipt, .acknowledged); XCTAssertEqual(access.writes, 1)
    }
    func testRetiredPresentationCannotResumeAfterReplacement() {
        let coordinator = OfficialActionCoordinator(access: PresentationAccess(), locks: PresentationLocks())
        let old = coordinator.beginPresentation(); coordinator.cancelReview(presentation: old)
        let current = coordinator.beginPresentation()
        XCTAssertFalse(coordinator.resumePresentation(old)); XCTAssertTrue(coordinator.ownsPresentation(current))
    }
    func testPausedPresentationCanResumeButOldReviewRemainsInvalid() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let lease = coordinator.beginPresentation(), review = try await coordinator.prepare(.signup(8), presentation: lease)
        coordinator.cancelReview(presentation: lease)
        XCTAssertFalse(coordinator.ownsPresentation(lease)); XCTAssertTrue(coordinator.resumePresentation(lease))
        do { _ = try await coordinator.confirm(review, presentation: lease); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        _ = try await coordinator.prepare(.signup(8), presentation: lease)
        XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.writes, 0)
    }
    func testRetiredQueuedPrepareMakesNoRead() async {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let lease = coordinator.beginPresentation(); coordinator.cancelReview(presentation: lease)
        do { _ = try await coordinator.prepare(.signup(8), presentation: lease); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        XCTAssertEqual(access.reads, 0); XCTAssertEqual(access.writes, 0)
    }
    func testForeignPresentationCannotReadOrCancelOwner() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let other = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let owner = coordinator.beginPresentation(), foreign = other.beginPresentation()
        coordinator.cancelReview(presentation: foreign)
        XCTAssertTrue(coordinator.ownsPresentation(owner))
        do { _ = try await coordinator.prepare(.signup(8), presentation: foreign); XCTFail() } catch {}
        XCTAssertEqual(access.reads, 0)
    }
    func testChangedIdentityCannotResumeOrConfirmOriginalReview() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let lease = coordinator.beginPresentation(), review = try await coordinator.prepare(.signup(8), presentation: lease)
        access.identity = .init(accountID: 71, epoch: UUID(), namespace: "synthetic")
        XCTAssertFalse(coordinator.ownsPresentation(lease)); XCTAssertFalse(coordinator.resumePresentation(lease))
        do { _ = try await coordinator.confirm(review, presentation: lease); XCTFail() } catch {}
        XCTAssertEqual(access.writes, 0); XCTAssertEqual(access.reads, 1)
    }
    func testCancelledTaskRejectsScopedReadBeforeDispatch() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let lease = coordinator.beginPresentation()
        let queued = Task { try await coordinator.prepare(.signup(8), presentation: lease) }
        queued.cancel()
        do { _ = try await queued.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(access.reads, 0)
    }
    func testLegacyPrepareRetiresOnlyAcceptedPresentationOwner() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let old = coordinator.beginPresentation()
        let review = try await coordinator.prepare(.signup(8))
        coordinator.cancelReview(presentation: old)
        XCTAssertFalse(coordinator.resumePresentation(old))
        _ = try await coordinator.confirm(review)
        XCTAssertEqual(access.writes, 1)
    }
    func testCancelledPrepareDropsLateSnapshotAndAllowsFreshOwner() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let old = coordinator.beginPresentation(); access.pauseRead = true
        let started = expectation(description: "old read started"); access.onRead = { started.fulfill() }
        let task = Task { try await coordinator.prepare(.signup(8), presentation: old) }
        await fulfillment(of: [started], timeout: 1)
        coordinator.cancelReview(presentation: old)
        let current = coordinator.beginPresentation()
        access.readContinuation?.resume(returning: try access.facts()); access.readContinuation = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        access.pauseRead = false; access.onRead = nil
        _ = try await coordinator.prepare(.signup(8), presentation: current)
        XCTAssertTrue(coordinator.ownsPresentation(current)); XCTAssertEqual(access.writes, 0)
    }
    func testRetiringDuringConfirmationReadMakesZeroWritesAndNoLock() async throws {
        let access = PresentationAccess(), locks = PresentationLocks(), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let lease = coordinator.beginPresentation(), review = try await coordinator.prepare(.signup(8), presentation: lease)
        access.pauseRead = true; let started = expectation(description: "confirmation read")
        access.onRead = { started.fulfill() }
        let task = Task { try await coordinator.confirm(review, presentation: lease) }
        await fulfillment(of: [started], timeout: 1)
        coordinator.cancelReview(presentation: lease)
        access.readContinuation?.resume(returning: try access.facts()); access.readContinuation = nil
        do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertEqual(access.writes, 0); XCTAssertTrue(locks.values.isEmpty)
    }
    func testRetiringAfterDispatchPreservesUnknownAndDurableLock() async throws {
        let access = PresentationAccess(), locks = PresentationLocks(), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let lease = coordinator.beginPresentation(), review = try await coordinator.prepare(.signup(8), presentation: lease)
        access.pauseWrite = true; let started = expectation(description: "original write dispatched")
        access.onWrite = { started.fulfill() }
        let task = Task { try await coordinator.confirm(review, presentation: lease) }
        await fulfillment(of: [started], timeout: 1)
        coordinator.cancelReview(presentation: lease)
        access.writeContinuation?.resume(returning: .acknowledged); access.writeContinuation = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .unknown) }
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(locks.values.count, 1)
        let next = coordinator.beginPresentation()
        do { _ = try await coordinator.prepare(.signup(8), presentation: next); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
        XCTAssertEqual(access.writes, 1)
    }
    func testDisabledAccessStillCannotConfirmScopedReview() async throws {
        let access = PresentationAccess(), coordinator = OfficialActionCoordinator(access: access, locks: PresentationLocks())
        let lease = coordinator.beginPresentation(), review = try await coordinator.prepare(.signup(8), presentation: lease)
        access.enabled = false
        do { _ = try await coordinator.confirm(review, presentation: lease); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialActionFailure, .disabled) }
        XCTAssertEqual(access.writes, 0)
    }
}
