import XCTest
@testable import QuestifyCore

@MainActor final class PrivateHomeStorageRaceTests: XCTestCase {
    private final class SuspendedJournal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var pauseRead = false, pauseSave = false, pauseClear = false, failRead = false
        var reads = 0, clears = 0
        var waiting: CheckedContinuation<Void, Never>?
        init(_ owner: PlayExperienceSession) { scope = PrivateHomeJournalScope(owner: owner) }
        func read() async throws -> PrivateHomeMutation? {
            reads += 1
            if pauseRead { await withCheckedContinuation { waiting = $0 } }
            if failRead { throw PrivateHomeIssue.storageUnavailable }; return value
        }
        func save(_ mutation: PrivateHomeMutation) async throws {
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }; value = mutation
            if pauseSave { await withCheckedContinuation { waiting = $0 } }
        }
        func clear(matching mutation: PrivateHomeMutation) async throws {
            clears += 1
            guard value == mutation else { throw PrivateHomeIssue.storageUnavailable }; value = nil
            if pauseClear { await withCheckedContinuation { waiting = $0 } }
        }
        func resume() { let continuation = waiting; waiting = nil; continuation?.resume() }
    }
    private final class Service: PrivateHomeServing {
        var reads = 0, writes = 0
        var afterSend: (() -> Void)?
        func load() async throws -> PrivateHomeSnapshot {
            reads += 1
            return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":0,\"status\":\"DELETED\"}".utf8))
        }
        func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
            writes += 1; afterSend?()
            return try JSONDecoder().decode(PrivateHomeReceipt.self, from: Data("{\"requestId\":\"\(mutation.requestId)\",\"decision\":\"SAVED\",\"version\":1}".utf8))
        }
    }
    private func owner() throws -> PlayExperienceSession { try PlayExperienceSession(accountID: 12, epoch: 1, namespace: "synthetic", token: "fixture-token") }
    private func prepare(_ model: PrivateHomeCoordinator) throws { model.prepareSet(label: "Synthetic", point: try PrivateHomePoint(latitude: 12, longitude: 45)) }
    func testLogoutDuringDurableInsertLeavesLockAndNeverDispatchesHTTP() async throws {
        let owner = try owner(), journal = SuspendedJournal(owner), service = Service()
        var current: PlayExperienceSession? = owner
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { current })
        await model.load(); try prepare(model); journal.pauseSave = true
        let task = Task { await model.confirm() }
        while journal.waiting == nil { await Task.yield() }
        await model.confirm(); XCTAssertEqual(service.writes, 0) // repeat tap while insert awaits
        current = nil; model.invalidate(); journal.resume(); await task.value
        XCTAssertEqual(service.writes, 0); XCTAssertNotNil(journal.value); XCTAssertNil(model.home); XCTAssertEqual(model.phase, .invalidated)
    }
    func testLogoutDuringClearDoesNotRestoreOldUIOrTriggerReadback() async throws {
        let owner = try owner(), journal = SuspendedJournal(owner), service = Service()
        var current: PlayExperienceSession? = owner
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { current })
        await model.load(); try prepare(model); journal.pauseClear = true
        let task = Task { await model.confirm() }
        while journal.waiting == nil { await Task.yield() }
        current = nil; model.invalidate(); journal.resume(); await task.value
        XCTAssertEqual(service.writes, 1); XCTAssertEqual(service.reads, 1)
        XCTAssertNil(model.home); XCTAssertNil(model.decision); XCTAssertEqual(model.phase, .invalidated)
    }
    func testUnavailableStoragePreventsEvenOwnerReadAndAnyMutation() async throws {
        let owner = try owner(), journal = SuspendedJournal(owner), service = Service()
        journal.failRead = true
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
        await model.load(); try prepare(model); await model.confirm()
        XCTAssertEqual(service.reads, 0); XCTAssertEqual(service.writes, 0); XCTAssertFalse(model.canEdit)
    }
    func testRetryRechecksLockedOrCorruptStorageWithoutDispatchOrClear() async throws {
        let owner = try owner(), journal = SuspendedJournal(owner), service = Service()
        let pending = try PrivateHomeMutation(requestId: "pending", expectedVersion: 0, label: "Synthetic", point: PrivateHomePoint(latitude: 12, longitude: 45))
        journal.value = pending
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
        await model.load(); XCTAssertTrue(model.canRetry)
        journal.failRead = true
        await model.retryExact()
        XCTAssertEqual(service.writes, 0); XCTAssertEqual(service.reads, 1); XCTAssertEqual(journal.clears, 0)
        XCTAssertEqual(journal.value, pending); XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertTrue(model.canRetry)
        journal.failRead = false
        await model.retryExact()
        XCTAssertEqual(service.writes, 1); XCTAssertNil(journal.value)
    }
    func testRetryRejectsMissingOrReplacedDurableMutationWithoutClearingIt() async throws {
        let owner = try owner()
        let pending = try PrivateHomeMutation(requestId: "pending", expectedVersion: 0, label: "Synthetic", point: PrivateHomePoint(latitude: 12, longitude: 45))
        let replacements: [PrivateHomeMutation?] = [
            nil,
            try PrivateHomeMutation(requestId: "different-request", expectedVersion: 0, label: "Synthetic", point: PrivateHomePoint(latitude: 12, longitude: 45)),
            try PrivateHomeMutation(requestId: "pending", expectedVersion: 0, label: "Changed payload", point: PrivateHomePoint(latitude: 12, longitude: 45)),
            try PrivateHomeMutation(requestId: "pending", expectedVersion: 0)
        ]
        for replacement in replacements {
            let journal = SuspendedJournal(owner), service = Service()
            journal.value = pending
            let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
            await model.load(); journal.value = replacement
            await model.retryExact()
            XCTAssertEqual(service.writes, 0); XCTAssertEqual(service.reads, 1); XCTAssertEqual(journal.clears, 0)
            XCTAssertEqual(journal.value, replacement); XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.canRetry)
            XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertFalse(model.canEdit)
        }
    }
    func testLogoutDuringRetryReadNeverDispatchesOrClearsDurableLock() async throws {
        let owner = try owner(), journal = SuspendedJournal(owner), service = Service()
        let pending = try PrivateHomeMutation(requestId: "pending", expectedVersion: 0, label: "Synthetic", point: PrivateHomePoint(latitude: 12, longitude: 45))
        journal.value = pending
        var current: PlayExperienceSession? = owner
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { current })
        await model.load(); journal.pauseRead = true
        let task = Task { await model.retryExact() }
        while journal.waiting == nil { await Task.yield() }
        await model.retryExact(); XCTAssertEqual(journal.reads, 2) // repeat tap while the retry read awaits
        current = nil; model.invalidate(); journal.resume(); await task.value
        XCTAssertEqual(service.writes, 0); XCTAssertEqual(service.reads, 1); XCTAssertEqual(journal.clears, 0)
        XCTAssertEqual(journal.value, pending); XCTAssertNil(model.home); XCTAssertEqual(model.phase, .invalidated)
    }
    func testReplacementAfterRetryDispatchCannotBeClearedByOldReceipt() async throws {
        let owner = try owner(), journal = SuspendedJournal(owner), service = Service()
        let pending = try PrivateHomeMutation(requestId: "pending", expectedVersion: 0, label: "Synthetic", point: PrivateHomePoint(latitude: 12, longitude: 45))
        let replacement = try PrivateHomeMutation(requestId: "replacement", expectedVersion: 1)
        journal.value = pending
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
        await model.load(); service.afterSend = { journal.value = replacement }
        await model.retryExact()
        XCTAssertEqual(service.writes, 1); XCTAssertEqual(service.reads, 1); XCTAssertEqual(journal.clears, 1)
        XCTAssertEqual(journal.value, replacement); XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.canRetry)
        await model.retryExact()
        XCTAssertEqual(service.writes, 1); XCTAssertEqual(journal.clears, 1); XCTAssertEqual(journal.value, replacement)
    }

}
