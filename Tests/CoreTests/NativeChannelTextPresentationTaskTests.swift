import XCTest
@testable import QuestifyCore

/// Presentation cancellation uses the original coordinator and protected journal.
/// Injected receipts below do not provide a production transport or type-5 grant.
@MainActor final class NativeChannelTextPresentationTaskTests: XCTestCase {
    func testCurrentCompletionReleasesSlotAndRunsOnce() async throws {
        let owner = NativeChannelTextPresentationTask()
        var calls = 0, results: [Bool] = []
        let task = try XCTUnwrap(owner.run(isCurrent: { true }, operation: {
            calls += 1; return true
        }, completion: { results.append($0) }))
        XCTAssertTrue(owner.isRunning)
        await task.value
        XCTAssertEqual(calls, 1); XCTAssertEqual(results, [true]); XCTAssertFalse(owner.isRunning)
    }

    func testDoubleTapDoesNotQueueAnotherOperation() async throws {
        let owner = NativeChannelTextPresentationTask(), waiting = TextPresentationSuspension()
        let first = try XCTUnwrap(owner.run(isCurrent: { true }, operation: { await waiting.run() }))
        var secondCalls = 0
        XCTAssertNil(owner.run(isCurrent: { true }, operation: { secondCalls += 1; return true }))
        await waiting.started.wait(for: 1); waiting.resume(true); await first.value
        XCTAssertEqual(secondCalls, 0); XCTAssertFalse(owner.isRunning)
    }

    func testCancelBeforeAdmissionNeverCallsOperationOrCompletion() async throws {
        let owner = NativeChannelTextPresentationTask()
        var calls = 0, completions = 0
        let task = try XCTUnwrap(owner.run(isCurrent: { true }, operation: {
            calls += 1; return true
        }, completion: { _ in completions += 1 }))
        owner.cancel(); await task.value
        XCTAssertEqual(calls, 0); XCTAssertEqual(completions, 0); XCTAssertFalse(owner.isRunning)
    }

    func testUnavailableAtAdmissionDropsActionAndReleasesSlot() async throws {
        let owner = NativeChannelTextPresentationTask()
        var calls = 0, completions = 0
        let task = try XCTUnwrap(owner.run(isCurrent: { false }, operation: {
            calls += 1; return true
        }, completion: { _ in completions += 1 }))
        await task.value
        XCTAssertEqual(calls, 0); XCTAssertEqual(completions, 0); XCTAssertFalse(owner.isRunning)
    }

    func testLateCompletionCannotClearNewDraftOrReplacementSlot() async throws {
        let owner = NativeChannelTextPresentationTask()
        let oldWaiting = TextPresentationSuspension(), newWaiting = TextPresentationSuspension()
        var draft = "old draft", completions: [Bool] = []
        let old = try XCTUnwrap(owner.run(isCurrent: { true }, operation: { await oldWaiting.run() },
            completion: { _ in draft = "" }))
        await oldWaiting.started.wait(for: 1)
        owner.cancel(); XCTAssertFalse(owner.isRunning); draft = "new draft"
        let current = try XCTUnwrap(owner.run(isCurrent: { true }, operation: { await newWaiting.run() },
            completion: { completions.append($0) }))
        await newWaiting.started.wait(for: 1)
        oldWaiting.resume(true); await old.value
        XCTAssertEqual(draft, "new draft"); XCTAssertTrue(owner.isRunning); XCTAssertTrue(completions.isEmpty)
        XCTAssertNil(owner.run(isCurrent: { true }, operation: { false }))
        newWaiting.resume(false); await current.value
        XCTAssertEqual(completions, [false]); XCTAssertFalse(owner.isRunning)
    }

    func testCurrentVetoAfterSuspensionDropsCompletionWithoutStrandingSlot() async throws {
        let owner = NativeChannelTextPresentationTask(), waiting = TextPresentationSuspension()
        var current = true, completions = 0
        let task = try XCTUnwrap(owner.run(isCurrent: { current }, operation: { await waiting.run() },
            completion: { _ in completions += 1 }))
        await waiting.started.wait(for: 1); current = false
        waiting.resume(true); await task.value
        XCTAssertEqual(completions, 0); XCTAssertFalse(owner.isRunning)
    }

    func testExternallyCancelledQueuedHandleAlsoReleasesItsOwnSlot() async throws {
        let owner = NativeChannelTextPresentationTask()
        var calls = 0
        let task = try XCTUnwrap(owner.run(isCurrent: { true }, operation: { calls += 1; return true }))
        task.cancel(); await task.value
        XCTAssertEqual(calls, 0); XCTAssertFalse(owner.isRunning)
    }

