import XCTest
@testable import QuestifyCore

/// In-memory suspension seams only. No location, Keychain, HTTP or backend is used. NOT_RUN.
@available(macOS 14.0, *) @MainActor final class NativeHomeReturnCancellationTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    @MainActor private final class Pause {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async {
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
        }
        func resume() { let saved = continuation; continuation = nil; saved?.resume() }
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var saves: [NativeHomeRestoreRequest] = []
        var reads = 0, clears = 0
        var beforeSave: Pause?, afterSave: Pause?, beforeRead: Pause?, beforeClear: Pause?
        var failSave = false, failClear = false
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() async throws -> NativeHomeRestoreRequest? {
            reads += 1
            if let pause = beforeRead { beforeRead = nil; await pause.wait() }
            return value
        }
        func save(_ request: NativeHomeRestoreRequest) async throws {
            saves.append(request)
            if let pause = beforeSave { beforeSave = nil; await pause.wait() }
            guard !failSave, value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = request
            if let pause = afterSave { afterSave = nil; await pause.wait() }
        }
        func clear(matching request: NativeHomeRestoreRequest) async throws {
            clears += 1
            if let pause = beforeClear { beforeClear = nil; await pause.wait() }
            guard !failClear, value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = nil
        }
    }
    @MainActor private final class Service: NativeHomeReturnServing {
        var requests: [NativeHomeRestoreRequest] = []
        var checks: [NativeHomeReturnCheck] = []
        var receipts: [String: NativeHomeRestoreReceipt] = [:]
        var accountReads = 0, receiptReads = 0
        var current: Int64 = 2, version: Int64 = 4
        var loseNextResponse = false
        var beforeResponse: Pause?, beforeReceipt: Pause?
        func policy() async throws -> NativeHomeReturnPolicy? {
            .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30,
                  dwellSeconds: 0, serverTimeMillis: 1_000_000_000)
        }
        func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount {
            accountReads += 1
            return .init(resourceType: "sys.hp", scopeType: "RUN", scopeId: scope.wire["scopeId"],
                         current: current, maximum: 5, version: version)
        }
        func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification {
            checks.append(check)
            return .init(requestId: check.requestId, decision: .verified, proofId: "synthetic-proof",
                homeVersion: check.homeVersion, expiresAtMillis: 1_000_060_000, retryAfterSeconds: nil,
                accountVersion: version)
        }
        func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt {
            requests.append(request)
            if receipts[request.requestId] == nil {
                current = 5; version += 1
                receipts[request.requestId] = .init(requestId: request.requestId, proofId: request.proofId,
                    decision: .restored, current: current, maximum: 5, accountVersion: version, retryAfterSeconds: nil)
            }
            if let pause = beforeResponse { beforeResponse = nil; await pause.wait() }
            if loseNextResponse { loseNextResponse = false; throw NativeHomeReturnFailure.network }
            return receipts[request.requestId]!
        }
        func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt? {
            receiptReads += 1
            if let pause = beforeReceipt { beforeReceipt = nil; await pause.wait() }
            return receipts[request.requestId]
        }
    }
    private func owner() throws -> PlayExperienceSession {
        try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token")
    }
    private func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
    }
    private func model(_ service: Service, _ journal: Journal, current: @escaping () -> Bool = { true }) throws -> NativeHomeReturnCoordinator {
        NativeHomeReturnCoordinator(scope: .run(runId: "42", resourceType: "sys.hp"), service: service,
            journal: journal, owner: try owner(), enabled: true,
            location: { .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: Self.now)) },
            locationAuthorized: { true }, isCurrent: current, now: { Self.now })
    }
    private func verify(_ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try home()); XCTAssertEqual(model.phase, .verified)
    }
    private func assertUnknown(_ model: NativeHomeReturnCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .unknown, file: file, line: line)
        XCTAssertTrue(model.hasPendingRestore, file: file, line: line)
        XCTAssertFalse(model.canRestore, file: file, line: line)
        XCTAssertFalse(model.canCheckIn, file: file, line: line)
        XCTAssertNil(model.decision, file: file, line: line)
    }
    func testNavigationDuringEitherSaveStageNeverDispatchesAndKeepsExactRecovery() async throws {
        for savedAlready in [false, true] {
            let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
            try await verify(model)
            let pause = Pause(expectation(description: "save stage \(savedAlready)"))
            if savedAlready { journal.afterSave = pause } else { journal.beforeSave = pause }
            let operation = Task { await model.confirmRestore(home: home) }
            defer { pause.resume(); operation.cancel() }
            await fulfillment(of: [pause.entered], timeout: 1)
            let original = try XCTUnwrap(journal.saves.first)
            model.cancelVerification(); assertUnknown(model)
            XCTAssertTrue(service.requests.isEmpty)
            pause.resume(); await operation.value
            XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0)
            await model.load(); assertUnknown(model); XCTAssertTrue(service.requests.isEmpty)
            await model.retryExact()
            XCTAssertEqual(service.requests, [original]); XCTAssertEqual(journal.saves, [original]); XCTAssertNil(journal.value)
        }
    }
    func testTaskCancellationDuringSaveCannotDispatchWhenStorageReturnsNormally() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "save")); journal.afterSave = pause
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        operation.cancel(); pause.resume(); await operation.value
        assertUnknown(model); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.value, journal.saves.first)
        XCTAssertEqual(journal.clears, 0)
    }
    func testCancellationDuringFinalJournalReadStopsInitialAndRetryDispatch() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model)
        for initial in [true, false] {
            let pause = Pause(expectation(description: "durable preflight \(initial)")); journal.beforeRead = pause
            let operation = Task { if initial { await model.confirmRestore(home: home) } else { await model.retryExact() } }
            defer { pause.resume(); operation.cancel() }
            await fulfillment(of: [pause.entered], timeout: 1)
            model.cancelVerification(); pause.resume(); await operation.value
            assertUnknown(model); XCTAssertTrue(service.requests.isEmpty); XCTAssertNotNil(journal.value); XCTAssertEqual(journal.clears, 0)
        }
        let original = try XCTUnwrap(journal.value); await model.retryExact(); XCTAssertEqual(service.requests, [original])
    }
    func testLateWriteReceiptAfterNavigationStaysUnknownUntilExplicitReadback() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "write response")); service.beforeResponse = pause
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        let original = try XCTUnwrap(journal.value); XCTAssertEqual(service.requests, [original])
        model.cancelVerification(); pause.resume(); await operation.value
        assertUnknown(model); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0); XCTAssertEqual(service.accountReads, 1)
        await model.readBack()
        XCTAssertEqual(service.requests, [original]); XCTAssertEqual(service.receiptReads, 1); XCTAssertNil(journal.value)
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
    }
    func testTaskCancellationAfterDispatchRetainsUnknownEvenWhenServiceIgnoresCancellation() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "write response")); service.beforeResponse = pause
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        operation.cancel(); pause.resume(); await operation.value
        assertUnknown(model); XCTAssertEqual(service.requests.count, 1); XCTAssertNotNil(journal.value)
        XCTAssertEqual(journal.clears, 0); XCTAssertEqual(service.accountReads, 1)
    }
    func testCancelledReceiptReadCannotClearJournalOrAutomaticallyRetry() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        try await verify(model); service.loseNextResponse = true; await model.confirmRestore(home: try home()); assertUnknown(model)
        let original = try XCTUnwrap(journal.value), pause = Pause(expectation(description: "receipt read")); service.beforeReceipt = pause
        let operation = Task { await model.readBack() }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelVerification(); pause.resume(); await operation.value
        assertUnknown(model); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0); XCTAssertEqual(service.requests, [original])
        await model.readBack(); XCTAssertNil(journal.value); XCTAssertEqual(service.requests, [original])
    }
    func testKnownTerminalClearMayFinishButNavigationStopsAutomaticCurrentRead() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "validated terminal clear")); journal.beforeClear = pause
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelVerification(); XCTAssertEqual(model.phase, .restoring)
        pause.resume(); await operation.value
        XCTAssertNil(journal.value); XCTAssertFalse(model.hasPendingRestore); XCTAssertEqual(model.decision, .restored)
        XCTAssertEqual(model.phase, .unavailable); XCTAssertTrue(model.requiresAccountReadback); XCTAssertNil(model.account)
        XCTAssertFalse(model.canCheckIn); XCTAssertEqual(service.accountReads, 1); XCTAssertEqual(service.requests.count, 1)
        await model.load(); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(service.requests.count, 1)
    }
    func testTaskCancelledDuringValidatedClearAlsoStopsAutomaticCurrentRead() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "terminal clear")); journal.beforeClear = pause
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        operation.cancel(); pause.resume(); await operation.value
        XCTAssertNil(journal.value); XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.phase, .unavailable)
        XCTAssertTrue(model.requiresAccountReadback); XCTAssertNil(model.account); XCTAssertEqual(service.accountReads, 1)
    }
    func testCancelledSaveThatFailsNeverBecomesSuccessOrUnlocksAnUnprovenRequest() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "failing save")); journal.beforeSave = pause; journal.failSave = true
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelVerification(); pause.resume(); await operation.value
        assertUnknown(model); XCTAssertNil(journal.value); XCTAssertTrue(service.requests.isEmpty)
        await model.load(); assertUnknown(model); XCTAssertEqual(model.failure, .storageUnavailable); XCTAssertTrue(service.requests.isEmpty)
    }
    func testFailedTerminalClearAfterNavigationRetainsOriginalUnknownForReadback() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "failing clear")); journal.beforeClear = pause; journal.failClear = true
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelVerification(); pause.resume(); await operation.value
        assertUnknown(model); XCTAssertNotNil(journal.value); XCTAssertEqual(service.accountReads, 1); XCTAssertEqual(service.requests.count, 1)
        journal.failClear = false; await model.readBack(); XCTAssertNil(journal.value); XCTAssertEqual(service.requests.count, 1)
    }
    func testOwnerInvalidationDuringSaveKeepsOnlyScopedDurableRecoveryAndNeverDispatches() async throws {
        var current = true
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal, current: { current }), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "owner save")); journal.afterSave = pause
        let operation = Task { await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        current = false; model.invalidate(); pause.resume(); await operation.value
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.account); XCTAssertFalse(model.hasPendingRestore)
        XCTAssertNotNil(journal.value); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.clears, 0)
    }
    func testAlreadyCancelledConfirmationDoesNotSaveOrConsumeProof() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal), home = try home()
        try await verify(model); let pause = Pause(expectation(description: "before confirmation"))
        let operation = Task { await pause.wait(); await model.confirmRestore(home: home) }; defer { pause.resume(); operation.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        operation.cancel(); pause.resume(); await operation.value
        XCTAssertTrue(journal.saves.isEmpty); XCTAssertTrue(service.requests.isEmpty); XCTAssertNil(journal.value)
        XCTAssertEqual(model.phase, .verified); XCTAssertTrue(model.canRestore)
    }
}
