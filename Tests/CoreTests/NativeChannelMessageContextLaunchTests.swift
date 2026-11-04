import XCTest
@testable import QuestifyCore

@MainActor private final class LaunchContextClient: NativeChannelMessageAccess {
    var identity: MessagingReadIdentity? = .init(accountID: 3, epoch: 1)
    var binding = try! NativeChannelMessageBinding(channelID: .init(rawValue: "9")!,
        conversationID: .init(rawValue: "9")!, mappingRevision: "source")
    var contextAllowed = true
    var receiptAllowed = true
    var pending: [(NativeChannelMessageID, CheckedContinuation<NativeChannelMessageContextPage, Error>)] = []
    var mutationCount = 0
    var receiptCount = 0
    func retireOperations() {}
    func allows(_ capability: NativeChannelMessageCapability) -> Bool {
        guard identity != nil else { return false }
        return capability == .context ? contextAllowed : receiptAllowed
    }
    func context(messageID: NativeChannelMessageID) async throws -> NativeChannelMessageContextPage {
        try await withCheckedThrowingContinuation { pending.append((messageID, $0)) }
    }
    func mutate(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageResult {
        mutationCount += 1; throw APIError.notConfigured
    }
    func receipt(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageReceipt {
        receiptCount += 1; throw APIError.notConfigured
    }
    func mutations(after: String) async throws -> NativeChannelMessageMutationPage { throw APIError.notConfigured }
    func pins() async throws -> NativeChannelMessagePinPage { throw APIError.notConfigured }
    func search(_ query: NativeChannelMessageQuery, cursor: String?) async throws -> NativeChannelMessageSearchPage { throw APIError.notConfigured }
    func revisions(messageID: NativeChannelMessageID, cursor: Int64?) async throws -> NativeChannelMessageRevisionPage { throw APIError.notConfigured }
}

@MainActor final class NativeChannelMessageContextLaunchTests: XCTestCase {
    private func id(_ text: String) -> NativeChannelMessageID { .init(rawValue: text)! }
    private func decode<T: Decodable>(_ object: [String: Any], as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    private func row(_ id: String, conversation: String = "9", status: Int = 0, version: Int64 = 2) -> [String: Any] {
        ["id": id, "conversationId": conversation, "version": version, "status": status,
         "msgType": 1, "content": "current body \(id)"]
    }
    private func object(anchor: String = "8", version: Int64 = 2) -> [String: Any] {
        ["source": "original-channel-message-context-v1", "conversation_id": "9", "anchor_id": anchor,
         "anchor": row(anchor, version: version),
         "older": ["list": [row("7"), row("6")], "has_more": true, "next_cursor": "6"],
         "newer": ["list": [row("10"), row("11")], "has_more": true, "next_cursor": "11", "next_after": "11"]]
    }
    private func page(anchor: String = "8", version: Int64 = 2) throws -> NativeChannelMessageContextPage {
        try decode(object(anchor: anchor, version: version), as: NativeChannelMessageContextPage.self)
    }
    private func waitForRequest(_ client: LaunchContextClient, count: Int = 1) async -> Bool {
        for _ in 0..<1000 where client.pending.count < count { await Task.yield() }
        guard client.pending.count == count else { XCTFail("Controlled context request did not arrive"); return false }
        return true
    }
    private func open(_ model: NativeChannelMessageContext, client: LaunchContextClient) async throws {
        let task = Task { await model.open() }
        guard await waitForRequest(client) else { task.cancel(); return }
        client.pending.removeFirst().1.resume(returning: try page())
        await task.value
    }
    private func command(_ client: LaunchContextClient, operation: NativeChannelMessageOperation = .edit,
                         request: String = "original_request_0001") throws -> NativeChannelMessageCommand {
        try .init(operation: operation, requestID: request, binding: client.binding, messageID: id("8"),
                  expectedVersion: 1, content: operation == .edit ? "edited body" : nil)
    }
    private func receipt(_ command: NativeChannelMessageCommand, request: String? = nil,
                         redacted: Bool = false) throws -> NativeChannelMessageReceipt {
        var object: [String: Any] = ["request_id": request ?? command.requestID, "state": "APPLIED",
            "outcome_confirmed": true, "operation": command.operation.rawValue, "conversation_id": "9"]
        if redacted { object["result_redacted"] = true }
        else {
            var result: [String: Any] = ["message_id": "8", "conversation_id": "9", "version": 2, "changed": true]
            if command.operation == .edit { result["revision"] = 2 } else { result["status"] = 1 }
            object["result"] = result
        }
        return try decode(object, as: NativeChannelMessageReceipt.self)
    }
    func testValidBidirectionalCursorsAndAnchorAreRetained() async throws {
        let client = LaunchContextClient(), page = try page()
        XCTAssertNoThrow(try page.verify(binding: client.binding, anchor: id("8")))
        XCTAssertEqual(page.older.next_cursor, "6")
        XCTAssertEqual(page.newer.next_after, "11")
    }
    func testWrongSourceAnchorConversationAndDuplicateRowsAreRejected() async throws {
        let client = LaunchContextClient()
        for field in ["source", "anchor_id", "conversation_id", "anchor", "older"] {
            var bad = object()
            switch field {
            case "source": bad[field] = "search-summary"
            case "anchor_id": bad[field] = "7"
            case "conversation_id": bad[field] = "99"
            case "anchor": bad[field] = row("8", status: 1)
            default: bad[field] = ["list": [row("8")], "has_more": false]
            }
            let result = try decode(bad, as: NativeChannelMessageContextPage.self)
            XCTAssertThrowsError(try result.verify(binding: client.binding, anchor: id("8")), field)
        }
        var bad = object()
        bad["newer"] = ["list": [row("10", conversation: "99")], "has_more": false]
        let result = try decode(bad, as: NativeChannelMessageContextPage.self)
        XCTAssertThrowsError(try result.verify(binding: client.binding, anchor: id("8")))
    }
    func testEverySuppliedCursorIsValidatedIncludingOlderNextAfter() async throws {
        let client = LaunchContextClient()
        for side in ["older", "newer"] {
            for key in ["next_cursor", "next_after"] {
                for invalid in ["-1", "01", "9223372036854775808", "not-a-cursor"] {
                    var bad = object(), values = bad[side] as! [String: Any]
                    values[key] = invalid; bad[side] = values
                    let result = try decode(bad, as: NativeChannelMessageContextPage.self)
                    XCTAssertThrowsError(try result.verify(binding: client.binding, anchor: id("8")), "\(side).\(key)=\(invalid)")
                }
            }
        }
    }
    func testHasMoreRequiresUsableNavigationCursorForThatDirection() async throws {
        let client = LaunchContextClient()
        for (side, key) in [("older", "next_cursor"), ("newer", "next_after")] {
            for unusable in [NSNull(), "0", "8"] as [Any] {
                var bad = object(), values = bad[side] as! [String: Any]
                values[key] = unusable; bad[side] = values
                let result = try decode(bad, as: NativeChannelMessageContextPage.self)
                XCTAssertThrowsError(try result.verify(binding: client.binding, anchor: id("8")), "\(side).\(key)")
            }
        }
    }
    func testLaterAnchorWinsEvenWhenOlderRequestFinishesLast() async throws {
        let client = LaunchContextClient()
        let context = NativeChannelMessageContext(client: client, selected: id("8"))
        let old = Task { await context.open() }
        guard await waitForRequest(client) else { old.cancel(); return }
        let new = Task { await context.open(id("12")) }
        guard await waitForRequest(client, count: 2) else { old.cancel(); new.cancel(); return }
        client.pending.remove(at: 1).1.resume(returning: try page(anchor: "12")); await new.value
        client.pending.removeFirst().1.resume(returning: try page()); await old.value
        XCTAssertEqual(context.selected, id("12")); XCTAssertEqual(context.page?.anchor_id, id("12"))
        XCTAssertFalse(context.loading); XCTAssertFalse(context.failed)
    }
    func testRefreshRetainsCurrentPageOnlyWhileAuthorizedAndReading() async throws {
        let client = LaunchContextClient()
        let model = NativeChannelMessageContext(client: client, selected: id("8"))
        try await open(model, client: client)
        let refresh = Task { await model.refresh() }
        guard await waitForRequest(client) else { refresh.cancel(); return }
        XCTAssertEqual(model.page?.anchor.version, 2)
        client.pending.removeFirst().1.resume(returning: try page(version: 3)); await refresh.value
        XCTAssertEqual(model.page?.anchor.version, 3)
    }
    func testRevocationHidesCachedPageImmediatelyAndDropsPendingPayload() async throws {
        let client = LaunchContextClient()
        let context = NativeChannelMessageContext(client: client, selected: id("8"))
        try await open(context, client: client)
        let refresh = Task { await context.refresh() }
        guard await waitForRequest(client) else { refresh.cancel(); return }
        client.contextAllowed = false
        XCTAssertNil(context.page); XCTAssertNil(context.currentMessage(id: 8))
        client.pending.removeFirst().1.resume(returning: try page(version: 3)); await refresh.value
        client.contextAllowed = true
        XCTAssertNil(context.page); XCTAssertFalse(context.loading)
    }
    func testIdentityOrMappingChangeHidesCachedPageAndDiscardsPendingRead() async throws {
        for changeIdentity in [true, false] {
            let client = LaunchContextClient()
            let context = NativeChannelMessageContext(client: client, selected: id("8"))
            try await open(context, client: client)
            let refresh = Task { await context.refresh() }
            guard await waitForRequest(client) else { refresh.cancel(); continue }
            if changeIdentity { client.identity = .init(accountID: 3, epoch: 2) }
            else { client.binding = try .init(channelID: id("9"), conversationID: id("9"), mappingRevision: "replacement") }
            XCTAssertFalse(context.isCurrent); XCTAssertNil(context.page)
            client.pending.removeFirst().1.resume(returning: try page(version: 3)); await refresh.value
            XCTAssertNil(context.page); XCTAssertFalse(context.loading)
        }
    }
    func testCancellationAndFailureRemoveOldPageAfterRefreshCompletes() async throws {
        for cancel in [true, false] {
            let client = LaunchContextClient()
            let context = NativeChannelMessageContext(client: client, selected: id("8"))
            try await open(context, client: client)
            let refresh = Task { await context.refresh() }
            guard await waitForRequest(client) else { refresh.cancel(); continue }
            if cancel { refresh.cancel(); client.pending.removeFirst().1.resume(returning: try page(version: 3)) }
            else { client.pending.removeFirst().1.resume(throwing: URLError(.timedOut)) }
            await refresh.value
            XCTAssertNil(context.page); XCTAssertFalse(context.loading)
            XCTAssertEqual(context.failed, !cancel)
        }
    }
    func testRetirementInvalidatesAnInFlightAnchor() async throws {
        let client = LaunchContextClient()
        let context = NativeChannelMessageContext(client: client, selected: id("8"))
        let task = Task { await context.open() }
        guard await waitForRequest(client) else { task.cancel(); return }
        context.retire()
        client.pending.removeFirst().1.resume(returning: try page()); await task.value
        XCTAssertNil(context.page); XCTAssertFalse(context.loading); XCTAssertFalse(context.failed)
    }
    func testOnlyOriginalUUIDAppliedReceiptCanStartEditReadback() async throws {
        let client = LaunchContextClient()
        let model = NativeChannelMessageEditRecallReadback(client: client), command = try command(client)
        await model.observeApplied(command, receipt: try receipt(command, request: "replacement_key_0002"))
        XCTAssertNil(model.observation); XCTAssertTrue(client.pending.isEmpty)
        let applied = try receipt(command)
        let task = Task { await model.observeApplied(command, receipt: applied) }
        guard await waitForRequest(client) else { task.cancel(); return }
        XCTAssertEqual(client.pending.first?.0, command.messageID)
        client.pending.removeFirst().1.resume(returning: try page()); await task.value
        XCTAssertEqual(model.observation?.requestID, command.requestID)
        XCTAssertEqual(model.observation?.state, .visible(version: 2, atAppliedEditVersion: true))
        let retry = Task { await model.refresh() }
        guard await waitForRequest(client) else { retry.cancel(); return }
        client.pending.removeFirst().1.resume(returning: try page(version: 3)); await retry.value
        XCTAssertEqual(model.observation?.state, .visible(version: 3, atAppliedEditVersion: false))
        XCTAssertEqual(model.observation?.requestID, command.requestID)
        XCTAssertEqual(client.mutationCount, 0); XCTAssertEqual(client.receiptCount, 0)
    }
    func testRecallUnavailableIsOnlyAnObservationAndRetryPreservesProof() async throws {
        let client = LaunchContextClient()
        let command = try command(client, operation: .recall)
        let model = NativeChannelMessageEditRecallReadback(client: client)
        let applied = try receipt(command)
        let task = Task { await model.observeApplied(command, receipt: applied) }
        guard await waitForRequest(client) else { task.cancel(); return }
        client.pending.removeFirst().1.resume(throwing: NativeChannelMessageFailure(httpStatus: 404, code: 404,
            errorCode: "MESSAGE_CONTEXT_UNAVAILABLE", message: nil, outcomeKnown: nil)); await task.value
        XCTAssertEqual(model.observation?.state, .unavailable)
        XCTAssertEqual(model.observation?.appliedVersion, 2)
        let retry = Task { await model.refresh() }
        guard await waitForRequest(client) else { retry.cancel(); return }
        client.pending.removeFirst().1.resume(returning: try page(version: 3)); await retry.value
        XCTAssertEqual(model.observation?.state, .visible(version: 3, atAppliedEditVersion: false))
        XCTAssertEqual(model.observation?.requestID, command.requestID)
        XCTAssertEqual(client.mutationCount, 0)
    }
    func testReadbackBindingChangeClosesObservationAndBlocksFurtherReads() async throws {
        let client = LaunchContextClient()
        let command = try command(client)
        let model = NativeChannelMessageEditRecallReadback(client: client)
        let applied = try receipt(command)
        let task = Task { await model.observeApplied(command, receipt: applied) }
        guard await waitForRequest(client) else { task.cancel(); return }
        client.binding = try .init(channelID: id("9"), conversationID: id("9"), mappingRevision: "replacement")
        XCTAssertEqual(model.observation?.state, .accessClosed); XCTAssertFalse(model.canRefresh)
        client.pending.removeFirst().1.resume(returning: try page()); await task.value
        XCTAssertEqual(model.observation?.state, .accessClosed); XCTAssertFalse(model.refreshing)
        let retry = Task { await model.refresh() }
        for _ in 0..<100 { await Task.yield() }
        let extraReads = client.pending.count
        for (_, continuation) in client.pending { continuation.resume(throwing: APIError.notConfigured) }
        client.pending.removeAll()
        await retry.value
        XCTAssertEqual(extraReads, 0)
    }
    func testRedactedReceiptAndRevokedContextNeverExposeCurrentVersion() async throws {
        let client = LaunchContextClient()
        let command = try command(client)
        let model = NativeChannelMessageEditRecallReadback(client: client)
        await model.observeApplied(command, receipt: try receipt(command, redacted: true))
        XCTAssertNil(model.observation); XCTAssertTrue(client.pending.isEmpty)
        let applied = try receipt(command)
        let task = Task { await model.observeApplied(command, receipt: applied) }
        guard await waitForRequest(client) else { task.cancel(); return }
        client.contextAllowed = false
        client.pending.removeFirst().1.resume(returning: try page()); await task.value
        XCTAssertEqual(model.observation?.state, .accessClosed); XCTAssertFalse(model.canRefresh)
        client.receiptAllowed = false; XCTAssertNil(model.observation)
    }
}
