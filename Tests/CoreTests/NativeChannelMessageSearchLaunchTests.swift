import XCTest
@testable import QuestifyCore

@MainActor private final class LaunchSearchClient: NativeChannelMessageAccess {
    var identity: MessagingReadIdentity? = .init(accountID: 3, epoch: 1)
    var binding = try! NativeChannelMessageBinding(channelID: .init(rawValue: "9")!,
        conversationID: .init(rawValue: "9")!, mappingRevision: "mapping-1")
    var allowed = true
    var response: NativeChannelMessageSearchPage?
    var suspend = false
    var pending: [CheckedContinuation<NativeChannelMessageSearchPage, Error>] = []
    var requests: [(NativeChannelMessageQuery, String?)] = []
    var writes = 0
    func retireOperations() {}
    func allows(_ capability: NativeChannelMessageCapability) -> Bool { allowed && identity != nil }
    func search(_ query: NativeChannelMessageQuery, cursor: String?) async throws -> NativeChannelMessageSearchPage {
        requests.append((query, cursor))
        if suspend { return try await withCheckedThrowingContinuation { pending.append($0) } }
        guard let response else { throw APIError.malformedResponse }
        return response
    }
    func mutate(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageResult {
        writes += 1; throw APIError.notConfigured
    }
    func receipt(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageReceipt { throw APIError.notConfigured }
    func mutations(after: String) async throws -> NativeChannelMessageMutationPage { throw APIError.notConfigured }
    func pins() async throws -> NativeChannelMessagePinPage { throw APIError.notConfigured }
    func revisions(messageID: NativeChannelMessageID, cursor: Int64?) async throws -> NativeChannelMessageRevisionPage { throw APIError.notConfigured }
}

@MainActor final class NativeChannelMessageSearchLaunchTests: XCTestCase {
    private func page(_ ids: [String] = ["10", "9"], more: Bool = true,
                      conversation: String = "9", degraded: Bool = true) throws -> NativeChannelMessageSearchPage {
        var object: [String: Any] = ["list": ids.map { id in
            ["id": id, "conversationId": conversation, "version": 1, "status": 0,
             "msgType": 1, "content": "Search body \(id)"] as [String: Any]
        }, "has_more": more, "degraded": degraded, "oldest_searchable_at": "2026-09-01"]
        if more { object["next_cursor"] = ids.last }
        if degraded { object["degraded_reason"] = "RETENTION_BOUNDARY" }
        return try JSONDecoder().decode(NativeChannelMessageSearchPage.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    private func initial() async throws -> (LaunchSearchClient, NativeChannelMessageSearch) {
        let client = LaunchSearchClient()
        client.response = try page()
        let model = NativeChannelMessageSearch(client: client)
        await model.replace(.init(keyword: "original", from: "2026-09-01", to: "2026-11-04", authorID: .init(rawValue: "7")!))
        XCTAssertEqual(model.rows.count, 2)
        return (client, model)
    }

    private func awaitPending(_ client: LaunchSearchClient, count: Int = 1) async {
        for _ in 0..<1000 where client.pending.count < count { await Task.yield() }
        XCTAssertEqual(client.pending.count, count)
    }

    private func assertNoPayload(_ model: NativeChannelMessageSearch,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(model.rows.isEmpty, file: file, line: line)
        XCTAssertNil(model.query, file: file, line: line)
        XCTAssertNil(model.nextCursor, file: file, line: line)
        XCTAssertFalse(model.hasMore, file: file, line: line)
        XCTAssertNil(model.degradedReason, file: file, line: line)
        XCTAssertNil(model.oldestSearchableAt, file: file, line: line)
    }

    func testSameQueryPaginationUsesOriginalCursorAndKeepsDescendingResults() async throws {
        let (client, model) = try await initial()
        client.response = try page(["8", "7"], more: false, degraded: false)
        await model.more()
        XCTAssertEqual(model.rows.map(\.id.rawValue), ["10", "9", "8", "7"])
        XCTAssertEqual(client.requests.map { $0.1 }, [nil, "9"])
        XCTAssertEqual(client.requests[0].0, client.requests[1].0)
        XCTAssertEqual(model.degradedReason, "RETENTION_BOUNDARY")
        XCTAssertFalse(model.hasMore); XCTAssertNil(model.nextCursor)
        XCTAssertEqual(client.writes, 0)
    }

    func testRevocationHidesAllCachedSearchDataWithoutWaitingForAViewCallback() async throws {
        let (client, model) = try await initial()
        client.allowed = false
        XCTAssertFalse(model.isCurrent)
        assertNoPayload(model)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testChangedIdentityCannotExposeOrContinuePriorSearch() async throws {
        let (client, model) = try await initial()
        let originalIdentity = client.identity
        client.identity = .init(accountID: 4, epoch: 2)
        assertNoPayload(model)
        await model.more()
        XCTAssertEqual(client.requests.count, 1)
        client.identity = originalIdentity
        assertNoPayload(model)
    }

    func testChangedMappingRevisionCannotReuseSameAccountSearch() async throws {
        let (client, model) = try await initial()
        client.binding = try .init(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "mapping-2")
        XCTAssertFalse(model.isCurrent); assertNoPayload(model)
        await model.replace(.init(keyword: "new mapping"))
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(model.channelID, "9")
    }

    func testLateSuccessAfterRevocationErasesCachedAndPendingPayload() async throws {
        let (client, model) = try await initial()
        client.suspend = true
        let task = Task { await model.more() }
        await awaitPending(client)
        guard !client.pending.isEmpty else { task.cancel(); return }
        client.allowed = false
        client.pending.removeFirst().resume(returning: try page(["8"], more: false))
        await task.value
        client.allowed = true
        assertNoPayload(model)
        XCTAssertFalse(model.loading)
    }

    func testLateFailureAfterRevocationAlsoErasesTheOldPage() async throws {
        let (client, model) = try await initial()
        client.suspend = true
        let task = Task { await model.more() }
        await awaitPending(client)
        guard !client.pending.isEmpty else { task.cancel(); return }
        client.allowed = false
        client.pending.removeFirst().resume(throwing: APIError.unauthorized)
        await task.value
        client.allowed = true
        assertNoPayload(model)
        XCTAssertFalse(model.failed)
    }

    func testCancelledPaginationCannotLeaveAnEarlierPageCurrent() async throws {
        let (client, model) = try await initial()
        client.suspend = true
        let task = Task { await model.more() }
        await awaitPending(client)
        guard !client.pending.isEmpty else { task.cancel(); return }
        task.cancel()
        client.pending.removeFirst().resume(returning: try page(["8"], more: false))
        await task.value
        assertNoPayload(model)
        XCTAssertFalse(model.loading); XCTAssertFalse(model.failed)
    }

    func testCancelledFailureDoesNotPublishAnErrorForTheRetiredRequest() async throws {
        let (client, model) = try await initial()
        client.suspend = true
        let task = Task { await model.more() }
        await awaitPending(client)
        guard !client.pending.isEmpty else { task.cancel(); return }
        task.cancel()
        client.pending.removeFirst().resume(throwing: CancellationError())
        await task.value
        assertNoPayload(model)
        XCTAssertFalse(model.failed)
    }

    func testOlderFailedRequestCannotClearNewerSearchResults() async throws {
        let client = LaunchSearchClient()
        let controlled = NativeChannelMessageSearch(client: client)
        client.suspend = true
        let older = Task { await controlled.replace(.init(keyword: "old")) }
        await awaitPending(client)
        guard !client.pending.isEmpty else { older.cancel(); return }
        let oldResponse = client.pending.removeFirst()
        client.suspend = false; client.response = try page(["20"], more: false)
        await controlled.replace(.init(keyword: "new"))
        oldResponse.resume(throwing: APIError.malformedResponse)
        await older.value
        XCTAssertEqual(controlled.query?.keyword, "new")
        XCTAssertEqual(controlled.rows.map(\.id.rawValue), ["20"])
        XCTAssertFalse(controlled.failed)
    }

    func testMutationRefreshDropsPagesBeforeAwaitAndRetainsExactOriginalFilters() async throws {
        let (client, model) = try await initial()
        let original = model.query
        client.suspend = true
        let task = Task { await model.refreshOriginalQuery() }
        await awaitPending(client)
        guard !client.pending.isEmpty else { task.cancel(); return }
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(client.requests.last?.0, original)
        XCTAssertNil(client.requests.last?.1)
        client.pending.removeFirst().resume(returning: try page(["12"], more: false))
        await task.value
        XCTAssertEqual(model.rows.map(\.id.rawValue), ["12"])
        XCTAssertEqual(model.query, original)
        XCTAssertEqual(client.writes, 0)
    }

    func testInvalidQueryIsRejectedBeforeCallingAnyReader() async throws {
        let client = LaunchSearchClient()
        let controlled = NativeChannelMessageSearch(client: client)
        for query in [NativeChannelMessageQuery(keyword: " \n"), .init(keyword: String(repeating: "x", count: 101)),
                      .init(keyword: "valid", from: ""), .init(keyword: "valid", to: String(repeating: "x", count: 65))] {
            await controlled.replace(query)
            XCTAssertTrue(controlled.failed)
            assertNoPayload(controlled)
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testBadSecondPageFailsClosedButAllowsExplicitSameQueryRetry() async throws {
        let (client, model) = try await initial()
        let original = try XCTUnwrap(model.query)
        client.response = try page(["10"], more: false)
        await model.more()
        XCTAssertTrue(model.failed); XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.query, original)
        client.response = try page(["13"], more: false)
        await model.replace(original)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.rows.map(\.id.rawValue), ["13"])
        XCTAssertNil(client.requests.last?.1)
    }

    func testRetirementVetoesAnUncancelledLateResponse() async throws {
        let (client, model) = try await initial()
        client.suspend = true
        let task = Task { await model.more() }
        await awaitPending(client)
        guard !client.pending.isEmpty else { task.cancel(); return }
        model.retire()
        client.pending.removeFirst().resume(returning: try page(["8"], more: false))
        await task.value
        assertNoPayload(model); XCTAssertFalse(model.loading)
    }

    func testPageValidationRejectsMalformedOriginalCursorAndWrongConversation() throws {
        let client = LaunchSearchClient()
        let empty = try page([], more: false)
        for cursor in ["", "01", "-1", "1e2", "9223372036854775808"] {
            XCTAssertThrowsError(try empty.verify(binding: client.binding, requested: cursor))
        }
        XCTAssertNoThrow(try empty.verify(binding: client.binding, requested: "9"))
        XCTAssertThrowsError(try page(conversation: "99").verify(binding: client.binding, requested: nil))
    }
}
