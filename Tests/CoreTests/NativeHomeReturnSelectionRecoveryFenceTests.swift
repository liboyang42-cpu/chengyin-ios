import XCTest
@testable import QuestifyCore

/// In-memory original-request recovery only. No GPS, Keychain, HTTP, grant or backend. NOT_RUN.
@available(macOS 14.0, *) @MainActor final class NativeHomeReturnSelectionRecoveryFenceTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    @MainActor private final class Pause {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        func resume() { let saved = continuation; continuation = nil; saved?.resume() }
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        var scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var failRead = false
        var readPause: Pause?
        var reads = 0, saves = 0
        var clears: [NativeHomeRestoreRequest] = []
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() async throws -> NativeHomeRestoreRequest? {
            reads += 1
            if let pause = readPause { readPause = nil; await pause.wait() }
            if failRead { throw NativeHomeReturnFailure.storageUnavailable }
            return value
        }
        func save(_ request: NativeHomeRestoreRequest) async throws {
            saves += 1
            guard value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = request
        }
        func clear(matching request: NativeHomeRestoreRequest) async throws {
            clears.append(request)
            guard value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = nil
        }
    }
    @MainActor private final class Service: NativeHomeReturnRunServing {
        var policyReads = 0, accountReads = 0, runReads = 0, verificationCalls = 0
        var restoreRequests: [NativeHomeRestoreRequest] = [], receiptRequests: [NativeHomeRestoreRequest] = []
        var receipts: [String: NativeHomeRestoreReceipt] = [:]
        var receiptPause: Pause?
        var accountFails = false
        var accountVersion: Int64 = 4
        var page = NativeHomeReturnRuns(runs: [], truncated: false, nextBeforeRunId: nil)
        func policy() async throws -> NativeHomeReturnPolicy? {
            policyReads += 1
            return .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30,
                         dwellSeconds: 0, serverTimeMillis: 1_000_000_000)
        }
        func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount {
            accountReads += 1
            if accountFails { throw NativeHomeReturnFailure.runUnavailable }
            return .init(resourceType: "sys.hp", scopeType: "RUN", scopeId: scope.wire["scopeId"],
                         current: accountVersion == 4 ? 2 : 5, maximum: 5, version: accountVersion)
        }
        func runs(beforeRunId: String?) async throws -> NativeHomeReturnRuns { runReads += 1; return page }
        func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification {
            verificationCalls += 1; throw NativeHomeReturnFailure.disabled
        }
        func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt {
            restoreRequests.append(request); throw NativeHomeReturnFailure.unknown
        }
        func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt? {
            receiptRequests.append(request)
            if let pause = receiptPause { receiptPause = nil; await pause.wait() }
            return receipts[request.requestId]
        }
    }
    @MainActor private final class Harness {
        let owner: PlayExperienceSession
        let service = Service()
        let journal: Journal
        var current = true
        var samples = 0
        var made: [NativeHomeReturnCoordinator] = []
        lazy var selection = NativeHomeReturnSelectionCoordinator(service: service, journal: journal, owner: owner,
            isCurrent: { [unowned self] in self.current }, makeModel: { [unowned self] scope in
                let model = NativeHomeReturnCoordinator(scope: scope, service: self.service, journal: self.journal, owner: self.owner,
                    enabled: true, location: { [unowned self] in self.samples += 1; return .denied },
                    isCurrent: { [unowned self] in self.current }, now: { NativeHomeReturnSelectionRecoveryFenceTests.now })
                self.made.append(model); return model
            })
        init() throws {
            owner = try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token")
            journal = Journal(owner)
        }
    }
    private func request(_ id: String = "original", proof: String = "proof", run: String = "42",
                         homeVersion: Int64 = 3, accountVersion: Int64 = 4) throws -> NativeHomeRestoreRequest {
        let value: [String: Any] = ["requestId": id, "proofId": proof, "scopeType": "RUN", "scopeId": run,
                                   "resourceType": "sys.hp", "homeVersion": homeVersion, "expectedAccountVersion": accountVersion]
        return try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func establish(_ h: Harness, _ original: NativeHomeRestoreRequest) async throws -> NativeHomeReturnCoordinator {
        h.journal.value = original; await h.selection.load()
        let selected = try XCTUnwrap(h.selection.selected)
        XCTAssertEqual(selected.phase, .unknown); XCTAssertTrue(selected.hasPendingRestore)
        XCTAssertEqual(h.made.count, 1)
        return selected
    }
    private func preserved(_ h: Harness, _ selected: NativeHomeReturnCoordinator,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(h.selection.selected === selected, file: file, line: line)
        XCTAssertEqual(h.made.count, 1, file: file, line: line)
        XCTAssertEqual(selected.phase, .unknown, file: file, line: line)
        XCTAssertTrue(selected.hasPendingRestore, file: file, line: line)
        XCTAssertFalse(h.selection.canSelect, file: file, line: line)
        XCTAssertTrue(h.service.restoreRequests.isEmpty, file: file, line: line)
        XCTAssertEqual(h.journal.saves, 0, file: file, line: line)
        XCTAssertEqual(h.samples, 0, file: file, line: line)
        XCTAssertEqual(h.service.verificationCalls, 0, file: file, line: line)
    }
    private func success(_ request: NativeHomeRestoreRequest) -> NativeHomeRestoreReceipt {
        .init(requestId: request.requestId, proofId: request.proofId, decision: .restored,
              current: 5, maximum: 5, accountVersion: request.expectedAccountVersion + 1, retryAfterSeconds: nil)
    }

    func testColdRecoveryKeepsOriginalScopeEvenWhenRunNoLongerEligible() async throws {
        let h = try Harness(), original = try request(run: "777")
        h.service.accountFails = true
        let selected = try await establish(h, original)
        XCTAssertEqual(selected.scope, original.scope); XCTAssertEqual(h.service.runReads, 0)
        XCTAssertEqual(selected.failure, .runUnavailable); preserved(h, selected)
        await selected.readBack()
        XCTAssertEqual(h.service.receiptRequests, [original]); XCTAssertEqual(h.journal.value, original)
        XCTAssertTrue(selected.noReceiptYet)
    }

    func testRefreshOfSameUnknownUsesOriginalCoordinatorWithoutAutomaticRetry() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        for _ in 0..<3 { await h.selection.load(); preserved(h, selected) }
        XCTAssertEqual(h.journal.value, original); XCTAssertEqual(h.journal.clears, [])
        XCTAssertEqual(h.service.runReads, 0); XCTAssertEqual(h.service.receiptRequests, [])
    }

    func testChangedSameScopeRecordCannotReplaceKnownOriginalIdentity() async throws {
        let replacements = [try request("other"), try request(proof: "other-proof"),
                            try request(homeVersion: 4), try request(accountVersion: 5)]
        for replacement in replacements {
            let h = try Harness(), original = try request(), selected = try await establish(h, original)
            let reads = h.service.accountReads, policies = h.service.policyReads
            h.journal.value = replacement; await h.selection.load()
            preserved(h, selected); XCTAssertEqual(selected.failure, .storageUnavailable)
            XCTAssertEqual(h.journal.value, replacement); XCTAssertEqual(h.journal.clears, [])
            XCTAssertEqual(h.service.accountReads, reads); XCTAssertEqual(h.service.policyReads, policies)
        }
    }

    func testDifferentRunReplacementDoesNotSwitchTheRecoveryScope() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        let replacement = try request("replacement", run: "12")
        h.journal.value = replacement; await h.selection.load()
        preserved(h, selected); XCTAssertEqual(selected.scope, original.scope)
        XCTAssertEqual(h.journal.value, replacement); XCTAssertEqual(h.service.runReads, 0)
    }

    func testMissingDurableRecordDoesNotUnlockKnownUnknownOrReinsertIt() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        h.journal.value = nil; await h.selection.load()
        preserved(h, selected); XCTAssertEqual(selected.failure, .storageUnavailable)
        XCTAssertNil(h.journal.value); XCTAssertEqual(h.service.runReads, 0); XCTAssertEqual(h.journal.clears, [])
    }

    func testLockedOrCorruptReadRetainsExistingUnknownAndNeverBuildsAReplacement() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        h.journal.failRead = true; await h.selection.load()
        preserved(h, selected); XCTAssertEqual(selected.failure, .storageUnavailable)
        XCTAssertEqual(h.journal.value, original); XCTAssertEqual(h.service.runReads, 0)
    }

    func testJournalScopeMismatchBlocksBeforeReadingOrReplacingSelected() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        let foreign = try PlayExperienceSession(accountID: 8, epoch: 1, namespace: "synthetic", token: "synthetic-other")
        h.journal.scope = .init(owner: foreign); let reads = h.journal.reads
        await h.selection.load()
        XCTAssertEqual(h.selection.phase, .blocked); preserved(h, selected)
        XCTAssertEqual(h.journal.reads, reads); XCTAssertEqual(h.journal.value, original)
    }

    func testExplicitRecoveryStillNamesOriginalAndCannotClearReplacementSlot() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        let replacement = try request("replacement")
        h.journal.value = replacement; h.service.receipts[original.requestId] = success(original)
        await h.selection.load(); await selected.retryExact()
        XCTAssertTrue(h.service.restoreRequests.isEmpty)
        await selected.readBack()
        preserved(h, selected); XCTAssertEqual(h.service.receiptRequests, [original])
        XCTAssertEqual(h.journal.clears, [original]); XCTAssertEqual(h.journal.value, replacement)
        XCTAssertNil(selected.decision)
    }

    func testOriginalSlotCanRecoverAfterMismatchWithoutMintingAnotherRequest() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        h.journal.value = try request("replacement"); await h.selection.load(); preserved(h, selected)
        h.journal.value = original; await h.selection.load(); preserved(h, selected)
        h.service.receipts[original.requestId] = success(original); h.service.accountVersion = 5
        await selected.readBack()
        XCTAssertNil(h.journal.value); XCTAssertEqual(h.journal.clears, [original])
        XCTAssertEqual(h.service.receiptRequests, [original]); XCTAssertTrue(h.service.restoreRequests.isEmpty)
        XCTAssertEqual(selected.decision, .restored); XCTAssertEqual(selected.account?.version, 5)
        XCTAssertFalse(selected.hasPendingRestore); XCTAssertEqual(h.made.count, 1)
    }

    func testOwnerInvalidationDuringRefreshCannotResurrectASelectedModel() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        let pause = Pause(expectation(description: "original journal read")); h.journal.readPause = pause
        let operation = Task { await h.selection.load() }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        h.current = false; h.selection.invalidate(); pause.resume(); await operation.value
        XCTAssertEqual(h.selection.phase, .invalidated); XCTAssertNil(h.selection.selected)
        XCTAssertEqual(selected.phase, .invalidated); XCTAssertEqual(h.made.count, 1)
        XCTAssertEqual(h.journal.value, original); XCTAssertEqual(h.journal.clears, [])
        XCTAssertTrue(h.service.restoreRequests.isEmpty)
    }

    func testBusyOriginalReceiptReadCannotBeReplacedByShelfRefresh() async throws {
        let h = try Harness(), original = try request(), selected = try await establish(h, original)
        let pause = Pause(expectation(description: "original receipt read")); h.service.receiptPause = pause
        let operation = Task { await selected.readBack() }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        let reads = h.journal.reads; await h.selection.load()
        XCTAssertTrue(h.selection.selected === selected); XCTAssertEqual(h.made.count, 1)
        XCTAssertEqual(h.journal.reads, reads); XCTAssertEqual(selected.phase, .restoring)
        pause.resume(); await operation.value; preserved(h, selected)
        XCTAssertEqual(h.service.receiptRequests, [original])
    }

    func testNoPendingShelfRefreshAndExplicitSelectionRemainAvailable() async throws {
        let h = try Harness()
        let run = NativeHomeReturnRun(runId: "42", activityId: "5", topicId: "6", playInstanceId: "synthetic-run",
                                     resourceType: "sys.hp", current: 2, maximum: 5, version: 4)
        h.service.page = .init(runs: [run], truncated: false, nextBeforeRunId: nil)
        await h.selection.load(); XCTAssertTrue(h.selection.canSelect); XCTAssertNil(h.selection.selected)
        await h.selection.select(run); let previous = try XCTUnwrap(h.selection.selected)
        XCTAssertEqual(previous.phase, .ready); XCTAssertFalse(previous.hasPendingRestore)
        await h.selection.load()
        XCTAssertNil(h.selection.selected); XCTAssertEqual(previous.phase, .invalidated)
        XCTAssertTrue(h.selection.canSelect); XCTAssertEqual(h.service.runReads, 2)
        XCTAssertEqual(h.journal.saves, 0); XCTAssertTrue(h.service.restoreRequests.isEmpty)
    }
}
