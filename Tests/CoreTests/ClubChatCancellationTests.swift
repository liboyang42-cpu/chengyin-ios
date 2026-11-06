import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class CancelChatClient: ClubChatServing {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true
    var requests: [Int] = []
    var send: () async throws -> Int = { 12 }
    func enter(clubID: Int, expectedIdentity: MessagingReadIdentity) async throws -> Int {
        requests.append(clubID); return try await send()
    }
}
@MainActor private final class CancelChatReader: ClubReading, MessagingReading {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true
    var isClubConfigured: Bool { isConfigured }
    var clubIdentity: ClubReadIdentity { .init(accountID: identity?.accountID, epoch: identity?.epoch ?? 0) }
    var beforeDetail: () async throws -> Void = {}
    var beforeMessages: () async throws -> Void = {}
    func clubDetail(id: Int) async throws -> ClubRecord {
        try await beforeDetail()
        return try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isJoined\":true}".utf8))
    }
    func messagingConversations() async throws -> [MessagingConversation] {
        try await beforeMessages()
        return [try JSONDecoder().decode(MessagingConversation.self, from: Data(#"{"conversationId":12,"type":4,"counterparty":{"bizKey":"club_81"}}"#.utf8))]
    }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { [] }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { [] }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
}
@MainActor final class ClubChatCancellationTests: XCTestCase {
    private func owner(_ client: CancelChatClient, _ reader: CancelChatReader) throws -> ClubChatCoordinator {
        try .init(clubID: 81, identity: .init(accountID: 7, epoch: 1), service: client, clubs: reader, messages: reader)
    }
    func testCancelledPreflightReturnsIdleWithoutDispatch() async throws {
        let client = CancelChatClient(), reader = CancelChatReader(), flow = try owner(client, reader)
        reader.beforeDetail = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await flow.enter() }; await task.value
        XCTAssertEqual(flow.visiblePhase, .idle); XCTAssertTrue(flow.canEnter); XCTAssertTrue(client.requests.isEmpty)
    }
    func testCancelledWriteSuccessOrFailureRemainsUnknownWithoutResend() async throws {
        for failing in [false, true] {
            let client = CancelChatClient(), reader = CancelChatReader(), flow = try owner(client, reader)
            client.send = {
                withUnsafeCurrentTask { $0?.cancel() }
                if failing { throw CancellationError() }; return 12
            }
            let task = Task { await flow.enter() }; await task.value
            XCTAssertEqual(flow.visiblePhase, .unknown); XCTAssertEqual(client.requests, [81])
        }
    }
    func testCancelledConversationReadDoesNotNavigateOrClaimFailure() async throws {
        let client = CancelChatClient(), reader = CancelChatReader(), flow = try owner(client, reader)
        reader.beforeMessages = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await flow.enter() }; await task.value
        XCTAssertEqual(flow.visiblePhase, .unknown); XCTAssertEqual(client.requests, [81])
    }
    func testOldCancelledCallCannotOverwriteNewGenerationReady() async throws {
        let client = CancelChatClient(), reader = CancelChatReader(), flow = try owner(client, reader)
        client.send = {
            flow.suspend()
            client.send = { 12 }
            await flow.enter()
            withUnsafeCurrentTask { $0?.cancel() }
            return 12
        }
        let task = Task { await flow.enter() }; await task.value
        guard case .ready(let row) = flow.visiblePhase else { return XCTFail("old cancellation replaced new result") }
        XCTAssertEqual(row.id, 12); XCTAssertEqual(client.requests, [81,81])
    }
    func testCancellationWithAccountReplacementStaysHidden() async throws {
        let client = CancelChatClient(), reader = CancelChatReader(), flow = try owner(client, reader)
        client.send = {
            client.identity = .init(accountID: 8, epoch: 2)
            reader.identity = .init(accountID: 8, epoch: 2)
            withUnsafeCurrentTask { $0?.cancel() }; return 12
        }
        let task = Task { await flow.enter() }; await task.value
        XCTAssertEqual(flow.visiblePhase, .stale); XCTAssertFalse(flow.canEnter); XCTAssertEqual(client.requests, [81])
    }
}
