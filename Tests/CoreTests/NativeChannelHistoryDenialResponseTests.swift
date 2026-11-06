import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Original /api/im/messages AjaxResult -> existing readers -> original history.
/// These tests inject no native service, type-5 mapping, read ACK or mutation grant.
@MainActor final class NativeChannelHistoryDenialResponseTests: XCTestCase {
    func testOriginal403EnvelopeRetiresLoadedHistoryAndRetryStartsLatest() async throws {
        try await assertTerminal(#"{"code":403,"msg":"操作失败，请稍后重试"}"#)
    }

    func testOriginalClosedGroupEnvelopeRetiresLoadedHistoryAndRetryStartsLatest() async throws {
        try await assertTerminal(#"{"code":409,"msg":"群聊已结束","errorCode":"IM_CONVERSATION_CLOSED"}"#)
    }

    func testExistingHangoutClosedEnvelopeKeepsTerminalRecovery() async throws {
        try await assertTerminal(#"{"code":409,"msg":"该组局已结束，聊天已关闭","errorCode":"HANGOUT_CLOSED","returnPath":"/subpackageB/pages/im/list/index"}"#,
                                 bizKey: "hangout_5")
    }

    func testGenericServerFailureKeepsSnapshotAndRetriesOriginalOlderCursor() async throws {
        try await assertTemporary(#"{"code":500,"msg":"操作失败，请稍后重试"}"#, status: 200)
    }

    func testUnrelatedConflictDoesNotPretendAccessWasWithdrawn() async throws {
        try await assertTemporary(#"{"code":409,"msg":"original conflict"}"#, status: 200)
    }

    func testHTTPServerFailureTakesPrecedenceOverTerminalEnvelopeMetadata() async throws {
        for body in [#"{"code":403,"msg":"temporary failure"}"#,
                     #"{"code":409,"errorCode":"IM_CONVERSATION_CLOSED"}"#] {
            try await assertTemporary(body, status: 503)
        }
    }

    func testIdentityChangeDuringDenialNeverExposesPreviousAccountHistory() async throws {
        let rig = try Rig(response: #"{"code":403,"msg":"操作失败，请稍后重试"}"#)
        rig.model.activate(); await rig.model.load()
        rig.transport.beforeReply = { if rig.transport.requests.count == 2 { rig.session.account = 2; rig.session.epoch = 2 } }
        await rig.model.older()
        XCTAssertFalse(rig.model.isCurrent); XCTAssertTrue(rig.model.visibleMessages.isEmpty)
        XCTAssertNil(rig.model.detailMessage(40)); XCTAssertNil(rig.model.failedOperation)
        let count = rig.transport.requests.count
        await rig.model.retry(); XCTAssertEqual(rig.transport.requests.count, count)
    }

    func testTypeFiveIsNotAdmittedAsOriginalTypeFourGroup() async throws {
        let rig = try Rig(response: #"{"code":200,"data":{"list":[],"hasMore":false}}"#, type: 5)
        XCTAssertNotEqual(rig.model.conversation.kind, .group)
        rig.model.activate(); XCTAssertNil(rig.model.prepare(.load)); await rig.model.load()
        XCTAssertTrue(rig.transport.requests.isEmpty); XCTAssertFalse(rig.model.loaded)
        XCTAssertTrue(NativeChannelSpace.project([rig.model.conversation]).isEmpty)
        XCTAssertFalse(rig.model.client.canReadThrough); XCTAssertFalse(rig.model.client.canLoadNewer)
    }

    private func assertTerminal(_ response: String, bizKey: String = "club_42") async throws {
        let rig = try Rig(response: response, bizKey: bizKey)
        rig.model.activate(); await rig.model.load(); rig.model.observed(40)
        XCTAssertEqual(rig.model.visibleMessages.map(\.id), [40]); XCTAssertNotNil(rig.model.detailMessage(40))
        await rig.model.older()
        XCTAssertTrue(rig.model.visibleMessages.isEmpty); XCTAssertNil(rig.model.detailMessage(40))
        XCTAssertFalse(rig.model.loaded); XCTAssertNil(rig.model.seenThrough); XCTAssertNil(rig.model.receipt)
        XCTAssertEqual(rig.model.failedOperation, .latest); XCTAssertNotNil(rig.model.issue)
        await rig.model.retry()
        XCTAssertEqual(rig.model.visibleMessages.map(\.id), [70]); XCTAssertNil(rig.model.failedOperation)
        XCTAssertTrue(rig.model.loaded); XCTAssertNil(rig.model.seenThrough); XCTAssertNil(rig.model.receipt)
        assertOriginalHistoryRequests(rig.transport.requests, cursors: [0, 17, 0])
        XCTAssertFalse(rig.model.client.canReadThrough); XCTAssertFalse(rig.model.client.canLoadNewer)
    }

    private func assertTemporary(_ response: String, status: Int) async throws {
        let rig = try Rig(response: response, status: status)
        rig.model.activate(); await rig.model.load(); rig.model.observed(40)
        await rig.model.older()
        XCTAssertEqual(rig.model.visibleMessages.map(\.id), [40]); XCTAssertNotNil(rig.model.detailMessage(40))
        XCTAssertTrue(rig.model.loaded); XCTAssertEqual(rig.model.seenThrough, 40)
        XCTAssertEqual(rig.model.failedOperation, .older(17))
        await rig.model.retry()
        XCTAssertNil(rig.model.failedOperation)
        assertOriginalHistoryRequests(rig.transport.requests, cursors: [0, 17, 17])
    }

    private func assertOriginalHistoryRequests(_ requests: [URLRequest], cursors: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(requests.count, cursors.count, file: file, line: line)
        for (request, cursor) in zip(requests, cursors) {
            XCTAssertEqual(request.url?.path, "/api/im/messages", file: file, line: line)
            XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token", file: file, line: line)
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertTrue(body.contains("name=\"conversation_id\"\r\n\r\n9\r\n"), file: file, line: line)
            XCTAssertTrue(body.contains("name=\"cursor_id\"\r\n\r\n\(cursor)\r\n"), file: file, line: line)
            XCTAssertFalse(body.contains("name=\"after_id\""), file: file, line: line)
            XCTAssertFalse(body.contains("name=\"read_to\""), file: file, line: line)
        }
    }

    @MainActor private struct Rig {
        let session: DenialHistorySession
        let transport: DenialHistoryTransport
        let model: NativeChannelHistoryModel
        init(response: String, status: Int = 200, bizKey: String = "club_42", type: Int = 4) throws {
            let session = DenialHistorySession(); self.session = session
            let first = #"{"code":200,"data":{"list":[{"id":40,"conversationId":9,"status":0,"msgType":1,"content":"old authorized row"}],"nextCursor":17,"hasMore":true}}"#
            let latest = #"{"code":200,"data":{"list":[{"id":70,"conversationId":9,"status":0,"msgType":1,"content":"fresh authorized row"}],"hasMore":false}}"#
            let transport = DenialHistoryTransport([(first, 200), (response, status), (latest, 200)])
            self.transport = transport
            let service = MessagingService(configuration: try .init(baseURL: URL(string: "https://example.test/")!), transport: transport)
            let reader = MessagingSessionReader(service: service, currentSession: {
                try? .init(accountID: session.account, epoch: session.epoch, token: "synthetic-token")
            })
            let client = NativeChannelSessionClient(history: reader, currentSession: {
                try? .init(accountID: session.account, epoch: session.epoch, token: "synthetic-token")
            }, isAvailable: { true })
            let conversation = try JSONDecoder().decode(MessagingConversation.self, from: JSONSerialization.data(withJSONObject: [
                "conversationId": 9, "type": type, "counterparty": ["bizKey": bizKey]
            ]))
            model = NativeChannelHistoryModel(conversation: conversation, client: client)
        }
    }
}

@MainActor private final class DenialHistorySession {
    var account = 1
    var epoch: UInt64 = 1
}
@MainActor private final class DenialHistoryTransport: HTTPTransport {
    private var responses: [(String, Int)]
    private(set) var requests: [URLRequest] = []
    var beforeReply: (() -> Void)?
    init(_ responses: [(String, Int)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?()
        guard !responses.isEmpty else { throw APIError.malformedResponse }
        let next = responses.removeFirst(); return (Data(next.0.utf8), next.1)
    }
}
