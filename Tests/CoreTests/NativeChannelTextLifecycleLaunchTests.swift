import XCTest
@testable import QuestifyCore

/// Client lifetime tests. An injected receipt is not evidence that the frozen
/// backend supplies an original-send proof, or that the app is configured.
@MainActor final class NativeChannelTextLifecycleLaunchTests: XCTestCase {
    private struct Rig {
        let flow: NativeChannelTextCoordinator
        let access: LifecycleTextAccess
        let journal: NativeChannelTextJournal
        let storage: LifecycleTextStorage
        let reader: LifecycleTextHistory
    }
    private func rig(storage: LifecycleTextStorage? = nil) async throws -> Rig {
        let storage = storage ?? LifecycleTextStorage()
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!,
            role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "text-lifecycle-tests", token: "synthetic-token"))
        let scope = try NativeChannelTextScope(context: context, conversationID: 9)
        let reader = LifecycleTextHistory()
        let client = NativeChannelSessionClient(history: reader,
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_12"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: client)
        history.activate(); await history.load()
        let access = LifecycleTextAccess(scope: scope)
        let journal = NativeChannelTextJournal(storage: storage, scope: scope)
        let flow = try NativeChannelTextCoordinator(history: history, client: access, journal: journal)
        flow.activate()
        return Rig(flow: flow, access: access, journal: journal, storage: storage, reader: reader)
    }
    private func message(status: Int = 0) throws -> MessagingMessage {
        try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject: [
            "id": 42, "conversationId": 9, "senderId": 7, "status": status, "msgType": 1, "content": "原文 hello"
        ]))
    }
    private func awaitCount(_ count: Int, _ value: () -> Int) async throws {
        for _ in 0..<10_000 {
            if value() == count { return }
            await Task.yield()
        }
        XCTFail("The expected suspended operation did not start")
        throw APIError.notConfigured
    }
    private func pending(_ rig: Rig) async throws -> MessageTextIntent {
        rig.access.sendError = URLError(.timedOut)
        let result = await rig.flow.sendNew("原文 hello")
        XCTAssertFalse(result)
        return try XCTUnwrap(rig.journal.restore())
    }

    func testStoppedWriterReleasesRecoveryWithoutWaitingForItsCallback() async throws {
        let r = try await rig(); r.access.pauseSend = true
        let old = Task { await r.flow.sendNew("原文 hello") }
        try await awaitCount(1) { r.access.sends.count }
        let original = try XCTUnwrap(r.journal.restore())
        r.flow.stop(); r.flow.activate()
        XCTAssertTrue(r.flow.canCheckReceipt); XCTAssertFalse(r.flow.canRetryOriginal)
        let found = await r.flow.checkReceipt()
        XCTAssertFalse(found); XCTAssertEqual(r.access.reads, [original]); XCTAssertEqual(r.access.sends, [original])
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
        r.access.resumeSend(0, result: .success(try message()))
        let completed1 = await old.value; XCTAssertFalse(completed1)
    }

    func testNewHostCanReadSameOriginalWhileRetiredWriterIsStillSuspended() async throws {
        let first = try await rig(); first.access.pauseSend = true
        let old = Task { await first.flow.sendNew("原文 hello") }
        try await awaitCount(1) { first.access.sends.count }
        let original = try XCTUnwrap(first.journal.restore())
        first.flow.stop()
        let second = try await rig(storage: first.storage)
        XCTAssertEqual(second.flow.pendingClientMessageID, original.clientMessageID)
        _ = await second.flow.checkReceipt()
        XCTAssertEqual(second.access.reads, [original]); XCTAssertTrue(second.access.sends.isEmpty)
        first.access.resumeSend(0, result: .failure(URLError(.timedOut)))
        let completed2 = await old.value; XCTAssertFalse(completed2)
        XCTAssertTrue(NativeChannelTextJournal.same(try second.journal.restore(), original))
    }

    func testLateWriterCannotReleaseReplacementReadOrChangeItsState() async throws {
        let r = try await rig(); r.access.pauseSend = true
        let old = Task { await r.flow.sendNew("原文 hello") }
        try await awaitCount(1) { r.access.sends.count }
        let original = try XCTUnwrap(r.journal.restore())
        r.flow.stop(); r.flow.activate(); r.access.pauseReceipt = true
        let current = Task { await r.flow.checkReceipt() }
        try await awaitCount(1) { r.access.reads.count }
        r.access.resumeSend(0, result: .success(try message()))
        let completed3 = await old.value; XCTAssertFalse(completed3)
        XCTAssertEqual(r.flow.visibleState, .checkingReceipt); XCTAssertFalse(r.flow.canCheckReceipt)
        let other = try await rig(storage: r.storage)
        let completed4 = await other.flow.checkReceipt(); XCTAssertFalse(completed4); XCTAssertTrue(other.access.reads.isEmpty)
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
        r.access.resumeReceipt(0, result: .success(.init(kind: .unknown, displayWithheld: false)))
        let completed5 = await current.value; XCTAssertFalse(completed5)
        XCTAssertTrue(r.flow.canCheckReceipt); XCTAssertFalse(r.flow.canRetryOriginal)
    }

    func testLateFailedReadCannotOverwriteReplacementProofOrSettleNewOriginal() async throws {
        let r = try await rig(); _ = try await pending(r)
        r.access.pauseReceipt = true
        let old = Task { await r.flow.checkReceipt() }
        try await awaitCount(2) { r.access.reads.count }
        r.flow.stop(); r.flow.activate(); r.access.pauseReceipt = false
        r.access.confirmation = .init(kind: .applied(messageID: 42), displayWithheld: true)
        let completed6 = await r.flow.checkReceipt(); XCTAssertTrue(completed6); XCTAssertNil(try r.journal.restore())
        r.access.pauseSend = true; r.access.sendError = nil
        let next = Task { await r.flow.sendNew("second original") }
        try await awaitCount(2) { r.access.sends.count }
        let secondOriginal = try XCTUnwrap(r.journal.restore())
        r.access.resumeReceipt(1, result: .failure(URLError(.notConnectedToInternet)))
        let completed7 = await old.value; XCTAssertFalse(completed7)
        XCTAssertEqual(r.flow.visibleState, .sending); XCTAssertFalse(r.flow.canCheckReceipt)
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), secondOriginal))
        r.flow.stop(); r.access.resumeSend(1, result: .failure(CancellationError()))
        let completed8 = await next.value; XCTAssertFalse(completed8)
    }

    func testRetiredMissingReceiptCannotEnableRetryInNewLifetime() async throws {
        let r = try await rig(); _ = try await pending(r); r.access.pauseReceipt = true
        let old = Task { await r.flow.checkReceipt() }
        try await awaitCount(2) { r.access.reads.count }
        r.flow.stop(); r.flow.activate()
        r.access.pauseReceipt = false; r.access.confirmation = .init(kind: .unknown, displayWithheld: false)
        _ = await r.flow.checkReceipt()
        r.access.resumeReceipt(1, result: .success(.init(kind: .notFound, displayWithheld: false)))
        let completed9 = await old.value; XCTAssertFalse(completed9)
        XCTAssertEqual(r.flow.visibleState, .outcomeUnknown); XCTAssertFalse(r.flow.canRetryOriginal)
        XCTAssertEqual(r.access.sends.count, 1)
    }

    func testRepeatedStopDoesNotReleaseAnotherHostLease() async throws {
        let first = try await rig(); _ = try await pending(first); first.flow.stop()
        let second = try await rig(storage: first.storage); second.access.pauseReceipt = true
        let read = Task { await second.flow.checkReceipt() }
        try await awaitCount(1) { second.access.reads.count }
        first.flow.stop(); first.flow.activate()
        let completed10 = await first.flow.checkReceipt(); XCTAssertFalse(completed10); XCTAssertEqual(first.access.reads.count, 1)
        second.access.resumeReceipt(0, result: .success(.init(kind: .unknown, displayWithheld: false)))
        let completed11 = await read.value; XCTAssertFalse(completed11)
    }

    func testSynchronousStopAfterSendingStatePreventsWriterDispatch() async throws {
        let r = try await rig()
        r.flow.onChange = { if r.flow.visibleState == .sending { r.flow.stop() } }
        let completed12 = await r.flow.sendNew("原文 hello"); XCTAssertFalse(completed12)
        XCTAssertTrue(r.access.sends.isEmpty); XCTAssertTrue(r.access.reads.isEmpty)
        XCTAssertNotNil(try r.journal.restore())
        r.flow.onChange = nil; r.flow.activate(); XCTAssertTrue(r.flow.canCheckReceipt)
    }

    func testSynchronousStopAfterReadingStatePreventsReceiptDispatch() async throws {
        let r = try await rig(); let original = try await pending(r)
        r.flow.onChange = { if r.flow.visibleState == .checkingReceipt { r.flow.stop() } }
        let completed13 = await r.flow.checkReceipt(); XCTAssertFalse(completed13)
        XCTAssertEqual(r.access.reads, [original]); XCTAssertEqual(r.access.sends, [original])
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
    }

    func testReceiptGrantLossDropsSendAcknowledgmentAndRetainsOriginal() async throws {
        let r = try await rig(); r.access.pauseSend = true
        let task = Task { await r.flow.sendNew("原文 hello") }
        try await awaitCount(1) { r.access.sends.count }
        r.access.canReadReceipt = false
        r.access.resumeSend(0, result: .success(try message()))
        let completed14 = await task.value; XCTAssertFalse(completed14); XCTAssertNotNil(try r.journal.restore())
        XCTAssertEqual(r.flow.visibleState, .accessClosed); XCTAssertNil(r.flow.pendingText)
    }

    func testTerminalAccessInvalidationReleasesLeaseButCannotReopenOldHost() async throws {
        let r = try await rig(); r.access.pauseSend = true
        let task = Task { await r.flow.sendNew("原文 hello") }
        try await awaitCount(1) { r.access.sends.count }
        r.flow.accessInvalidated(); r.flow.activate()
        XCTAssertFalse(r.flow.canCheckReceipt); XCTAssertFalse(r.flow.canSendNew); XCTAssertNil(r.flow.pendingText)
        let lease = try XCTUnwrap(r.journal.beginOperation()); r.journal.endOperation(lease)
        r.access.resumeSend(0, result: .success(try message()))
        let completed15 = await task.value; XCTAssertFalse(completed15); XCTAssertNotNil(try r.journal.restore())
    }

    func testExplicitRetryAfterReturnUsesSameKeyAndBodyAndRechecksReceipt() async throws {
        let r = try await rig(); let original = try await pending(r)
        r.flow.stop(); r.flow.activate()
        XCTAssertFalse(r.flow.canRetryOriginal)
        _ = await r.flow.checkReceipt(); XCTAssertTrue(r.flow.canRetryOriginal)
        r.access.sendError = nil; r.access.sendResult = try message()
        let completed16 = await r.flow.retryOriginal(); XCTAssertTrue(completed16)
        XCTAssertEqual(r.access.sends, [original, original]); XCTAssertEqual(r.access.reads, [original, original, original])
        XCTAssertNil(try r.journal.restore()); XCTAssertTrue(r.flow.history.visibleMessages.isEmpty)
    }

    func testFrozen58FoundMessageWithoutOriginalProofRemainsUnknown() async throws {
        let r = try await rig(); let original = try await pending(r)
        r.access.confirmation = NativeChannelTextService.readOriginalSend([
            "found": true, "message": ["id": 42, "conversationId": 9, "senderId": 7,
                "clientMessageId": original.clientMessageID, "msgType": 1, "status": 0, "content": original.content]
        ], intent: original, accountID: 7)
        XCTAssertEqual(r.access.confirmation.kind, .unknown)
        let completed17 = await r.flow.checkReceipt(); XCTAssertFalse(completed17); XCTAssertFalse(r.flow.canRetryOriginal)
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), original))
        XCTAssertEqual(r.access.sends.count, 1)
    }

    func testWithheldVetoSurvivesStopButNotReaderIdentityReplacement() async throws {
        let r = try await rig(); r.access.sendResult = try message(status: 1)
        let completed18 = await r.flow.sendNew("原文 hello"); XCTAssertTrue(completed18); XCTAssertTrue(r.flow.isMessageWithheld(42))
        r.flow.stop(); r.flow.history.stop(); XCTAssertTrue(r.flow.isMessageWithheld(42))
        r.reader.identity = .init(accountID: 8, epoch: 2)
        XCTAssertFalse(r.flow.isMessageWithheld(42)); XCTAssertNil(r.flow.authoritativeMessage)
    }

    func testWithheldVetoRequiresConfiguredHistoryReader() async throws {
        let r = try await rig(); r.access.sendResult = try message(status: 2)
        let completed19 = await r.flow.sendNew("原文 hello"); XCTAssertTrue(completed19); XCTAssertTrue(r.flow.isMessageWithheld(42))
        r.reader.isConfigured = false
        XCTAssertFalse(r.flow.isMessageWithheld(42)); XCTAssertNil(r.flow.authoritativeMessage)
    }
}

