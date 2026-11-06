import XCTest
@testable import QuestifyCore

/// Synthetic storage/service only. No backend, filesystem, OS Keychain or location operation.
@available(macOS 14.0, *) @MainActor final class PrivateHomeRecoveryFenceTests: XCTestCase {
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        var scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var failRead = false, failClear = false
        var reads = 0, saves = 0, clears = 0
        var afterRead: (() -> Void)?
        var pauseRead = false
        var onPaused: (() -> Void)?
        var resumeRead: CheckedContinuation<Void, Never>?
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() async throws -> PrivateHomeMutation? {
            reads += 1
            if pauseRead { await withCheckedContinuation { resumeRead = $0; onPaused?() } }
            afterRead?()
            if failRead { throw PrivateHomeIssue.storageUnavailable }
            return value
        }
        func save(_ mutation: PrivateHomeMutation) async throws {
            saves += 1
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = mutation
        }
        func clear(matching mutation: PrivateHomeMutation) async throws {
            clears += 1
            guard !failClear, value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = nil
        }
    }
    @MainActor private final class Service: PrivateHomeServing {
        var home: PrivateHomeSnapshot
        var reads = 0
        var mutations: [PrivateHomeMutation] = []
        var failLoad = false, loseNext = false
        var outcome: PrivateHomeReceipt.Decision?
        var receipts: [String: PrivateHomeReceipt] = [:]
        init(_ home: PrivateHomeSnapshot) { self.home = home }
        func load() async throws -> PrivateHomeSnapshot {
            reads += 1
            if failLoad { throw PrivateHomeIssue.unavailable }
            return home
        }
        func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
            mutations.append(mutation)
            if receipts[mutation.requestId] == nil {
                let decision = outcome ?? (mutation.method == "PUT" ? .saved : .deleted)
                let version: Int64
                switch decision {
                case .saved, .deleted: version = mutation.expectedVersion + 1
                case .conflict: version = mutation.expectedVersion + 2
                case .cooldown, .forbidden: version = mutation.expectedVersion
                }
                receipts[mutation.requestId] = .init(requestId: mutation.requestId, decision: decision, version: version)
            }
            if loseNext { loseNext = false; throw PrivateHomeIssue.unknownOutcome }
            return receipts[mutation.requestId]!
        }
    }
    private func owner(_ account: Int = 12, epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: "synthetic-home", token: "synthetic")
    }
    private func point(_ latitude: Decimal = 12) throws -> PrivateHomePoint {
        try .init(latitude: latitude, longitude: 45)
    }
    private func snapshot(_ version: Int64 = 3, active: Bool = true) throws -> PrivateHomeSnapshot {
        let body = active
            ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}"
            : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(body.utf8))
    }
    private func model(_ service: Service, _ journal: Journal, _ owner: PlayExperienceSession) -> PrivateHomeCoordinator {
        .init(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
    }
    private func lose(_ model: PrivateHomeCoordinator, _ service: Service, _ journal: Journal,
                      delete: Bool = false) async throws -> PrivateHomeMutation {
        await model.load()
        if delete { model.prepareDelete() } else { model.prepareSet(label: "Synthetic new home", point: try point()) }
        service.loseNext = true
        await model.confirm()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(service.mutations.count, 1)
        return try XCTUnwrap(journal.value)
    }
    private func assertLocked(_ model: PrivateHomeCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .unknown, file: file, line: line)
        XCTAssertEqual(model.issue, .storageUnavailable, file: file, line: line)
        XCTAssertTrue(model.canRetry, file: file, line: line)
        XCTAssertFalse(model.canEdit, file: file, line: line)
        XCTAssertFalse(model.canConfirm, file: file, line: line)
        XCTAssertNil(model.decision, file: file, line: line)
    }

    func testMissingSlotAfterLostPutOrDeleteCannotUnlockFromFreshGet() async throws {
        for delete in [false, true] {
            for activeCurrent in [false, true] {
                let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
                let model = model(service, journal, owner)
                let original = try await lose(model, service, journal, delete: delete)
                journal.value = nil; service.home = try snapshot(100, active: activeCurrent)
                await model.load(); assertLocked(model)
                model.prepareSet(label: "Must not stage", point: try point()); model.prepareDelete(); await model.confirm()
                await model.retryExact()
                XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.mutations, [original])
                XCTAssertNil(journal.value); XCTAssertEqual(journal.saves, 1); XCTAssertEqual(journal.clears, 0)
            }
        }
    }
    func testReplacedIdentityPayloadMethodVersionOrPointCannotBeAdopted() async throws {
        for variant in 0..<5 {
            let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
            let model = model(service, journal, owner)
            let original = try await lose(model, service, journal)
            let replacement = try PrivateHomeMutation(requestId: variant == 0 ? "replacement" : original.requestId,
                expectedVersion: variant == 3 ? original.expectedVersion + 1 : original.expectedVersion,
                label: variant == 2 ? nil : (variant == 1 ? "Changed payload" : original.label),
                point: variant == 2 ? nil : point(variant == 4 ? 13 : 12))
            journal.value = replacement
            let reads = service.reads
            await model.load(); assertLocked(model); await model.retryExact()
            XCTAssertEqual(service.reads, reads); XCTAssertEqual(service.mutations, [original])
            XCTAssertEqual(journal.value, replacement); XCTAssertEqual(journal.clears, 0)
        }
    }
    func testRestoringOriginalSlotRequiresExplicitRetryAndOriginalReceipt() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let model = model(service, journal, owner)
        let original = try await lose(model, service, journal)
        journal.value = nil; await model.load(); assertLocked(model)
        // Only the test fixture restores its stored record. Product load never re-saves missing data.
        journal.value = original
        await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(journal.saves, 1)
        await model.retryExact()
        XCTAssertEqual(service.mutations, [original, original]); XCTAssertNil(journal.value)
        XCTAssertEqual(journal.clears, 1); XCTAssertEqual(model.decision, .saved); XCTAssertTrue(model.canEdit)
    }
    func testCorruptOrLockedReadRetainsKnownOriginalAndCannotDispatch() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let model = model(service, journal, owner)
        let original = try await lose(model, service, journal)
        journal.failRead = true
        await model.load(); assertLocked(model); await model.retryExact()
        XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(service.reads, 1)
        XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0)
        journal.failRead = false
        await model.load(); XCTAssertEqual(model.phase, .unknown)
        XCTAssertEqual(service.mutations, [original])
    }
    func testInvalidDecodedReplacementCannotEraseKnownOriginal() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let model = model(service, journal, owner)
        let original = try await lose(model, service, journal)
        journal.value = try JSONDecoder().decode(PrivateHomeMutation.self,
            from: Data(#"{"requestId":"invalid-id","expectedVersion":-1}"#.utf8))
        await model.load(); assertLocked(model); await model.retryExact()
        XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(service.reads, 1)
        XCTAssertEqual(journal.value?.expectedVersion, -1); XCTAssertEqual(journal.clears, 0)
    }
    func testColdRecreationRecoversDurableOriginalWithoutAutomaticReplay() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let first = model(service, journal, owner)
        let original = try await lose(first, service, journal, delete: true)
        first.invalidate()
        let replacementOwner = try self.owner(epoch: 2)
        let recreated = model(service, journal, replacementOwner)
        await recreated.load(); await recreated.load()
        XCTAssertEqual(recreated.phase, .unknown); XCTAssertFalse(recreated.canEdit)
        XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(journal.value, original)
        await recreated.retryExact()
        XCTAssertEqual(service.mutations, [original, original]); XCTAssertEqual(recreated.decision, .deleted)
        XCTAssertNil(journal.value)
    }
    func testColdCorruptStorageBlocksBeforeCurrentRead() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        journal.failRead = true
        let model = model(service, journal, owner)
        await model.load()
        XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit); XCTAssertFalse(model.canRetry)
        XCTAssertEqual(service.reads, 0); XCTAssertTrue(service.mutations.isEmpty)
    }
    func testFreshEmptyJournalStillAllowsReadAndExplicitReview() async throws {
        // With no known original identity, nil cannot prove a past operation. Preserve the existing
        // fresh-start contract rather than inventing a durable tombstone or claiming loss detection.
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let model = model(service, journal, owner)
        await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canEdit)
        model.prepareSet(label: "Explicit review", point: try point())
        XCTAssertTrue(model.canConfirm); XCTAssertTrue(service.mutations.isEmpty)
    }
    func testEveryMatchingTerminalDecisionCanClearThenRefreshNormally() async throws {
        for decision in [PrivateHomeReceipt.Decision.saved, .deleted, .conflict, .cooldown, .forbidden] {
            let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
            let original = try PrivateHomeMutation(requestId: "terminal-" + decision.rawValue, expectedVersion: 3,
                label: decision == .deleted ? nil : "Synthetic", point: decision == .deleted ? nil : point())
            journal.value = original; service.outcome = decision
            let model = model(service, journal, owner)
            await model.load(); XCTAssertEqual(model.phase, .unknown)
            await model.retryExact()
            XCTAssertEqual(model.decision, decision); XCTAssertEqual(model.phase, .ready)
            XCTAssertTrue(model.canEdit); XCTAssertNil(journal.value); XCTAssertEqual(journal.clears, 1)
            XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(service.reads, 2)
            await model.load(); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(service.mutations, [original])
        }
    }
    func testFailedConditionalClearThenMissingSlotStillNeedsOriginalReceiptBoundary() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let model = model(service, journal, owner)
        await model.load(); model.prepareSet(label: "Synthetic", point: try point()); journal.failClear = true
        await model.confirm()
        let original = try XCTUnwrap(journal.value)
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision)
        journal.value = nil
        await model.load(); assertLocked(model); await model.retryExact()
        XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(service.reads, 1)
        XCTAssertEqual(journal.clears, 1); XCTAssertEqual(journal.saves, 1)
    }
    func testScopeChangeDuringReadCannotAdoptAnotherOwnerRecord() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        let other = try self.owner(99)
        journal.value = try PrivateHomeMutation(requestId: "foreign", expectedVersion: 3)
        journal.afterRead = { journal.scope = .init(owner: other) }
        let model = model(service, journal, owner)
        await model.load()
        XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit); XCTAssertFalse(model.canRetry)
        XCTAssertEqual(service.reads, 0); XCTAssertTrue(service.mutations.isEmpty); XCTAssertEqual(journal.clears, 0)
    }
    func testInvalidationDuringRecoveryReadCannotRestoreOldOwnerPresentation() async throws {
        let owner = try owner(), journal = Journal(owner), service = try Service(snapshot())
        var current: PlayExperienceSession? = owner
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { current })
        let original = try await lose(model, service, journal)
        let paused = expectation(description: "Recovery journal suspended")
        journal.pauseRead = true; journal.onPaused = { paused.fulfill() }
        let task = Task { await model.load() }
        await fulfillment(of: [paused], timeout: 1)
        current = nil; model.invalidate()
        let resume = try XCTUnwrap(journal.resumeRead); journal.resumeRead = nil; resume.resume()
        await task.value
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.home); XCTAssertNil(model.decision)
        XCTAssertEqual(journal.value, original); XCTAssertEqual(service.reads, 1)
        XCTAssertEqual(service.mutations, [original]); XCTAssertEqual(journal.clears, 0)
    }
}
