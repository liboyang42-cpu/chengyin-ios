import XCTest
@testable import QuestifyCore

/// Source-only synthetic receipt/current readback tests. No backend, Keychain, GPS or grant. NOT_RUN.
@available(macOS 14.0, *) @MainActor final class PrivateHomeCurrentReadbackFenceTests: XCTestCase {
    @MainActor private final class Pause {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        func resume() { let saved = continuation; continuation = nil; saved?.resume() }
    }
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var saves: [PrivateHomeMutation] = [], clears: [PrivateHomeMutation] = []
        var failClear = false
        var beforeClear: Pause?
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() async throws -> PrivateHomeMutation? { value }
        func save(_ mutation: PrivateHomeMutation) async throws {
            saves.append(mutation)
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = mutation
        }
        func clear(matching mutation: PrivateHomeMutation) async throws {
            clears.append(mutation)
            if let pause = beforeClear { beforeClear = nil; await pause.wait() }
            guard !failClear, value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = nil
        }
    }
    @MainActor private final class Service: PrivateHomeServing {
        var home: PrivateHomeSnapshot
        var nextHome: PrivateHomeSnapshot?
        var outcome: PrivateHomeReceipt.Decision?
        var receiptVersion: Int64?
        var loseNext = false, failRead = false, wrongReceipt = false
        var readPause: Pause?
        var reads = 0
        var requests: [PrivateHomeMutation] = []
        var receipts: [String: PrivateHomeReceipt] = [:]
        init(_ home: PrivateHomeSnapshot) { self.home = home }
        func load() async throws -> PrivateHomeSnapshot {
            reads += 1
            if let pause = readPause { readPause = nil; await pause.wait() }
            if failRead { throw PrivateHomeIssue.unavailable }
            return home
        }
        func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
            requests.append(mutation)
            if receipts[mutation.requestId] == nil {
                let decision = outcome ?? (mutation.method == "PUT" ? .saved : .deleted)
                let version: Int64
                switch decision {
                case .saved, .deleted: version = mutation.expectedVersion + 1
                case .conflict: version = mutation.expectedVersion + 2
                case .cooldown, .forbidden: version = mutation.expectedVersion
                }
                receipts[mutation.requestId] = .init(requestId: wrongReceipt ? "not-original" : mutation.requestId,
                    decision: decision, version: receiptVersion ?? version)
            }
            if let nextHome { home = nextHome; self.nextHome = nil }
            if loseNext { loseNext = false; throw PrivateHomeIssue.unknownOutcome }
            return receipts[mutation.requestId]!
        }
    }
    private func owner(_ id: Int = 7, epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try .init(accountID: id, epoch: epoch, namespace: "synthetic-home", token: "synthetic-token")
    }
    private func snapshot(_ version: Int64 = 3, active: Bool = true) throws -> PrivateHomeSnapshot {
        let json = active
            ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}"
            : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(json.utf8))
    }
    private func model(_ service: Service, _ journal: Journal, _ owner: PlayExperienceSession,
                       current: (() -> PlayExperienceSession?)? = nil) -> PrivateHomeCoordinator {
        .init(service: service, journal: journal, owner: owner, enabled: true, current: current ?? { owner })
    }
    private func prepare(_ model: PrivateHomeCoordinator, delete: Bool = false) async throws {
        await model.load()
        if delete { model.prepareDelete() }
        else { model.prepareSet(label: "Synthetic new point", point: try .init(latitude: 13, longitude: 46)) }
        XCTAssertTrue(model.canConfirm)
    }
    private func knownButUnread(_ model: PrivateHomeCoordinator, _ decision: PrivateHomeReceipt.Decision,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.decision, decision, file: file, line: line)
        XCTAssertEqual(model.phase, .blocked, file: file, line: line)
        XCTAssertEqual(model.issue, .unavailable, file: file, line: line)
        XCTAssertNil(model.home, file: file, line: line)
        XCTAssertFalse(model.canEdit, file: file, line: line)
        XCTAssertFalse(model.canConfirm, file: file, line: line)
        XCTAssertFalse(model.canRetry, file: file, line: line)
    }

    func testSavedOrDeletedReceiptDoesNotAcceptAnOlderActiveSnapshot() async throws {
        for delete in [false, true] {
            let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
            try await prepare(model, delete: delete); await model.confirm()
            knownButUnread(model, delete ? .deleted : .saved)
            XCTAssertNil(journal.value); XCTAssertEqual(journal.clears.count, 1)
            XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(service.reads, 2)
            model.prepareSet(label: "Must stay blocked", point: try .init(latitude: 1, longitude: 2)); model.prepareDelete()
            await model.confirm(); await model.retryExact()
            XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(journal.saves.count, 1)
        }
    }

    func testEqualVersionReadRestoresEditingWithoutAnotherMutation() async throws {
        for delete in [false, true] {
            let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
            try await prepare(model, delete: delete); await model.confirm()
            service.home = try snapshot(4, active: !delete); await model.load()
            XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canEdit)
            XCTAssertEqual(model.home?.version, 4); XCTAssertEqual(model.home?.status, delete ? .deleted : .active)
            XCTAssertEqual(model.decision, delete ? .deleted : .saved); XCTAssertEqual(service.requests.count, 1)
            XCTAssertNil(journal.value); XCTAssertEqual(journal.clears.count, 1)
        }
    }

    func testNewerCurrentStateMayDifferFromTheOriginalTerminalDecision() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model, delete: true); service.nextHome = try snapshot(9, active: true); await model.confirm()
        XCTAssertEqual(model.decision, .deleted); XCTAssertEqual(model.home?.status, .active)
        XCTAssertEqual(model.home?.version, 9); XCTAssertTrue(model.canEdit)
        XCTAssertEqual(service.requests.count, 1)
    }

    func testCurrentReadFailureAndStaleRetryKeepKnownOutcomeWithoutReplaying() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); service.failRead = true; await model.confirm(); knownButUnread(model, .saved)
        service.failRead = false; await model.load(); knownButUnread(model, .saved)
        service.home = try snapshot(4); await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(journal.saves.count, 1); XCTAssertEqual(journal.clears.count, 1)
    }

    func testReceiptFloorSurvivesLaterRefreshInTheSameOwnerInstance() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); service.nextHome = try snapshot(4); await model.confirm()
        XCTAssertTrue(model.canEdit)
        service.home = try snapshot(3); await model.load(); knownButUnread(model, .saved)
        service.home = try snapshot(4); await model.load(); XCTAssertTrue(model.canEdit)
        XCTAssertEqual(service.requests.count, 1)
    }

    func testConflictAndNonmutatingTerminalVersionsAlsoBoundCurrentRead() async throws {
        for decision in [PrivateHomeReceipt.Decision.conflict, .cooldown, .forbidden] {
            let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
            try await prepare(model); service.outcome = decision
            service.nextHome = try snapshot(decision == .conflict ? 4 : 2)
            await model.confirm(); knownButUnread(model, decision)
            service.home = try snapshot(decision == .conflict ? 5 : 3); await model.load()
            XCTAssertTrue(model.canEdit); XCTAssertEqual(model.decision, decision); XCTAssertEqual(service.requests.count, 1)
        }
    }

    func testLaterReceiptCannotLowerAnAlreadyEstablishedFloor() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); service.nextHome = try snapshot(4); await model.confirm()
        model.prepareSet(label: "Second explicit request", point: try .init(latitude: 13, longitude: 46))
        service.outcome = .conflict; service.receiptVersion = 2; service.nextHome = try snapshot(2)
        await model.confirm(); knownButUnread(model, .conflict)
        service.home = try snapshot(4); await model.load(); XCTAssertTrue(model.canEdit)
        XCTAssertEqual(service.requests.count, 2); XCTAssertNil(journal.value)
    }

    func testLostReplyStillNeedsExactReceiptBeforeCurrentCanUnlock() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); service.loseNext = true; await model.confirm()
        let original = try XCTUnwrap(journal.value)
        service.home = try snapshot(100); await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.canRetry); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(journal.value, original); XCTAssertNil(model.decision)
        service.home = try snapshot(3); await model.retryExact(); knownButUnread(model, .saved)
        XCTAssertEqual(service.requests, [original, original]); XCTAssertNil(journal.value)
    }

    func testColdPendingRecoveryUsesItsReceiptFloorAfterExactRetry() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner)
        let original = try PrivateHomeMutation(requestId: "persisted-original", expectedVersion: 3)
        journal.value = original
        let model = model(service, journal, owner)
        await model.load(); XCTAssertEqual(model.phase, .unknown)
        await model.retryExact(); knownButUnread(model, .deleted)
        XCTAssertEqual(service.requests, [original]); XCTAssertNil(journal.value)
        service.home = try snapshot(4, active: false); await model.load(); XCTAssertTrue(model.canEdit)
    }

    func testFailedConditionalClearRemainsUnknownAndDoesNotRetireOriginal() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); journal.failClear = true; await model.confirm()
        let original = try XCTUnwrap(journal.value)
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision); XCTAssertTrue(model.canRetry)
        XCTAssertEqual(service.reads, 1)
        journal.failClear = false; await model.retryExact(); knownButUnread(model, .saved)
        XCTAssertEqual(service.requests, [original, original]); XCTAssertNil(journal.value)
    }

    func testUnmatchedReceiptNeverCreatesAKnownOutcomeOrClearsJournal() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); service.wrongReceipt = true; await model.confirm()
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision)
        XCTAssertNotNil(journal.value); XCTAssertTrue(journal.clears.isEmpty)
        service.home = try snapshot(100); await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertFalse(model.canEdit); XCTAssertEqual(service.requests.count, 1)
    }

    func testBackgroundDuringValidatedClearRetainsFloorForManualRefresh() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model, delete: true)
        let pause = Pause(expectation(description: "validated clear")); journal.beforeClear = pause
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelReview(); pause.resume(); await task.value
        knownButUnread(model, .deleted); XCTAssertEqual(service.reads, 1)
        await model.load(); knownButUnread(model, .deleted)
        service.home = try snapshot(4, active: false); await model.load()
        XCTAssertTrue(model.canEdit); XCTAssertEqual(service.requests.count, 1)
    }

    func testOwnerInvalidationDuringCurrentReadCannotReviveThePriorPoint() async throws {
        let owner = try owner(), service = try Service(snapshot()), journal = Journal(owner)
        var current: PlayExperienceSession? = owner
        let model = model(service, journal, owner, current: { current })
        try await prepare(model)
        let pause = Pause(expectation(description: "current read")); service.readPause = pause
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        current = nil; model.invalidate(); service.home = try snapshot(4); pause.resume(); await task.value
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.home); XCTAssertNil(model.decision)
        XCTAssertNil(journal.value); XCTAssertEqual(service.requests.count, 1)
    }

    func testMaximumTerminalVersionUsesIntegerComparisonWithoutOverflow() async throws {
        let owner = try owner(), service = try Service(snapshot(Int64.max - 1)), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model, delete: true); await model.confirm(); knownButUnread(model, .deleted)
        service.home = try snapshot(Int64.max, active: false); await model.load()
        XCTAssertEqual(model.home?.version, Int64.max); XCTAssertEqual(model.phase, .ready)
        model.prepareSet(label: "Version exhausted", point: try .init(latitude: 13, longitude: 46))
        XCTAssertFalse(model.canConfirm); XCTAssertEqual(service.requests.count, 1)
    }

    func testFreshOwnerWithoutKnownReceiptStillUsesExistingReadContract() async throws {
        let owner = try owner(8), service = try Service(snapshot(0, active: false)), journal = Journal(owner), model = model(service, journal, owner)
        await model.load(); XCTAssertTrue(model.canEdit); XCTAssertNil(model.decision)
        XCTAssertTrue(service.requests.isEmpty); XCTAssertTrue(journal.saves.isEmpty)
    }
}
