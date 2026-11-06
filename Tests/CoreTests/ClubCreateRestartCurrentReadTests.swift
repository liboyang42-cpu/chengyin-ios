import XCTest
@testable import QuestifyCore

@MainActor final class ClubCreateRestartCurrentReadTests: XCTestCase {
    func testRestoredPendingCanReadCurrentWithoutReceiptUnlockOrWrite() async throws {
        let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
        let original = access.pending
        await owner.readBack(target: .create, ownerID: UUID())
        XCTAssertEqual(access.reads, 1)
        XCTAssertEqual(owner.readback(target: .create), .received(access.current))
        guard case .outcomeUnknown = owner.state(target: .create) else { return XCTFail("Current is not an original receipt") }
        do {
            _ = try await owner.prepare(.create(ClubOperationsDraft()), target: .create,
                expectedIdentity: XCTUnwrap(access.identity), ownerID: UUID())
            XCTFail("Current read unlocked creation")
        } catch { XCTAssertEqual(error as? ClubOperationsBlock, .pending) }
        XCTAssertEqual(access.pending, original); XCTAssertEqual(access.writes, 0)
    }

    func testCurrentFailureAndWrongTargetAreUnavailableThenRetryIsReadOnly() async {
        for malformed in [false, true] {
            let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
            let original = access.pending
            access.response = malformed ? .success(.init(target: .club(82))) : .failure(APIError.malformedResponse)
            await owner.readBack(target: .create, ownerID: UUID())
            XCTAssertEqual(owner.readback(target: .create), .unavailable)
            access.response = .success(access.current)
            await owner.readBack(target: .create, ownerID: UUID())
            XCTAssertEqual(owner.readback(target: .create), .received(access.current))
            guard case .outcomeUnknown = owner.state(target: .create) else { return XCTFail() }
            XCTAssertEqual(access.pending, original); XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.writes, 0)
        }
    }

    func testNoPendingDisabledAndOtherTargetNeverDispatch() async {
        let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
        access.isConfigured = false
        await owner.readBack(target: .create, ownerID: UUID())
        access.isConfigured = true
        await owner.readBack(target: .club(82), ownerID: UUID())
        access.pending = nil
        await owner.readBack(target: .create, ownerID: UUID())
        XCTAssertEqual(access.reads, 0); XCTAssertEqual(access.writes, 0)
        XCTAssertEqual(owner.readback(target: .create), .idle)
    }

    func testDuplicateTapCoalescesAndOldOwnerCannotEraseReplacementRead() async throws {
        for lateFailure in [false, true] {
            let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
            access.hold = true
            let firstOwner = UUID(), secondOwner = UUID(), identity = try XCTUnwrap(access.identity)
            let firstStarted = expectation(description: "first started")
            access.onRead = { firstStarted.fulfill() }
            let first = Task { await owner.readBack(target: .create, ownerID: firstOwner) }
            await fulfillment(of: [firstStarted], timeout: 2)
            await owner.readBack(target: .create, ownerID: firstOwner)
            XCTAssertEqual(access.reads, 1)
            owner.leaveScreen(target: .create, expectedIdentity: identity, ownerID: firstOwner)
            XCTAssertEqual(owner.readback(target: .create), .idle)
            let secondStarted = expectation(description: "second started")
            access.onRead = { secondStarted.fulfill() }
            let second = Task { await owner.readBack(target: .create, ownerID: secondOwner) }
            await fulfillment(of: [secondStarted], timeout: 2)
            owner.leaveScreen(target: .create, expectedIdentity: identity, ownerID: firstOwner)
            access.finish(1, result: lateFailure ? .failure(APIError.malformedResponse) : .success(access.current))
            await first.value
            XCTAssertEqual(owner.readback(target: .create), .loading)
            access.finish(2, result: .success(access.current)); await second.value
            XCTAssertEqual(owner.readback(target: .create), .received(access.current))
            XCTAssertEqual(access.writes, 0)
        }
    }

    func testSwitchAccountAndReturnWithNewEpochRejectsOldResponse() async throws {
        let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
        access.hold = true
        let started = expectation(description: "read started"); access.onRead = { started.fulfill() }
        let task = Task { await owner.readBack(target: .create, ownerID: UUID()) }
        await fulfillment(of: [started], timeout: 2)
        access.identity = .init(accountID: 702, epoch: 2); owner.synchronizeSession()
        XCTAssertEqual(owner.state(target: .create), .idle)
        XCTAssertEqual(owner.readback(target: .create), .idle)
        access.identity = .init(accountID: 701, epoch: 3)
        access.finish(1, result: .success(access.current)); await task.value
        XCTAssertEqual(owner.readback(target: .create), .idle)
        access.hold = false; access.onRead = nil
        await owner.readBack(target: .create, ownerID: UUID())
        XCTAssertEqual(owner.readback(target: .create), .received(access.current))
        guard case .outcomeUnknown = owner.state(target: .create) else { return XCTFail() }
        XCTAssertEqual(access.writes, 0)
    }

    func testRevocationCancellationAndRemovedPendingRejectLateRead() async {
        for boundary in 0..<3 {
            let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
            access.hold = true
            let started = expectation(description: "read started"); access.onRead = { started.fulfill() }
            let task = Task { await owner.readBack(target: .create, ownerID: UUID()) }
            await fulfillment(of: [started], timeout: 2)
            if boundary == 0 { access.isConfigured = false }
            if boundary == 1 { task.cancel() }
            if boundary == 2 { access.pending = nil }
            access.finish(1, result: .success(access.current)); await task.value
            XCTAssertEqual(owner.readback(target: .create), .idle)
            XCTAssertEqual(access.writes, 0)
        }
    }

    func testRevokedPublishedCurrentCannotReappearAfterObservedRegrant() async {
        let access = RestartCreateReadAccess(), owner = ClubOperationsCoordinator(access: access)
        await owner.readBack(target: .create, ownerID: UUID())
        XCTAssertEqual(owner.readback(target: .create), .received(access.current))
        access.isConfigured = false
        XCTAssertEqual(owner.readback(target: .create), .idle)
        access.isConfigured = true
        XCTAssertEqual(owner.readback(target: .create), .idle)
        guard case .outcomeUnknown = owner.state(target: .create) else { return XCTFail() }
        XCTAssertEqual(access.reads, 1); XCTAssertEqual(access.writes, 0)
    }
}

@MainActor private final class RestartCreateReadAccess: ClubOperationsAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    let writeAvailability: ClubOperationsWriteAvailability = .syntheticOnly
    var pending: OperationPendingRecord? = .init(ownerKey: "synthetic:701", targetKey: "club:create")
    let current = ClubOperationsSnapshot(target: .create, accountRole: "club", ownedClubIDs: [81, 82])
    var response: Result<ClubOperationsSnapshot, Error>?
    var reads = 0, writes = 0
    var hold = false
    var onRead: (() -> Void)?
    private var continuations: [Int: CheckedContinuation<ClubOperationsSnapshot, Error>] = [:]
    func hasPending(target: ClubOperationsTarget) -> Bool {
        identity?.accountID == 701 && target == .create && pending != nil
    }
    func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
        reads += 1; let number = reads
        if hold {
            return try await withCheckedThrowingContinuation { continuation in
                continuations[number] = continuation; onRead?()
            }
        }
        onRead?()
        return try (response ?? .success(current)).get()
    }
    func finish(_ number: Int, result: Result<ClubOperationsSnapshot, Error>) {
        let continuation = continuations.removeValue(forKey: number)
        continuation?.resume(with: result)
    }
    func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget,
                 expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
        writes += 1; throw APIError.invalidRequest
    }
}
