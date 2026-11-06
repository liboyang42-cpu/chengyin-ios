import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelTextRecoveryTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, path: String = "native", namespace: String = "text-tests") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.test/\(path)")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "synthetic-token"))
    }
    private func intent(_ text: String = "hello", key: String = String(repeating: "a", count: 32)) throws -> MessageTextIntent {
        try .init(conversationID: 9, content: text, clientMessageID: key)
    }
    private func message(_ value: MessageTextIntent) throws -> MessagingMessage {
        try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject: [
            "id": 42, "conversationId": 9, "senderId": 7, "status": 0, "msgType": 1, "content": value.content
        ]))
    }
    private func rig(storage supplied: TextMemoryStorage? = nil, receiptAllowed: Bool = true) async throws -> (NativeChannelTextCoordinator, TextAccess, NativeChannelTextJournal, TextMemoryStorage) {
        let storage = supplied ?? TextMemoryStorage()
        let ctx = try context(), scope = try NativeChannelTextScope(context: ctx, conversationID: 9)
        let reader = TextHistoryReader(), client = NativeChannelSessionClient(history: reader,
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self, from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_12"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: client)
        history.activate(); await history.load()
        let access = TextAccess(scope: scope), journal = NativeChannelTextJournal(storage: storage, scope: scope)
        access.canReadReceipt = receiptAllowed
        let coordinator = try NativeChannelTextCoordinator(history: history, client: access, journal: journal)
        coordinator.activate(); return (coordinator, access, journal, storage)
    }
    func testProtectedJournalReconstructsSameIntentAndRejectsConcurrentNewIntent() throws {
        let storage = TextMemoryStorage(), scope = try NativeChannelTextScope(context: context(), conversationID: 9)
        let first = NativeChannelTextJournal(storage: storage, scope: scope), value = try intent()
        try first.saveBeforeDispatch(value)
        let cold = NativeChannelTextJournal(storage: storage, scope: scope)
        XCTAssertTrue(NativeChannelTextJournal.same(try cold.restore(), value))
        XCTAssertThrowsError(try cold.saveBeforeDispatch(intent("different")))
        XCTAssertThrowsError(try cold.settle(intent("different")))
        let lock = try XCTUnwrap(first.beginOperation()); XCTAssertNil(cold.beginOperation()); first.endOperation(lock)
        XCTAssertNotNil(cold.beginOperation().map { cold.endOperation($0); return true })
    }
    func testScopeSeparatesAccountDeploymentNamespaceButSurvivesNewLoginEpoch() throws {
        let storage = TextMemoryStorage(), first = NativeChannelTextJournal(storage: storage, scope: try .init(context: context(), conversationID: 9))
        try first.saveBeforeDispatch(intent())
        for ctx in [try context(account: 8), try context(path: "other"), try context(namespace: "other")] {
            XCTAssertNil(try NativeChannelTextJournal(storage: storage, scope: .init(context: ctx, conversationID: 9)).restore())
        }
        XCTAssertNotNil(try NativeChannelTextJournal(storage: storage, scope: .init(context: context(epoch: 2), conversationID: 9)).restore())
        XCTAssertNil(try NativeChannelTextJournal(storage: storage, scope: .init(context: context(), conversationID: 10)).restore())
    }
    func testByteDifferentUnicodePayloadCannotShareOriginalIntent() throws {
        let storage = TextMemoryStorage(), journal = NativeChannelTextJournal(storage: storage, scope: try .init(context: context(), conversationID: 9))
        try journal.saveBeforeDispatch(intent("\u{00e9}"))
        XCTAssertThrowsError(try journal.saveBeforeDispatch(intent("e\u{0301}")))
    }
    func testSaveFailureAndFailedReadbackBlockBeforeAnyDispatch() async throws {
        for failReadback in [false, true] {
            let (flow, access, _, storage) = try await rig()
            storage.failWrite = !failReadback; storage.failReadAfterWrite = failReadback
            let result = await flow.sendNew("hello")
            XCTAssertFalse(result); XCTAssertEqual(access.sends.count, 0); XCTAssertEqual(access.reads.count, 0)
            XCTAssertEqual(flow.visibleState, .persistenceFailed)
        }
    }
    func testTimeoutQueriesOriginalWithoutPostingAgainAndBlocksNewIntent() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut)
        let sent = await flow.sendNew("hello"), original = try XCTUnwrap(journal.restore())
        XCTAssertFalse(sent); XCTAssertEqual(access.sends, [original]); XCTAssertEqual(access.reads, [original])
        XCTAssertEqual(flow.visibleState, .outcomeUnknown); XCTAssertTrue(flow.canRetryOriginal)
        let replaced = await flow.sendNew("new message"); XCTAssertFalse(replaced); XCTAssertEqual(access.sends.count, 1)
    }
    func testExplicitRetryRechecksThenUsesSameKeyAndPayload() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        access.sendError = nil; access.sendResult = try message(original)
        let sent = await flow.retryOriginal()
        XCTAssertTrue(sent); XCTAssertEqual(access.sends, [original, original]); XCTAssertEqual(access.reads, [original, original])
        XCTAssertNil(try journal.restore()); XCTAssertTrue(flow.canSendNew)
        XCTAssertTrue(flow.history.visibleMessages.isEmpty) // no optimistic history row or read ACK
    }
    func testLateFoundBeforeExplicitRetryPreventsSecondPost() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        access.receiptResult = try message(XCTUnwrap(journal.restore()))
        let recovered = await flow.retryOriginal()
        XCTAssertTrue(recovered); XCTAssertEqual(access.sends.count, 1); XCTAssertNil(try journal.restore())
    }
    func testColdRestoreOnlyQueriesSameOriginalAndDoesNotSend() async throws {
        let storage = TextMemoryStorage(), scope = try NativeChannelTextScope(context: context(), conversationID: 9), value = try intent()
        try NativeChannelTextJournal(storage: storage, scope: scope).saveBeforeDispatch(value)
        let (flow, access, _, _) = try await rig(storage: storage)
        XCTAssertEqual(flow.pendingClientMessageID, value.clientMessageID); XCTAssertFalse(flow.canRetryOriginal)
        _ = await flow.checkReceipt()
        XCTAssertEqual(access.sends.count, 0); XCTAssertEqual(access.reads, [value]); XCTAssertTrue(flow.canRetryOriginal)
    }
    func testReceiptFailureNeverEnablesRetryOrNewIntent() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); access.receiptError = URLError(.notConnectedToInternet)
        _ = await flow.sendNew("hello")
        XCTAssertEqual(flow.visibleState, .receiptUnavailable); XCTAssertFalse(flow.canRetryOriginal); XCTAssertFalse(flow.canSendNew)
        _ = await flow.retryOriginal(); XCTAssertEqual(access.sends.count, 1); XCTAssertNotNil(try journal.restore())
    }
    func testDoubleClickAndConcurrentNewCoordinatorCannotDispatchDuringOriginal() async throws {
        let storage = TextMemoryStorage(), (flow, access, journal, _) = try await rig(storage: storage)
        access.pauseSend = true
        let original = Task { await flow.sendNew("hello") }
        while access.continuation == nil { await Task.yield() }
        let double = await flow.sendNew("hello"), other = try await rig(storage: storage)
        XCTAssertFalse(double); XCTAssertFalse(other.0.canSendNew)
        let retried = await other.0.checkReceipt(); XCTAssertFalse(retried); XCTAssertTrue(other.1.reads.isEmpty)
        access.continuation?.resume(throwing: URLError(.timedOut)); access.continuation = nil
        _ = await original.value; XCTAssertEqual(access.sends.count, 1); XCTAssertNotNil(try journal.restore())
    }
    func testLifecycleOrAccountChangeDropsLateResultButRetainsOriginal() async throws {
        for switchAccount in [false, true] {
            let (flow, access, journal, _) = try await rig(); access.pauseSend = true
            let original = Task { await flow.sendNew("hello") }
            while access.continuation == nil { await Task.yield() }
            let value = try XCTUnwrap(journal.restore())
            if switchAccount { access.identity = .init(accountID: 8, epoch: 2) } else { flow.stop() }
            access.continuation?.resume(returning: try message(value)); access.continuation = nil
            let result = await original.value
            XCTAssertFalse(result); XCTAssertNil(flow.pendingText); XCTAssertNotNil(try journal.restore()); XCTAssertEqual(access.reads.count, 0)
        }
    }
    func testDepartedOrClosedGroupBlocksRecoveryAndPreservesOriginal() async throws {
        for error in [MessagingReadFailure(code: 403), MessagingReadFailure(code: 409, errorCode: "IM_CONVERSATION_CLOSED")] {
            let (flow, access, journal, _) = try await rig(); access.sendError = error
            _ = await flow.sendNew("hello")
            XCTAssertEqual(flow.visibleState, .accessClosed); XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canSendNew)
            XCTAssertNotNil(try journal.restore()); XCTAssertEqual(access.reads.count, 0)
        }
    }
    func testCleanupFailureKeepsVerifiedReceiptAndBlocksNewIntent() async throws {
        let (flow, access, journal, storage) = try await rig(); access.sendError = URLError(.timedOut)
        _ = await flow.sendNew("hello"); let value = try XCTUnwrap(journal.restore())
        access.receiptResult = try message(value); storage.failRemove = true
        let result = await flow.checkReceipt()
        XCTAssertTrue(result); XCTAssertFalse(flow.canSendNew); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertNil(flow.pendingText); XCTAssertNotNil(try journal.restore())
        storage.failRemove = false; _ = await flow.checkReceipt(); XCTAssertNil(try journal.restore()); XCTAssertTrue(flow.canSendNew)
    }
    func testSecondRestoredScreenCanSettleAnAlreadyConfirmedOriginal() async throws {
        let storage = TextMemoryStorage(), (first, access, journal, _) = try await rig(storage: storage)
        access.sendError = URLError(.timedOut); _ = await first.sendNew("hello")
        let original = try XCTUnwrap(journal.restore()), (second, other, _, _) = try await rig(storage: storage)
        access.receiptResult = try message(original); other.receiptResult = try message(original)
        let firstResult = await first.checkReceipt(); XCTAssertTrue(firstResult); XCTAssertNil(try journal.restore())
        let secondResult = await second.checkReceipt(); XCTAssertTrue(secondResult)
        XCTAssertTrue(second.canSendNew); XCTAssertNil(second.pendingClientMessageID); XCTAssertTrue(other.sends.isEmpty)
    }
    func testAcknowledgedPayloadAlwaysReprojectsCurrentHistoryAndDisappearsAfterRecall() async throws {
        let (flow, access, _, _) = try await rig()
        access.sendResult = try message(intent())
        let sent = await flow.sendNew("hello")
        XCTAssertTrue(sent); XCTAssertEqual(flow.visibleState, .acknowledged(messageID: 42))
        XCTAssertNil(flow.authoritativeMessage) // receipt alone never installs a second message truth source
        let reader = try XCTUnwrap(flow.history.client.history as? TextHistoryReader)
        reader.pageJSON = #"{"list":[{"id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"hello"}],"hasMore":false}"#
        await flow.history.load(); XCTAssertEqual(flow.authoritativeMessage?.content, "hello")
        for status in [1, 2, 99] {
            reader.pageJSON = #"{"list":[{"id":42,"conversationId":9,"senderId":7,"status":STATUS,"msgType":1,"content":"withheld"}],"hasMore":false}"#.replacingOccurrences(of:"STATUS",with:String(status))
            await flow.history.load()
            XCTAssertNil(flow.authoritativeMessage?.content); XCTAssertNil(flow.pendingText)
            XCTAssertEqual(flow.visibleState, .acknowledged(messageID: 42))
        }
        reader.pageJSON = #"{"list":[],"hasMore":false}"#
        await flow.history.load(); XCTAssertNil(flow.authoritativeMessage)
    }
    func testNewerHiddenReceiptVetoesOlderNormalHistoryInBothDirections() async throws {
        for status in [1, 2, 99] {
            let (flow, access, _, _) = try await rig()
            let reader = try XCTUnwrap(flow.history.client.history as? TextHistoryReader)
            reader.pageJSON = #"{"list":[{"id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"old normal"}],"hasMore":false}"#
            await flow.history.load()
            access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
            access.receiptResult = try JSONDecoder().decode(MessagingMessage.self, from: Data(
                #"{"id":42,"conversationId":9,"status":STATUS,"content":"withheld"}"#.replacingOccurrences(of:"STATUS",with:String(status)).utf8))
            _ = await flow.checkReceipt()
            XCTAssertTrue(flow.receiptPayloadWithheld); XCTAssertTrue(flow.isMessageWithheld(42))
            XCTAssertNil(flow.authoritativeMessage); XCTAssertNil(flow.pendingText)
            // Even another stale normal history refresh cannot erase newer receipt evidence.
            await flow.history.load(); XCTAssertTrue(flow.isMessageWithheld(42)); XCTAssertNil(flow.authoritativeMessage)
            flow.stop(); flow.history.stop(); XCTAssertTrue(flow.isMessageWithheld(42))
            reader.identity = .init(accountID: 8, epoch: 2)
            XCTAssertFalse(flow.isMessageWithheld(42)); XCTAssertNil(flow.history.detailMessage(42))
        }
    }
    func testKnownReceiptCleanupFailureDoesNotRevealOriginalOnLifecycleReturn() async throws {
        let (flow, access, _, storage) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        access.receiptResult = try JSONDecoder().decode(MessagingMessage.self, from: Data(#"{"id":42,"conversationId":9,"status":1}"#.utf8))
        storage.failRemove = true; _ = await flow.checkReceipt()
        flow.stop(); flow.activate()
        XCTAssertNil(flow.pendingText); XCTAssertTrue(flow.isMessageWithheld(42)); XCTAssertFalse(flow.canSendNew)
    }
    func testAbsentReceiptGrantDoesNotRestoreOrDisplayProtectedOriginal() async throws {
        let storage = TextMemoryStorage(), scope = try NativeChannelTextScope(context: context(), conversationID: 9)
        try NativeChannelTextJournal(storage: storage, scope: scope).saveBeforeDispatch(intent())
        let readsBefore = storage.readCount
        let (flow, access, _, _) = try await rig(storage: storage, receiptAllowed: false)
        XCTAssertEqual(storage.readCount, readsBefore); XCTAssertNil(flow.pendingText); XCTAssertNil(flow.pendingClientMessageID)
        XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canSendNew)
        XCTAssertTrue(access.reads.isEmpty); XCTAssertTrue(access.sends.isEmpty)
    }
    func testMalformedMultipartMissingClosingQuoteOrEmptyNameRejectsWithoutTrap() throws {
        let base = try context().baseURL
        for malformed in ["Content-Disposition: form-data; name=\"\r\n\r\n9\r\n", "Content-Disposition: form-data; name=\"\"\r\n\r\n9\r\n"] {
            var request = URLRequest(url: base.appendingPathComponent("api/im/send"))
            request.httpMethod = "POST"; request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField:"Accept")
            request.setValue("multipart/form-data; boundary=malformed",forHTTPHeaderField:"Content-Type")
            request.httpBody = Data(("--malformed\r\n" + malformed + "--malformed--\r\n").utf8)
            XCTAssertNil(NativeChannelTextRoute(request: request, baseURL: base))
        }
    }
    func testReadAndWriteApprovalsAreIndependentDefaultClosedAndRevisionFenced() async throws {
        let ctx = try context(), raw = TextWireTransport()
        var read: NativeChannelTextApproval?, write: NativeChannelTextApproval?
        let closed = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, stillCurrent: { true })
        XCTAssertFalse(closed.allows(.send, conversationID: 9)); XCTAssertFalse(closed.allows(.receipt, conversationID: 9))
        read = try .init(context: ctx, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let t = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, read: { read }, write: { write }, stillCurrent: { true })
        XCTAssertTrue(t.allows(.receipt, conversationID: 9)); XCTAssertFalse(t.allows(.send, conversationID: 9)); XCTAssertFalse(t.allows(.receipt, conversationID: 10))
        write = try .init(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        XCTAssertFalse(t.allows(.send, conversationID: 9)) // issuance cannot reopen retained client
        read = try .init(context: ctx, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        XCTAssertFalse(t.allows(.receipt, conversationID: 9))
    }
    func testFinalDispatchRevocationAndLate401CannotExpireReplacementSession() async throws {
        for mode in ["revoke", "account", "viewer", "revision", "lifecycle"] {
            let ctx = try context(), raw = TextWireTransport(); var live: RuntimeDependencyContext? = ctx
            let grant = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
            var selected: NativeChannelTextApproval? = grant, viewer = true, unauthorized = 0
            let t = NativeChannelTextTransport(context: ctx, transport: raw, current: { live }, write: { selected }, stillCurrent: { viewer })
            let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: t, onUnauthorized: { _ in unauthorized += 1 })
            raw.hook = {
                switch mode {
                case "revoke": grant.revoke()
                case "account": live = try self.context(account: 8, epoch: 2)
                case "viewer": viewer = false
                case "lifecycle": client.retireOperations()
                default: selected = try .init(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
                }
            }
            raw.json = #"{"code":401}"#; raw.status = 401
            do { _ = try await client.send(intent()); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(unauthorized, 0); XCTAssertEqual(raw.requests.count, 1)
            if mode != "lifecycle" {
                do { _ = try await client.send(intent()); XCTFail() } catch { }
                XCTAssertEqual(raw.requests.count, 1)
            }
        }
    }
    func testCurrentUncancelled401PreservesOriginalUnauthorizedCallbackBeforeRetirement() async throws {
        let ctx = try context(), raw = TextWireTransport()
        let read = try NativeChannelTextApproval(context: ctx, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let write = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, read: { read }, write: { write }, stillCurrent: { true })
        var calls = 0
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport, onUnauthorized: { captured in
            XCTAssertEqual(captured, ctx); XCTAssertFalse(read.isRevoked); XCTAssertFalse(write.isRevoked)
            calls += 1
        })
        raw.status = 401
        do { _ = try await client.send(intent()); XCTFail("Unauthorized response accepted") } catch {}
        XCTAssertEqual(calls, 1); XCTAssertTrue(read.isRevoked); XCTAssertTrue(write.isRevoked)
        do { _ = try await client.send(intent()); XCTFail("Retired source reused") } catch {}
        XCTAssertEqual(calls, 1); XCTAssertEqual(raw.requests.count, 1)
    }
    func testActual401AfterCancellationRetiresOriginalApprovalsAndKeepsJournal() async throws {
        let ctx = try context(), raw = TextWireTransport(), value = try intent()
        let read = try NativeChannelTextApproval(context: ctx, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let write = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let memory = TextMemoryStorage(), journal = NativeChannelTextJournal(storage: memory, scope: try .init(context: ctx, conversationID: 9))
        try journal.saveBeforeDispatch(value); let originalBytes = memory.values
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, read: { read }, write: { write }, stillCurrent: { true })
        var sharedLogoutCalls = 0
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport, onUnauthorized: { _ in sharedLogoutCalls += 1 })
        raw.status = 401; raw.json = #"{"code":401}"#
        raw.hook = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { () -> Bool in
            do { _ = try await client.send(value); return true } catch { return false }
        }
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertTrue(read.isRevoked); XCTAssertTrue(write.isRevoked)
        XCTAssertEqual(sharedLogoutCalls, 0)
        XCTAssertEqual(raw.requests.count, 1); XCTAssertEqual(memory.values, originalBytes)
        XCTAssertTrue(NativeChannelTextJournal.same(try journal.restore(), value))
        XCTAssertFalse(client.canSend); XCTAssertFalse(client.canReadReceipt)
    }
    func testCancellationWithReturned200DoesNotRetireApprovalOrSettleOriginal() async throws {
        let ctx = try context(), raw = TextWireTransport(), value = try intent()
        let grant = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let memory = TextMemoryStorage(), journal = NativeChannelTextJournal(storage: memory, scope: try .init(context: ctx, conversationID: 9))
        try journal.saveBeforeDispatch(value); let originalBytes = memory.values
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, write: { grant }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport)
        raw.status = 200; raw.hook = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { () -> Bool in
            do { _ = try await client.send(value); return true } catch { return false }
        }
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertFalse(grant.isRevoked); XCTAssertTrue(client.canSend)
        XCTAssertEqual(raw.requests.count, 1); XCTAssertEqual(memory.values, originalBytes)
    }
    func testCancelledNetworkThrowIsNotAnUnauthorizedReceipt() async throws {
        let ctx = try context(), raw = TextWireTransport()
        let grant = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, write: { grant }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport)
        raw.status = 401 // No returned response: throwing must not infer this fixture value.
        raw.hook = { withUnsafeCurrentTask { $0?.cancel() }; throw URLError(.cancelled) }
        let value = try intent()
        let task = Task { () -> Bool in
            do { _ = try await client.send(value); return true } catch { return false }
        }
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertFalse(grant.isRevoked); XCTAssertEqual(raw.requests.count, 1)
    }
    func testLateOldIdentity401RetiresOnlyCapturedObjectsNotReplacementGrants() async throws {
        let ctx = try context(), next = try context(account: 8, epoch: 2), raw = TextWireTransport()
        let oldRead = try NativeChannelTextApproval(context: ctx, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let oldWrite = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let newRead = try NativeChannelTextApproval(context: next, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let newWrite = try NativeChannelTextApproval(context: next, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        var live = ctx, read = oldRead, write = oldWrite, sharedLogoutCalls = 0
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { live }, read: { read }, write: { write }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport, onUnauthorized: { _ in sharedLogoutCalls += 1 })
        raw.status = 401; raw.hook = { live = next; read = newRead; write = newWrite }
        do { _ = try await client.send(intent()); XCTFail("Old identity response was accepted") } catch {}
        XCTAssertTrue(oldRead.isRevoked); XCTAssertTrue(oldWrite.isRevoked)
        XCTAssertFalse(newRead.isRevoked); XCTAssertFalse(newWrite.isRevoked); XCTAssertEqual(sharedLogoutCalls, 0)
        XCTAssertTrue(newRead.matches(next, operation: .receipt, conversationID: 9))
        XCTAssertTrue(newWrite.matches(next, operation: .send, conversationID: 9))
    }
    func testLate401DoesNotRevokeReissuedSameIdentityApprovals() async throws {
        let ctx = try context(), raw = TextWireTransport()
        let old = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let replacement = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        var selected = old
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, write: { selected }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport)
        raw.status = 401; raw.hook = { selected = replacement }
        do { _ = try await client.send(intent()); XCTFail("Retired response accepted") } catch {}
        XCTAssertTrue(old.isRevoked); XCTAssertFalse(replacement.isRevoked)
        let fresh = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, write: { selected }, stillCurrent: { true })
        XCTAssertTrue(fresh.allows(.send, conversationID: 9))
        XCTAssertFalse(transport.allows(.send, conversationID: 9)); XCTAssertEqual(raw.requests.count, 1)
    }
    func testCancellationBeforeForwardDoesNotRetireCapturedApproval() async throws {
        let ctx = try context(), raw = TextWireTransport(), value = try intent()
        let grant = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        let transport = NativeChannelTextTransport(context: ctx, transport: raw, current: { ctx }, write: { grant }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport)
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await client.send(value); return true } catch { return false }
        }
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertFalse(grant.isRevoked); XCTAssertTrue(raw.requests.isEmpty)
    }
    func testReceiptValidatesOriginalSenderConversationKeyAndPayload() async throws {
        let value = try intent(), raw = TextWireTransport(), service = NativeChannelTextService(configuration: try .init(baseURL: context().baseURL), transport: raw)
        let good: [String: Any] = ["id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"hello","clientMessageId":value.clientMessageID]
        for (field, wrong) in [("senderId", 8 as Any), ("conversationId", 10 as Any), ("clientMessageId", String(repeating:"b",count:32) as Any), ("content", "other" as Any), ("msgType", 2 as Any)] {
            var message = good; message[field] = wrong
            raw.json = String(data: try JSONSerialization.data(withJSONObject: ["code":200,"data":["found":true,"message":message]]), encoding:.utf8)!
            do { _ = try await service.receipt(value, accountID:7, token:"synthetic-token"); XCTFail(field) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
        var hidden = good; hidden["status"] = 2
        raw.json = String(data: try JSONSerialization.data(withJSONObject: ["code":200,"data":["found":true,"message":hidden]]), encoding:.utf8)!
        let receipt = try await service.receipt(value, accountID:7, token:"synthetic-token")
        XCTAssertEqual(receipt?.status,.blocked); XCTAssertNil(receipt?.content)
    }
    func testRouteRejectsExtraFieldsCookiesDifferentOriginAndHistoryClassification() throws {
        let base = try context().baseURL, value = try intent("hello\nworld")
        var request = try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent("api/im/send"),fields:["conversation_id":"9","client_message_id":value.clientMessageID,"msg_type":"1","content":value.content],token:"synthetic-token")
        request.httpShouldHandleCookies = false
        XCTAssertEqual(NativeChannelTextRoute(request:request,baseURL:base),.send(value))
        XCTAssertNil(MessagingHistoryReadRoute(request:request,baseURL:base))
        for header in ["Cookie","Cookie2","Proxy-Authorization"] {
            var other = request; other.setValue("unapproved",forHTTPHeaderField:header)
            XCTAssertNil(NativeChannelTextRoute(request:other,baseURL:base))
        }
        var other = request; other.url = URL(string:"https://other.test/native/api/im/send")
        XCTAssertNil(NativeChannelTextRoute(request:other,baseURL:base))
        other = request; other.url = URL(string:base.appendingPathComponent("api/im/send").absoluteString+"?x=1")
        XCTAssertNil(NativeChannelTextRoute(request:other,baseURL:base))
        other = try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent("api/im/send"),fields:["conversation_id":"9","client_message_id":value.clientMessageID,"msg_type":"1","content":value.content,"target_member_id":"8"],token:"synthetic-token")
        other.httpShouldHandleCookies=false; XCTAssertNil(NativeChannelTextRoute(request:other,baseURL:base))
    }

    func testDigestMatchesOriginalFastjsonSendVector() throws {
        XCTAssertEqual(NativeChannelOriginalSendDigest.requestHash(content: "hello", conversationID: 9, replyToID: 0, memberIDs: [], roleIDs: [], mentionEveryone: false),
                       "d857aa89c49cc91416ee24a349e362237182d8e056db7eecc49ec1ada36ba7d2")
        let quoted = "他说\"你好\"\n下一行"
        XCTAssertEqual(NativeChannelOriginalSendDigest.requestHash(content: quoted, conversationID: 9, replyToID: 15, memberIDs: [8, 2, 8], roleIDs: [3, 1], mentionEveryone: false),
                       "6845f72f85f59d22d45569c721f15f0ed8c38df15c2c8679267e7037194d73b3")
        XCTAssertNil(NativeChannelOriginalSendDigest.requestHash(content: "<script>alert(1)</script>", conversationID: 9, replyToID: 0, memberIDs: [], roleIDs: [], mentionEveryone: false))
    }
    func testMissingAppliedStateDoesNotClearJournal() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        for state in [nil, "UNKNOWN"] {
            var body: [String: Any] = ["found": true, "original_send_proof": proof(original, hash: hash)]
            if let state { body["state"] = state }
            let parsed = NativeChannelTextService.readOriginalSend(body, intent: original, accountID: 7)
            XCTAssertEqual(parsed.kind, .unknown)
            access.confirmation = parsed
            let recovered = await flow.checkReceipt()
            XCTAssertFalse(recovered)
            XCTAssertNotNil(try journal.restore())
            XCTAssertFalse(flow.canRetryOriginal)
        }
    }
    func testUnavailableProofHidesOldHistoryBody() async throws {
        let (flow, access, journal, _) = try await rig()
        let reader = try XCTUnwrap(flow.history.client.history as? TextHistoryReader)
        reader.pageJSON = #"{"list":[{"id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"old hello"}],"hasMore":false}"#
        await flow.history.load()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        let body: [String: Any] = ["found": true, "state": "APPLIED",
                                   "message": ["message_unavailable": true],
                                   "original_send_proof": proof(original, hash: hash)]
        let parsed = NativeChannelTextService.readOriginalSend(body, intent: original, accountID: 7)
        guard case .applied(let id) = parsed.kind else { return XCTFail("applied") }
        XCTAssertEqual(id, 42)
        XCTAssertTrue(parsed.displayWithheld)
        access.confirmation = parsed
        let recovered = await flow.checkReceipt()
        XCTAssertTrue(recovered)
        XCTAssertNil(try journal.restore())
        XCTAssertTrue(flow.isMessageWithheld(42))
        XCTAssertNil(flow.authoritativeMessage)
    }
    func testMissingProofDoesNotSettleAMatchingDisplayMessage() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        access.receiptResult = try message(original)
        access.confirmation = NativeChannelOriginalSendRead(kind: .unknown, displayWithheld: false)
        let recovered = await flow.checkReceipt()
        XCTAssertFalse(recovered); XCTAssertNotNil(try journal.restore()); XCTAssertFalse(flow.canRetryOriginal)
    }
    func testAppliedProofSettlesWithoutADisplayMessage() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        access.receiptResult = nil
        access.confirmation = NativeChannelOriginalSendRead(kind: .applied(messageID: 42), displayWithheld: true)
        let recovered = await flow.checkReceipt()
        XCTAssertTrue(recovered); XCTAssertNil(try journal.restore()); XCTAssertEqual(flow.visibleState, .acknowledged(messageID: 42))
        XCTAssertTrue(flow.isMessageWithheld(42)); XCTAssertNil(flow.authoritativeMessage)
    }
    func testLegacyProofDoesNotClearJournal() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        access.confirmation = NativeChannelOriginalSendRead(kind: .legacy, displayWithheld: false)
        let recovered = await flow.checkReceipt()
        XCTAssertFalse(recovered); XCTAssertNotNil(try journal.restore()); XCTAssertFalse(flow.canRetryOriginal)
    }
    func testContradictoryNotFoundKeepsJournalAndDoesNotRetry() async throws {
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        let body: [String: Any] = ["found": false, "state": "NOT_FOUND",
                                   "message": ["id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": "old"],
                                   "original_send_proof": proof(original, hash: hash)]
        access.rawReceipt = body
        let recovered = await flow.checkReceipt()
        XCTAssertFalse(recovered)
        XCTAssertNotNil(try journal.restore())
        XCTAssertFalse(flow.canRetryOriginal)
    }
    func testStatusZeroWithoutDisplayableKindHidesOldHistory() async throws {
        let (flow, access, journal, _) = try await rig()
        let reader = try XCTUnwrap(flow.history.client.history as? TextHistoryReader)
        reader.pageJSON = #"{"list":[{"id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"old hello"}],"hasMore":false}"#
        await flow.history.load()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        let body: [String: Any] = ["found": true, "state": "APPLIED",
                                   "message": ["id": "42", "conversationId": "9", "status": 0],
                                   "original_send_proof": proof(original, hash: hash)]
        access.rawReceipt = body
        let recovered = await flow.checkReceipt()
        XCTAssertTrue(recovered)
        XCTAssertNil(try journal.restore())
        XCTAssertTrue(flow.isMessageWithheld(42))
        XCTAssertNil(flow.authoritativeMessage)
    }
    func testPlainReceiptThroughBridgeConfirmsAndShowsCurrentHistory() async throws {
        let (flow, access, journal, _) = try await rig()
        let reader = try XCTUnwrap(flow.history.client.history as? TextHistoryReader)
        reader.pageJSON = #"{"list":[{"id":42,"conversationId":9,"senderId":7,"status":0,"msgType":1,"content":"hello"}],"hasMore":false}"#
        await flow.history.load()
        access.sendError = URLError(.timedOut); _ = await flow.sendNew("hello")
        let original = try XCTUnwrap(journal.restore())
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        let body: [String: Any] = ["found": true, "state": "APPLIED",
                                   "message": ["id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": "hello"],
                                   "original_send_proof": proof(original, hash: hash)]
        access.rawReceipt = body
        let recovered = await flow.checkReceipt()
        XCTAssertTrue(recovered)
        XCTAssertNil(try journal.restore())
        XCTAssertFalse(flow.isMessageWithheld(42))
        XCTAssertEqual(flow.authoritativeMessage?.content, "hello")
    }
    func testReplyAndMentionsKeepTheSameRequest() async throws {
        let storage = TextMemoryStorage()
        let scope = try NativeChannelTextScope(context: context(), conversationID: 9)
        let conversation = try XCTUnwrap(NativeChannelMessageID(rawValue: "9"))
        let binding = try NativeChannelMessageBinding(channelID: conversation, conversationID: conversation, mappingRevision: "rev-1")
        let reference = try NativeChannelMessageTextReference(
            binding: binding,
            replyToID: NativeChannelMessageID(rawValue: "15"),
            memberIDs: [try XCTUnwrap(NativeChannelMessageID(rawValue: "8")), try XCTUnwrap(NativeChannelMessageID(rawValue: "2"))],
            roleIDs: [try XCTUnwrap(NativeChannelMessageID(rawValue: "3")), try XCTUnwrap(NativeChannelMessageID(rawValue: "1"))])
        let value = try MessageTextIntent(conversationID: 9, content: "他说\"你好\"\n下一行",
                                           clientMessageID: String(repeating: "b", count: 32), channelReference: reference)
        try NativeChannelTextJournal(storage: storage, scope: scope).saveBeforeDispatch(value)
        let (flow, access, journal, _) = try await rig(storage: storage)
        let original = try XCTUnwrap(journal.restore())
        XCTAssertEqual(original.clientMessageID, value.clientMessageID)
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        let body: [String: Any] = ["found": true, "state": "APPLIED",
                                   "message": ["id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": original.content],
                                   "original_send_proof": proof(original, hash: hash)]
        access.rawReceipt = body
        XCTAssertEqual((body["original_send_proof"] as? [String: Any])?["request_id"] as? String, value.clientMessageID)
        let recovered = await flow.checkReceipt()
        XCTAssertTrue(recovered)
        XCTAssertNil(try journal.restore())
    }
    func testRecordedBridgeChainRecoversReplyAndRejectsWrongChannel() async throws {
        let quoted = "他说\"你好\"\n下一行"
        let channel = try XCTUnwrap(NativeChannelMessageID(rawValue: "9"))
        let binding = try NativeChannelMessageBinding(channelID: channel, conversationID: channel, mappingRevision: "rev-1")
        let reference = try NativeChannelMessageTextReference(
            binding: binding, replyToID: NativeChannelMessageID(rawValue: "15"),
            memberIDs: [try XCTUnwrap(NativeChannelMessageID(rawValue: "8")), try XCTUnwrap(NativeChannelMessageID(rawValue: "2"))],
            roleIDs: [try XCTUnwrap(NativeChannelMessageID(rawValue: "3")), try XCTUnwrap(NativeChannelMessageID(rawValue: "1"))])
        let value = try MessageTextIntent(conversationID: 9, content: quoted, clientMessageID: String(repeating: "b", count: 32), channelReference: reference)
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(value))
        let mismatched: [String: Any] = ["found": true, "state": "APPLIED",
            "message": ["id": "42", "conversationId": "99", "status": 0, "msgType": 1, "content": "old"],
            "original_send_proof": proof(value, hash: hash)]
        let parsed = NativeChannelTextService.readOriginalSend(mismatched, intent: value, accountID: 7)
        guard case .applied(let kept) = parsed.kind else { return XCTFail("applied") }
        XCTAssertEqual(kept, 42)
        XCTAssertTrue(parsed.displayWithheld)
        let shown = try await recordedChain(intent: value, historyContent: quoted, receipt: [
            "found": true, "state": "APPLIED",
            "message": ["id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": quoted],
            "original_send_proof": proof(value, hash: hash)])
        XCTAssertTrue(shown.recovered)
        XCTAssertNil(try shown.journal.restore())
        XCTAssertEqual(shown.flow.authoritativeMessage?.content, quoted)
        XCTAssertEqual(shown.wire.requests.count, 1)
        XCTAssertTrue(shown.wire.requests[0].url?.path.hasSuffix("api/im/send-receipt") == true)
        XCTAssertTrue(String(data: shown.wire.requests[0].httpBody ?? Data(), encoding: .utf8)?.contains(value.clientMessageID) == true)
        let recalled = try await recordedChain(intent: value, historyContent: "old hello", receipt: [
            "found": true, "state": "APPLIED",
            "message": ["id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": "secret", "message_unavailable": true],
            "original_send_proof": proof(value, hash: hash)])
        XCTAssertTrue(recalled.recovered)
        XCTAssertNil(try recalled.journal.restore())
        XCTAssertTrue(recalled.flow.isMessageWithheld(42))
        XCTAssertNil(recalled.flow.authoritativeMessage)
        let wrong = try await recordedChain(intent: value, historyContent: "old hello", receipt: mismatched)
        XCTAssertFalse(wrong.recovered)
        XCTAssertNotNil(try wrong.journal.restore())
        XCTAssertNil(wrong.flow.authoritativeMessage)
        XCTAssertFalse(wrong.flow.canRetryOriginal)
        let contradiction = try await recordedChain(intent: value, historyContent: "old hello", receipt: [
            "found": false, "state": "NOT_FOUND",
            "message": ["id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": "old"],
            "original_send_proof": proof(value, hash: hash)])
        XCTAssertFalse(contradiction.recovered)
        XCTAssertNotNil(try contradiction.journal.restore())
        XCTAssertFalse(contradiction.flow.canRetryOriginal)
        let late = try await recordedChain(intent: value, historyContent: "old hello", receipt: ["code": 401], status: 401)
        XCTAssertFalse(late.recovered)
        XCTAssertNotNil(try late.journal.restore())
        XCTAssertTrue(late.read.isRevoked)
        XCTAssertEqual(late.flow.visibleState, .accessClosed)
        XCTAssertNil(late.flow.authoritativeMessage)
        for chain in [shown, recalled, wrong, contradiction, late] {
            XCTAssertFalse(chain.wire.requests.contains { $0.url?.path.hasSuffix("/api/im/send") == true })
        }
    }
    private struct RecordedChain {
        let flow: NativeChannelTextCoordinator
        let journal: NativeChannelTextJournal
        let wire: TextWireTransport
        let read: NativeChannelTextApproval
        let recovered: Bool
    }
    private func recordedChain(intent: MessageTextIntent, historyContent: String, receipt: [String: Any], status: Int = 200) async throws -> RecordedChain {
        let ctx = try context()
        let channel = try XCTUnwrap(NativeChannelMessageID(rawValue: "9"))
        let binding = try NativeChannelMessageBinding(channelID: channel, conversationID: channel, mappingRevision: "rev-1")
        let wire = TextWireTransport()
        let envelope: [String: Any] = status == 401 ? ["code": 401] : ["code": 200, "data": receipt]
        wire.json = String(data: try JSONSerialization.data(withJSONObject: envelope), encoding: .utf8) ?? "{}"
        wire.status = status
        let bridge = NativeChannelMessageOriginalWireBridge(binding: binding, configuration: try APIConfiguration(baseURL: ctx.baseURL),
            underlying: wire, current: { true })
        let read = try NativeChannelTextApproval(context: ctx, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        let write = try NativeChannelTextApproval(context: ctx, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        let transport = NativeChannelTextTransport(context: ctx, transport: bridge, current: { ctx }, read: { read }, write: { write }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: ctx, conversationID: 9, transport: transport)
        let reader = TextHistoryReader()
        let row: [String: Any] = ["id": 42, "conversationId": 9, "senderId": 7, "status": 0, "msgType": 1, "content": historyContent]
        reader.pageJSON = String(data: try JSONSerialization.data(withJSONObject: ["list": [row], "hasMore": false]), encoding: .utf8) ?? "{}"
        let session = NativeChannelSessionClient(history: reader, currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self, from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_12"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: session)
        history.activate(); await history.load()
        let storage = TextMemoryStorage()
        let journal = NativeChannelTextJournal(storage: storage, scope: client.scope)
        try journal.saveBeforeDispatch(intent)
        let flow = try NativeChannelTextCoordinator(history: history, client: client, journal: journal)
        flow.activate()
        let recovered = await flow.checkReceipt()
        return .init(flow: flow, journal: journal, wire: wire, read: read, recovered: recovered)
    }
    func testJSONSerializationRejectsBooleanNumbersAndKeepsExactIntegers() async throws {
        let original = try intent()
        let hash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(original))
        func parsed(_ fields: [String: Any]) throws -> NativeChannelOriginalSendRead {
            let data = try JSONSerialization.data(withJSONObject: fields)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return NativeChannelTextService.readOriginalSend(body, intent: original, accountID: 7)
        }
        let proofFields = proof(original, hash: hash)
        for found in [1, 0, "true", NSNull()] as [Any] {
            let read = try parsed(["found": found, "state": "APPLIED", "original_send_proof": proofFields])
            XCTAssertEqual(read.kind, .unknown)
        }
        var actor = proofFields
        actor["actor_member_id"] = true
        XCTAssertEqual(try parsed(["found": true, "state": "APPLIED", "original_send_proof": actor]).kind, .unknown)
        var channel = proofFields
        channel["conversation_id"] = false
        XCTAssertEqual(try parsed(["found": true, "state": "APPLIED", "original_send_proof": channel]).kind, .unknown)
        var message = proofFields
        message["message_id"] = true
        XCTAssertEqual(try parsed(["found": true, "state": "APPLIED", "original_send_proof": message]).kind, .unknown)
        var fractional = proofFields
        fractional["message_id"] = 1.5
        XCTAssertEqual(try parsed(["found": true, "state": "APPLIED", "original_send_proof": fractional]).kind, .unknown)
        var overflow = proofFields
        overflow["message_id"] = "9223372036854775808"
        XCTAssertEqual(try parsed(["found": true, "state": "APPLIED", "original_send_proof": overflow]).kind, .unknown)
        XCTAssertEqual(try parsed(["found": true, "state": "APPLIED"]).kind, .unknown)
        XCTAssertEqual(try parsed(["facade_metadata_confirmed": 0, "found": true, "state": "APPLIED", "original_send_proof": proofFields]).kind, .unknown)
        var one = proofFields
        one["message_id"] = 1
        let shown = try parsed(["found": true, "state": "APPLIED", "message": [
            "id": "1", "conversationId": "9", "status": 0, "msgType": 1, "content": original.content
        ], "original_send_proof": one])
        guard case .applied(let id) = shown.kind else { return XCTFail("applied") }
        XCTAssertEqual(id, 1)
        XCTAssertFalse(shown.displayWithheld)
        let hidden = try parsed(["found": true, "state": "APPLIED", "message": [
            "id": "42", "conversationId": "9", "status": false, "msgType": true, "content": "old"
        ], "original_send_proof": proofFields])
        guard case .applied = hidden.kind else { return XCTFail("withheld") }
        XCTAssertTrue(hidden.displayWithheld)
        let hiddenData = try JSONSerialization.data(withJSONObject: ["message": [
            "id": "42", "conversationId": "9", "status": false, "msgType": true, "content": "old"
        ]])
        let hiddenObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: hiddenData) as? [String: Any])
        let rewritten = NativeChannelMessageOriginalWireBridge.rewriteSendReceipt(hiddenObject)
        XCTAssertEqual((rewritten["message"] as? [String: Any])?["message_unavailable"] as? Bool, true)
        let illegalFlag = try parsed(["found": true, "state": "APPLIED", "message": [
            "id": "42", "conversationId": "9", "status": 0, "msgType": 1, "message_unavailable": 1, "content": "old"
        ], "original_send_proof": proofFields])
        XCTAssertTrue(illegalFlag.displayWithheld)
        for field in ["status", "msgType"] {
            var displayFields: [String: Any] = [
                "id": "42", "conversationId": "9", "status": 0, "msgType": 1, "content": "old"
            ]
            displayFields[field] = field == "status" ? "0" : "1"
            let stringState = try parsed(["found": true, "state": "APPLIED", "message": displayFields,
                                          "original_send_proof": proofFields])
            guard case .applied = stringState.kind else { return XCTFail("proof must remain valid") }
            XCTAssertTrue(stringState.displayWithheld)
            let wireData = try JSONSerialization.data(withJSONObject: ["message": displayFields])
            let wireObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: wireData) as? [String: Any])
            let rewritten = NativeChannelMessageOriginalWireBridge.rewriteSendReceipt(wireObject)
            let sparse = try XCTUnwrap(rewritten["message"] as? [String: Any])
            XCTAssertEqual(sparse["message_unavailable"] as? Bool, true)
            XCTAssertNil(sparse["content"])
        }
        let (flow, access, journal, _) = try await rig()
        access.sendError = URLError(.timedOut)
        _ = await flow.sendNew("hello")
        let saved = try XCTUnwrap(journal.restore())
        let savedHash = try XCTUnwrap(NativeChannelOriginalSendDigest.requestHash(saved))
        let raw = try JSONSerialization.data(withJSONObject: ["found": 1, "state": "APPLIED", "original_send_proof": proof(saved, hash: savedHash)])
        access.rawReceipt = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let recovered = await flow.checkReceipt()
        XCTAssertFalse(recovered)
        XCTAssertNotNil(try journal.restore())
        XCTAssertFalse(flow.canRetryOriginal)
    }
    private func proof(_ intent: MessageTextIntent, hash: String) -> [String: Any] {
        ["actor_member_id": "7", "conversation_id": "9", "request_id": intent.clientMessageID,
         "operation": "SEND", "request_hash": hash, "message_id": "42"]
    }
}