@MainActor private final class LifecycleTextStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class LifecycleTextHistory: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false}"#.utf8))
    }
}
@MainActor private final class LifecycleTextAccess: NativeChannelTextAccess {
    let scope: NativeChannelTextScope
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var canReadReceipt = true, canSend = true, pauseSend = false, pauseReceipt = false
    var sends: [MessageTextIntent] = [], reads: [MessageTextIntent] = []
    var sendError: Error?, sendResult: MessagingMessage?
    var confirmation: NativeChannelOriginalSendRead = .init(kind: .notFound, displayWithheld: false)
    private var sendsWaiting: [Int: CheckedContinuation<MessagingMessage, Error>] = [:]
    private var readsWaiting: [Int: CheckedContinuation<NativeChannelOriginalSendRead, Error>] = [:]
    init(scope: NativeChannelTextScope) { self.scope = scope }
    func retireOperations() { } // Deliberately does not finish a suspended transport.
    func send(_ intent: MessageTextIntent) async throws -> MessagingMessage {
        let index = sends.count; sends.append(intent)
        if pauseSend { return try await withCheckedThrowingContinuation { sendsWaiting[index] = $0 } }
        if let sendError { throw sendError }
        guard let sendResult else { throw APIError.malformedResponse }; return sendResult
    }
    func receipt(_ intent: MessageTextIntent) async throws -> MessagingMessage? { XCTFail("Use original proof, not legacy body"); return nil }
    func confirmOriginal(_ intent: MessageTextIntent) async throws -> NativeChannelOriginalSendRead {
        let index = reads.count; reads.append(intent)
        if pauseReceipt { return try await withCheckedThrowingContinuation { readsWaiting[index] = $0 } }
        return confirmation
    }
    func resumeSend(_ index: Int, result: Result<MessagingMessage, Error>) {
        guard let continuation = sendsWaiting.removeValue(forKey: index) else { return XCTFail("Missing send continuation") }
        continuation.resume(with: result)
    }
    func resumeReceipt(_ index: Int, result: Result<NativeChannelOriginalSendRead, Error>) {
        guard let continuation = readsWaiting.removeValue(forKey: index) else { return XCTFail("Missing receipt continuation") }
        continuation.resume(with: result)
    }
}
