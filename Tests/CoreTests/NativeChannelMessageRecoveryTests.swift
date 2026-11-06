import XCTest
@testable import QuestifyCore

@MainActor private final class MessageRecoveryJournal: NativeChannelMessageMutationRecording {
    let scope: NativeChannelMessageScope
    var saved: NativeChannelMessageCommand?
    init(scope: NativeChannelMessageScope) { self.scope = scope }
    func acquire() throws -> UUID { UUID() }
    func release(_ lease: UUID) {}
    func restore() throws -> NativeChannelMessageCommand? { saved }
    func saveBeforeDispatch(_ command: NativeChannelMessageCommand) throws {
        if let saved, !NativeChannelMessageMutationJournal.sameBytes(saved, command) { throw NativeChannelMessageJournalError.pending }
        saved = command
    }
    func settle(_ command: NativeChannelMessageCommand) throws {
        if let saved, !NativeChannelMessageMutationJournal.sameBytes(saved, command) { throw NativeChannelMessageJournalError.pending }
        saved = nil
    }
}
@MainActor private final class MessageUnknownClient: NativeChannelMessageAccess {
    var identity: MessagingReadIdentity? = .init(accountID: 3, epoch: 1)
    let binding = try! NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "source")
    var mutationsSent = 0
    var receiptKeys: [String] = []
    func retireOperations() {}
    func allows(_ capability: NativeChannelMessageCapability) -> Bool { identity != nil }
    func mutate(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageResult {
        mutationsSent += 1; throw URLError(.timedOut)
    }
    func receipt(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageReceipt {
        receiptKeys.append(command.requestID)
        let object: [String: Any] = ["request_id":command.requestID,"state":"NOT_FOUND","outcome_confirmed":false]
        return try JSONDecoder().decode(NativeChannelMessageReceipt.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func mutations(after: String) async throws -> NativeChannelMessageMutationPage { throw APIError.notConfigured }
    func pins() async throws -> NativeChannelMessagePinPage { throw APIError.notConfigured }
    func search(_ query: NativeChannelMessageQuery, cursor: String?) async throws -> NativeChannelMessageSearchPage { throw APIError.notConfigured }
    func revisions(messageID: NativeChannelMessageID, cursor: Int64?) async throws -> NativeChannelMessageRevisionPage { throw APIError.notConfigured }
}
@MainActor final class NativeChannelMessageRecoveryTests: XCTestCase {
    func testTimeoutNotFoundResumeAndAnotherSubmitNeverResendOrReplaceKey() async throws {
        let client = MessageUnknownClient()
        let credentials = try NativeChannelMessageCredentials(identity: client.identity!, namespace: "unit-only", baseURL: URL(string: "https://example.com")!, binding: client.binding, authorityRevision: "source", token: "test-only-token")
        let journal = MessageRecoveryJournal(scope: .init(credentials: credentials))
        let flow = try NativeChannelMessageCoordinator(client: client, journal: journal, invalidateOriginalMessage: { _ in }, refreshOriginalHistory: {})
        await flow.activate()
        try flow.replacedHistory(cursor: "0", contract: "VISIBLE_ORDER_PLUS_MUTATIONS_V1", cacheAction: "RELOAD_ON_RESUME", rows: [])
        let original = try NativeChannelMessageCommand(operation: .edit, requestID: "original_request_0001", binding: client.binding, messageID: .init(rawValue: "8")!, expectedVersion: 1, content: "keep this draft")
        await flow.submit(original); XCTAssertEqual(flow.state, .unknown)
        await flow.recover()
        let replacement = try NativeChannelMessageCommand(operation: .edit, requestID: "replacement_key_0002", binding: client.binding, messageID: .init(rawValue: "8")!, expectedVersion: 1, content: "different draft")
        await flow.submit(replacement)
        flow.retire(); await flow.activate()
        XCTAssertEqual(client.mutationsSent, 1)
        XCTAssertTrue(client.receiptKeys.allSatisfy { $0 == original.requestID })
        XCTAssertGreaterThanOrEqual(client.receiptKeys.count, 3)
        XCTAssertEqual(journal.saved?.requestID, original.requestID)
        XCTAssertEqual(flow.draft, "keep this draft")
    }
}
