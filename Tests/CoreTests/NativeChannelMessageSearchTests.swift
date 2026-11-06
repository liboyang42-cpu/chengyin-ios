import XCTest
@testable import QuestifyCore

@MainActor private final class MessageSearchSuspendedClient: NativeChannelMessageAccess {
    var identity: MessagingReadIdentity? = .init(accountID: 3, epoch: 1)
    let binding = try! NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "source")
    var pending: [(String, CheckedContinuation<NativeChannelMessageSearchPage, Error>)] = []
    func retireOperations() {}
    func allows(_ capability: NativeChannelMessageCapability) -> Bool { identity != nil }
    func search(_ query: NativeChannelMessageQuery, cursor: String?) async throws -> NativeChannelMessageSearchPage {
        try await withCheckedThrowingContinuation { pending.append((query.keyword, $0)) }
    }
    func mutate(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageResult { throw APIError.notConfigured }
    func receipt(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageReceipt { throw APIError.notConfigured }
    func mutations(after: String) async throws -> NativeChannelMessageMutationPage { throw APIError.notConfigured }
    func pins() async throws -> NativeChannelMessagePinPage { throw APIError.notConfigured }
    func revisions(messageID: NativeChannelMessageID, cursor: Int64?) async throws -> NativeChannelMessageRevisionPage { throw APIError.notConfigured }
}
@MainActor final class NativeChannelMessageSearchTests: XCTestCase {
    private func page(_ text: String, id: String) throws -> NativeChannelMessageSearchPage {
        let object: [String: Any] = ["list":[["id":id,"conversationId":"9","version":1,"status":0,"msgType":1,"content":text]],
            "has_more":false,"degraded":true,"degraded_reason":"SHORT_KEYWORD_LIKE","oldest_searchable_at":"2026-09-23 00:00:00"]
        return try JSONDecoder().decode(NativeChannelMessageSearchPage.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testOlderQueryResponseCannotPolluteNewQuery() async throws {
        let client = MessageSearchSuspendedClient(), model = NativeChannelMessageSearch(client: client)
        let old = Task { await model.replace(.init(keyword: "old")) }
        for _ in 0..<100 where client.pending.count < 1 { await Task.yield() }
        let new = Task { await model.replace(.init(keyword: "new")) }
        for _ in 0..<100 where client.pending.count < 2 { await Task.yield() }
        guard client.pending.count == 2 else { XCTFail("Search did not reach the controlled transport"); old.cancel(); new.cancel(); return }
        client.pending[1].1.resume(returning: try page("new result", id: "7")); await new.value
        client.pending[0].1.resume(returning: try page("old result", id: "8")); await old.value
        XCTAssertEqual(model.query?.keyword, "new"); XCTAssertEqual(model.rows.map(\.content), ["new result"])
        XCTAssertEqual(model.degradedReason, "SHORT_KEYWORD_LIKE")
    }
    func testIdentityChangeDiscardsPendingSearchPayload() async throws {
        let client = MessageSearchSuspendedClient(), model = NativeChannelMessageSearch(client: client)
        let task = Task { await model.replace(.init(keyword: "query")) }
        for _ in 0..<100 where client.pending.isEmpty { await Task.yield() }
        guard let pending = client.pending.first else { XCTFail("Missing controlled request"); task.cancel(); return }
        client.identity = .init(accountID: 4, epoch: 2)
        pending.1.resume(returning: try page("former owner secret", id: "8")); await task.value
        XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.isCurrent)
    }
}