    func testCompletionMayStartNextActionWithoutOldDeferClearingIt() async throws {
        let owner = NativeChannelTextPresentationTask(), waiting = TextPresentationSuspension()
        var next: Task<Void, Never>?
        let first = try XCTUnwrap(owner.run(isCurrent: { true }, operation: { true }, completion: { _ in
            next = owner.run(isCurrent: { true }, operation: { await waiting.run() })
        }))
        await first.value
        let nextTask = try XCTUnwrap(next)
        await waiting.started.wait(for: 1); XCTAssertTrue(owner.isRunning)
        waiting.resume(true); await nextTask.value; XCTAssertFalse(owner.isRunning)
    }

    func testHistoryReturnRecoversOriginalBeforeCancelledWriterReturns() async throws {
        let r = try await rig(), owner = NativeChannelTextPresentationTask()
        r.access.pauseSend = true
        var draft = "original", oldCompletions = 0
        let old = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.sendNew("original") }, completion: { _ in draft = ""; oldCompletions += 1 }))
        await r.access.sendStarted.wait(for: 1)
        defer { r.access.resumeSend(.failure(CancellationError())) }
        let original = try XCTUnwrap(r.journal.restore())
        owner.cancel(); r.flow.stop(); r.flow.history.stop()
        r.flow.history.activate(); await r.flow.history.load(); r.flow.activate()
        draft = "returned draft"
        let recovery = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.checkReceipt() }))
        await recovery.value
        XCTAssertEqual(r.access.reads, [original]); XCTAssertEqual(r.access.sends, [original])
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
        XCTAssertFalse(r.flow.canRetryOriginal); XCTAssertEqual(r.flow.visibleState, .outcomeUnknown)
        r.access.resumeSend(.success(try message())); await old.value
        XCTAssertEqual(oldCompletions, 0); XCTAssertEqual(draft, "returned draft")
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
        XCTAssertFalse(r.flow.history.client.canReadThrough); XCTAssertFalse(r.flow.history.client.canLoadNewer)
    }

    func testOldReceiptCannotReleaseNewReceiptOrEnableRetry() async throws {
        let r = try await rig(), owner = NativeChannelTextPresentationTask()
        r.access.sendError = URLError(.timedOut)
        _ = await r.flow.sendNew("original")
        let original = try XCTUnwrap(r.journal.restore())
        r.access.pauseReceipt = true
        let old = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.checkReceipt() }))
        await r.access.receiptStarted.wait(for: 2)
        defer { r.access.resumeReceipt(1, .failure(CancellationError())); r.access.resumeReceipt(2, .failure(CancellationError())) }
        owner.cancel(); r.flow.stop(); r.flow.activate()
        let replacement = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.checkReceipt() }))
        await r.access.receiptStarted.wait(for: 3)
        r.access.resumeReceipt(1, .success(.init(kind: .notFound, displayWithheld: false)))
        await old.value
        XCTAssertTrue(owner.isRunning); XCTAssertEqual(r.flow.visibleState, .checkingReceipt)
        XCTAssertFalse(r.flow.canRetryOriginal); XCTAssertEqual(r.access.sends, [original])
        r.access.resumeReceipt(2, .success(.init(kind: .unknown, displayWithheld: false)))
        await replacement.value
        XCTAssertFalse(owner.isRunning); XCTAssertEqual(r.flow.visibleState, .outcomeUnknown)
        XCTAssertFalse(r.flow.canRetryOriginal); XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
    }

    func testIdentityLossVetoesLatePresentationAndRetainsProtectedOriginal() async throws {
        let r = try await rig(), owner = NativeChannelTextPresentationTask()
        r.access.pauseSend = true
        var completions = 0
        let task = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.sendNew("original") }, completion: { _ in completions += 1 }))
        await r.access.sendStarted.wait(for: 1)
        let original = try XCTUnwrap(r.journal.restore())
        r.access.identity = .init(accountID: 8, epoch: 2)
        r.access.resumeSend(.success(try message())); await task.value
        XCTAssertEqual(completions, 0); XCTAssertFalse(owner.isRunning); XCTAssertNil(r.flow.pendingText)
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
        XCTAssertEqual(r.access.sends, [original]); XCTAssertTrue(r.access.reads.isEmpty)
    }

    func testReturnReadsOnlyThenExplicitRetryKeepsOriginalKeyAndBody() async throws {
        let r = try await rig(), owner = NativeChannelTextPresentationTask()
        r.access.sendError = URLError(.timedOut)
        _ = await r.flow.sendNew("original")
        let original = try XCTUnwrap(r.journal.restore())
        owner.cancel(); r.flow.stop(); r.flow.activate()
        XCTAssertFalse(r.flow.canRetryOriginal)
        r.access.confirmation = .init(kind: .notFound, displayWithheld: false)
        let recovery = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.checkReceipt() }))
        await recovery.value
        XCTAssertEqual(r.access.sends, [original]); XCTAssertTrue(r.flow.canRetryOriginal)
        r.access.sendError = nil; r.access.sendResult = try message()
        let retry = try XCTUnwrap(owner.run(isCurrent: { r.flow.conversationReady },
            operation: { await r.flow.retryOriginal() }))
        await retry.value
        XCTAssertEqual(r.access.sends, [original, original]); XCTAssertEqual(r.access.reads, [original, original, original])
        XCTAssertNil(try r.journal.restore()); XCTAssertTrue(r.flow.history.visibleMessages.isEmpty)
    }

    private struct Rig {
        let flow: NativeChannelTextCoordinator
        let access: PresentationTextAccess
        let journal: NativeChannelTextJournal
    }
    private func rig() async throws -> Rig {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!,
            role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "text-presentation-tests", token: "synthetic-token"))
        let scope = try NativeChannelTextScope(context: context, conversationID: 9)
        let reader = PresentationTextHistory()
        let client = NativeChannelSessionClient(history: reader,
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_12"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: client)
        history.activate(); await history.load()
        let access = PresentationTextAccess(scope: scope)
        let journal = NativeChannelTextJournal(storage: PresentationTextStorage(), scope: scope)
        let flow = try NativeChannelTextCoordinator(history: history, client: access, journal: journal)
        flow.activate()
        return Rig(flow: flow, access: access, journal: journal)
    }
    private func message() throws -> MessagingMessage {
        try JSONDecoder().decode(MessagingMessage.self,
            from: Data(#"{"id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"original"}"#.utf8))
    }
}

@MainActor private final class TextPresentationSignal {
    private var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func wait(for target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { waiters.append((target, $0)) }
    }
    func hit() {
        count += 1
        let ready = waiters.filter { $0.0 <= count }; waiters.removeAll { $0.0 <= count }
        for (_, continuation) in ready { continuation.resume() }
    }
}
@MainActor private final class TextPresentationSuspension {
    let started = TextPresentationSignal()
    private var continuation: CheckedContinuation<Bool, Never>?
    func run() async -> Bool {
        await withCheckedContinuation { continuation = $0; started.hit() }
    }
    func resume(_ accepted: Bool) { let held = continuation; continuation = nil; held?.resume(returning: accepted) }
}
@MainActor private final class PresentationTextStorage: ProjectEditDataStorage {
    private var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class PresentationTextHistory: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false}"#.utf8))
    }
}
@MainActor private final class PresentationTextAccess: NativeChannelTextAccess {
    let scope: NativeChannelTextScope
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var canReadReceipt = true, canSend = true, pauseSend = false, pauseReceipt = false
    var sends: [MessageTextIntent] = [], reads: [MessageTextIntent] = []
    var sendError: Error?, sendResult: MessagingMessage?
    var confirmation: NativeChannelOriginalSendRead = .init(kind: .unknown, displayWithheld: false)
    let sendStarted = TextPresentationSignal(), receiptStarted = TextPresentationSignal()
    private var sendWaiting: CheckedContinuation<MessagingMessage, Error>?
    private var readsWaiting: [Int: CheckedContinuation<NativeChannelOriginalSendRead, Error>] = [:]
    init(scope: NativeChannelTextScope) { self.scope = scope }
    func retireOperations() {} // Model a transport that does not finish when cancelled.
    func send(_ intent: MessageTextIntent) async throws -> MessagingMessage {
        sends.append(intent); sendStarted.hit()
        if pauseSend { return try await withCheckedThrowingContinuation { sendWaiting = $0 } }
        if let sendError { throw sendError }
        guard let sendResult else { throw APIError.malformedResponse }; return sendResult
    }
    func receipt(_ intent: MessageTextIntent) async throws -> MessagingMessage? {
        XCTFail("Recovery must use the original proof, never a legacy message body"); return nil
    }
    func confirmOriginal(_ intent: MessageTextIntent) async throws -> NativeChannelOriginalSendRead {
        let index = reads.count; reads.append(intent); receiptStarted.hit()
        if pauseReceipt { return try await withCheckedThrowingContinuation { readsWaiting[index] = $0 } }
        return confirmation
    }
    func resumeSend(_ result: Result<MessagingMessage, Error>) {
        let held = sendWaiting; sendWaiting = nil; held?.resume(with: result)
    }
    func resumeReceipt(_ index: Int, _ result: Result<NativeChannelOriginalSendRead, Error>) {
        readsWaiting.removeValue(forKey: index)?.resume(with: result)
    }
}
