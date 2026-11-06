import XCTest
@testable import QuestifyCore

/// In-memory suspension seams only. No location, Keychain, HTTP or backend operation. NOT_RUN.
@available(macOS 14.0, *) @MainActor final class PrivateHomeCRUDCancellationTests: XCTestCase {
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
        var saves: [PrivateHomeMutation] = []
        var reads = 0, clears = 0
        var beforeSave: Pause?, afterSave: Pause?, beforeRead: Pause?, beforeClear: Pause?, afterClear: Pause?
        var failSave = false, failClear = false
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() async throws -> PrivateHomeMutation? {
            reads += 1
            if let pause = beforeRead { beforeRead = nil; await pause.wait() }
            return value
        }
        func save(_ mutation: PrivateHomeMutation) async throws {
            saves.append(mutation)
            if let pause = beforeSave { beforeSave = nil; await pause.wait() }
            guard !failSave, value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = mutation
            if let pause = afterSave { afterSave = nil; await pause.wait() }
        }
        func clear(matching mutation: PrivateHomeMutation) async throws {
            clears += 1
            if let pause = beforeClear { beforeClear = nil; await pause.wait() }
            guard !failClear, value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = nil
            if let pause = afterClear { afterClear = nil; await pause.wait() }
        }
    }
    @MainActor private final class Service: PrivateHomeServing {
        var requests: [PrivateHomeMutation] = []
        var receipts: [String: PrivateHomeReceipt] = [:]
        var reads = 0, version: Int64 = 3
        var active = true
        var beforeResponse: Pause?
        func load() async throws -> PrivateHomeSnapshot {
            reads += 1
            let body = active
                ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}"
                : "{\"version\":\(version),\"status\":\"DELETED\"}"
            return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(body.utf8))
        }
        func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
            requests.append(mutation)
            // Synthetic commit precedes the paused response: cancellation is not rollback.
            if receipts[mutation.requestId] == nil {
                version = mutation.expectedVersion + 1; active = mutation.method == "PUT"
                receipts[mutation.requestId] = .init(requestId: mutation.requestId,
                    decision: active ? .saved : .deleted, version: version)
            }
            if let pause = beforeResponse { beforeResponse = nil; await pause.wait() }
            return receipts[mutation.requestId]!
        }
    }
    private func owner() throws -> PlayExperienceSession {
        try .init(accountID: 7, epoch: 1, namespace: "synthetic-home", token: "synthetic")
    }
    private func model(_ service: Service, _ journal: Journal, _ owner: PlayExperienceSession) -> PrivateHomeCoordinator {
        .init(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
    }
    private func prepare(_ model: PrivateHomeCoordinator, delete: Bool = false) async throws {
        await model.load()
        if delete { model.prepareDelete() }
        else { model.prepareSet(label: "Synthetic new home", point: try .init(latitude: 12, longitude: 45)) }
        XCTAssertTrue(model.canConfirm)
    }
    private func assertUnknown(_ model: PrivateHomeCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .unknown, file: file, line: line)
        XCTAssertTrue(model.canRetry, file: file, line: line)
        XCTAssertFalse(model.canEdit, file: file, line: line)
        XCTAssertFalse(model.canConfirm, file: file, line: line)
        XCTAssertNil(model.review, file: file, line: line)
        XCTAssertNil(model.decision, file: file, line: line)
    }

    func testNavigationDuringEitherSaveStageStopsPutAndDeleteDispatch() async throws {
        for delete in [false, true] {
            for savedAlready in [false, true] {
                let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
                try await prepare(model, delete: delete)
                let pause = Pause(expectation(description: "Save stage"))
                if savedAlready { journal.afterSave = pause } else { journal.beforeSave = pause }
                let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
                await fulfillment(of: [pause.entered], timeout: 1)
                let original = try XCTUnwrap(journal.saves.first)
                model.cancelReview(); assertUnknown(model)
                pause.resume(); await task.value
                XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0)
                await model.load(); assertUnknown(model); XCTAssertTrue(service.requests.isEmpty)
                await model.retryExact()
                XCTAssertEqual(service.requests, [original]); XCTAssertEqual(journal.saves, [original])
                XCTAssertNil(journal.value); XCTAssertEqual(model.decision, delete ? .deleted : .saved)
            }
        }
    }
    func testTaskCancelledDuringSaveCannotDispatchDespiteNormalStorageReturn() async throws {
        for delete in [false, true] {
            let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
            try await prepare(model, delete: delete)
            let pause = Pause(expectation(description: "Saved")); journal.afterSave = pause
            let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
            await fulfillment(of: [pause.entered], timeout: 1)
            task.cancel(); pause.resume(); await task.value
            assertUnknown(model); XCTAssertTrue(service.requests.isEmpty)
            XCTAssertEqual(journal.value, journal.saves.first); XCTAssertEqual(journal.clears, 0)
        }
    }
    func testFinalDurableReadCancellationStopsInitialAndRetryDispatch() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model)
        for initial in [true, false] {
            let pause = Pause(expectation(description: "Pre-dispatch journal read")); journal.beforeRead = pause
            let task = Task { if initial { await model.confirm() } else { await model.retryExact() } }
            defer { pause.resume(); task.cancel() }
            await fulfillment(of: [pause.entered], timeout: 1)
            model.cancelReview(); pause.resume(); await task.value
            assertUnknown(model); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.clears, 0)
        }
        let original = try XCTUnwrap(journal.value)
        await model.retryExact(); XCTAssertEqual(service.requests, [original])
    }
    func testLateWriteReceiptAfterNavigationStaysUnknownUntilExplicitExactRetry() async throws {
        for delete in [false, true] {
            let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
            try await prepare(model, delete: delete)
            let pause = Pause(expectation(description: "Committed, response delayed")); service.beforeResponse = pause
            let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
            await fulfillment(of: [pause.entered], timeout: 1)
            let original = try XCTUnwrap(journal.value)
            XCTAssertEqual(service.requests, [original]); XCTAssertEqual(service.receipts.count, 1)
            model.cancelReview(); pause.resume(); await task.value
            assertUnknown(model); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0)
            await model.load(); assertUnknown(model); XCTAssertEqual(service.requests, [original])
            await model.retryExact()
            XCTAssertEqual(service.requests, [original, original]); XCTAssertEqual(service.receipts.count, 1)
            XCTAssertEqual(service.version, original.expectedVersion + 1); XCTAssertNil(journal.value)
        }
    }
    func testTaskCancelledAfterDispatchCannotClearWithLateSuccessfulResponse() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model)
        let pause = Pause(expectation(description: "Response")); service.beforeResponse = pause
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        let original = try XCTUnwrap(journal.value)
        task.cancel(); pause.resume(); await task.value
        assertUnknown(model); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0)
        XCTAssertEqual(service.requests, [original]); XCTAssertEqual(service.reads, 1)
    }
    func testNavigationDuringEitherTerminalClearStageRetainsKnownDecisionWithoutAutoGet() async throws {
        for delete in [false, true] {
            for clearedAlready in [false, true] {
                let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
                try await prepare(model, delete: delete)
                let pause = Pause(expectation(description: "Validated terminal clear"))
                if clearedAlready { journal.afterClear = pause } else { journal.beforeClear = pause }
                let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
                await fulfillment(of: [pause.entered], timeout: 1)
                model.cancelReview(); pause.resume(); await task.value
                XCTAssertEqual(model.decision, delete ? .deleted : .saved); XCTAssertEqual(model.phase, .blocked)
                XCTAssertNil(journal.value); XCTAssertNil(model.home); XCTAssertFalse(model.canRetry); XCTAssertFalse(model.canEdit)
                XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(service.reads, 1)
                await model.load()
                XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.canEdit); XCTAssertEqual(service.reads, 2)
            }
        }
    }
    func testTaskCancelledDuringTerminalClearDoesNotInventUnknownOrAutoRefresh() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model)
        let pause = Pause(expectation(description: "Clear")); journal.beforeClear = pause
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        task.cancel(); pause.resume(); await task.value
        XCTAssertEqual(model.decision, .saved); XCTAssertEqual(model.phase, .blocked)
        XCTAssertNil(journal.value); XCTAssertNil(model.home); XCTAssertFalse(model.canRetry)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.requests.count, 1)
    }
    func testClearFailureAfterEitherCancellationKeepsOriginalUnknown() async throws {
        for cancelTask in [false, true] {
            let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
            try await prepare(model)
            let pause = Pause(expectation(description: "Failing clear")); journal.beforeClear = pause; journal.failClear = true
            let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
            await fulfillment(of: [pause.entered], timeout: 1)
            let original = try XCTUnwrap(journal.value)
            if cancelTask { task.cancel() } else { model.cancelReview() }
            pause.resume(); await task.value
            assertUnknown(model); XCTAssertEqual(journal.value, original); XCTAssertEqual(service.reads, 1)
            journal.failClear = false
            await model.retryExact()
            XCTAssertEqual(service.requests, [original, original]); XCTAssertEqual(service.receipts.count, 1)
            XCTAssertNil(journal.value)
        }
    }
    func testCancelledSaveFailureDoesNotInventDurabilityOrReconstructMissingRecord() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model)
        let pause = Pause(expectation(description: "Save fails after navigation")); journal.beforeSave = pause; journal.failSave = true
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelReview(); pause.resume(); await task.value
        assertUnknown(model); XCTAssertNil(journal.value)
        await model.load(); await model.retryExact(); assertUnknown(model)
        XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertTrue(service.requests.isEmpty)
        XCTAssertEqual(journal.saves.count, 1); XCTAssertEqual(journal.clears, 0); XCTAssertEqual(service.reads, 1)
    }
    func testIdentityInvalidationDuringClearCannotReviveOldPresentation() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner)
        var current: PlayExperienceSession? = owner
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { current })
        try await prepare(model)
        let pause = Pause(expectation(description: "Clear across owner invalidation")); journal.beforeClear = pause
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        model.cancelReview(); current = nil; model.invalidate(); pause.resume(); await task.value
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.decision); XCTAssertNil(model.home)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.requests.count, 1)
    }
    func testAlreadyCancelledConfirmationDoesNotSaveOrConsumeReview() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model)
        let original = try XCTUnwrap(model.review)
        let task = Task { await model.confirm() }; task.cancel(); await task.value
        XCTAssertEqual(model.review, original); XCTAssertTrue(model.canConfirm)
        XCTAssertTrue(journal.saves.isEmpty); XCTAssertTrue(service.requests.isEmpty)
    }
    func testRefreshDuringCancelledUnfinishedSaveCannotUnlockOrAutoReplay() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model)
        let pause = Pause(expectation(description: "Unfinished save")); journal.beforeSave = pause
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        let original = try XCTUnwrap(journal.saves.first)
        model.cancelReview(); await model.load(); model.cancelReview(); assertUnknown(model)
        XCTAssertNil(journal.value); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(service.reads, 1)
        pause.resume(); await task.value
        XCTAssertEqual(journal.value, original); XCTAssertTrue(service.requests.isEmpty)
        await model.load(); assertUnknown(model)
        await model.retryExact(); XCTAssertEqual(service.requests, [original]); XCTAssertEqual(journal.saves, [original])
    }
    func testPreviousSuccessCannotLabelNewCancelledClearAsSuccessful() async throws {
        let owner = try owner(), service = Service(), journal = Journal(owner), model = model(service, journal, owner)
        try await prepare(model); await model.confirm()
        XCTAssertEqual(model.decision, .saved); XCTAssertEqual(model.phase, .ready)
        model.prepareSet(label: "Second explicit review", point: try .init(latitude: 13, longitude: 46))
        let pause = Pause(expectation(description: "Second request clear")); journal.beforeClear = pause; journal.failClear = true
        let task = Task { await model.confirm() }; defer { pause.resume(); task.cancel() }
        await fulfillment(of: [pause.entered], timeout: 1)
        XCTAssertNil(model.decision)
        let original = try XCTUnwrap(journal.value)
        model.cancelReview(); pause.resume(); await task.value
        assertUnknown(model); XCTAssertEqual(journal.value, original)
        XCTAssertEqual(service.requests.count, 2); XCTAssertEqual(service.reads, 2)
    }
}
