import XCTest
@testable import Questify

@MainActor final class ClubCreateCurrentRecordPresentationTests: XCTestCase {
    private func count(_ access: CurrentClubRecordTestAccess, _ coordinator: ClubOperationsCoordinator,
        loading: Bool = false, active: Bool = true) -> Int? {
        ClubOperationsWorkspaceView.unknownCreateCurrentCount(target: .create, state: .outcomeUnknown(.transport),
            identity: access.identity, access: access, coordinator: coordinator, loading: loading, active: active)
    }
    func testCurrentRecordsRequireCompletedReadAndNeverResolveOriginal() async {
        let access = CurrentClubRecordTestAccess(), coordinator = ClubOperationsCoordinator(access: access)
        let pending = access.pending
        XCTAssertNil(count(access, coordinator))
        await coordinator.readBack(target: .create, ownerID: UUID())
        XCTAssertEqual(count(access, coordinator), 2)
        XCTAssertNil(count(access, coordinator, loading: true))
        XCTAssertNil(count(access, coordinator, active: false))
        XCTAssertTrue(coordinator.state(target: .create).locksForm)
        XCTAssertEqual(access.pending, pending); XCTAssertEqual(access.writes, 0)
        access.isConfigured = false
        XCTAssertNil(count(access, coordinator))
        access.isConfigured = true
        XCTAssertNil(count(access, coordinator))
    }
    func testEmptyIsZeroRecordsButMalformedIDsAreNotPresented() async {
        for ids in [[], [0], [81, 81]] {
            let access = CurrentClubRecordTestAccess(), coordinator = ClubOperationsCoordinator(access: access)
            access.response = .success(.init(target: .create, accountRole: "club", ownedClubIDs: ids))
            await coordinator.readBack(target: .create, ownerID: UUID())
            if ids.isEmpty { XCTAssertEqual(count(access, coordinator), 0) }
            else { XCTAssertNil(count(access, coordinator)) }
            XCTAssertTrue(coordinator.state(target: .create).locksForm); XCTAssertEqual(access.writes, 0)
        }
    }
}

@MainActor private final class CurrentClubRecordTestAccess: ClubOperationsAccess {
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