@MainActor private final class TextMemoryStorage: ProjectEditDataStorage {
    var values:[String:Data]=[:]
    var readCount = 0
    var failWrite=false, failRemove=false, failReadAfterWrite=false
    func read(_ key:String) throws -> Data? {
        readCount += 1
        if failReadAfterWrite && values[key] != nil { throw APIError.notConfigured }; return values[key]
    }
    func write(_ data:Data,key:String) throws { if failWrite { throw APIError.notConfigured }; values[key]=data }
    func remove(_ key:String) throws { if failRemove { throw APIError.notConfigured }; values[key]=nil }
}
@MainActor private final class TextHistoryReader: MessagingReading {
    var isConfigured=true
    var identity:MessagingReadIdentity? = .init(accountID:7,epoch:1)
    var pageJSON = #"{"list":[],"hasMore":false}"#
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID:Int,cursor:Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self,from:Data(pageJSON.utf8))
    }
}
@MainActor private final class TextAccess: NativeChannelTextAccess {
    let scope:NativeChannelTextScope
    var identity:MessagingReadIdentity? = .init(accountID:7,epoch:1)
    var canReadReceipt=true, canSend=true, pauseSend=false
    var sends:[MessageTextIntent]=[], reads:[MessageTextIntent]=[]
    var sendError:Error?, receiptError:Error?
    var sendResult:MessagingMessage?, receiptResult:MessagingMessage?
    var continuation:CheckedContinuation<MessagingMessage,Error>?
    init(scope:NativeChannelTextScope) { self.scope=scope }
    func retireOperations() { }
    func send(_ intent:MessageTextIntent) async throws -> MessagingMessage {
        sends.append(intent)
        if pauseSend { return try await withCheckedThrowingContinuation { continuation=$0 } }
        if let sendError { throw sendError }
        guard let sendResult else { throw APIError.malformedResponse }; return sendResult
    }
    func receipt(_ intent:MessageTextIntent) async throws -> MessagingMessage? {
        reads.append(intent); if let receiptError { throw receiptError }; return receiptResult
    }
    var confirmation: NativeChannelOriginalSendRead?
    var rawReceipt: [String: Any]?
    func confirmOriginal(_ intent: MessageTextIntent) async throws -> NativeChannelOriginalSendRead {
        reads.append(intent)
        if let receiptError { throw receiptError }
        if let rawReceipt {
            let rewritten = NativeChannelMessageOriginalWireBridge.rewriteSendReceipt(rawReceipt)
            return NativeChannelTextService.readOriginalSend(rewritten, intent: intent, accountID: scope.accountID)
        }
        if let confirmation { return confirmation }
        guard let receiptResult else { return NativeChannelOriginalSendRead(kind: .notFound, displayWithheld: false) }
        return NativeChannelOriginalSendRead(kind: .applied(messageID: receiptResult.id), displayWithheld: !receiptResult.isPayloadVisible)
    }
}
@MainActor private final class TextWireTransport: HTTPTransport {
    var requests:[URLRequest]=[]
    var json = #"{"code":200,"data":{"found":false,"message":null}}"#
    var status=200
    var hook:(() throws -> Void)?
    func send(_ request:URLRequest) async throws -> (Data,Int) {
        requests.append(request); try hook?(); return (Data(json.utf8),status)
    }
}
