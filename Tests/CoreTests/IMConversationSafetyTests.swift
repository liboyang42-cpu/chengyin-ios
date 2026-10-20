import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// w2-20: im/list delete and im/chat report/block/unblock. Writes need an exact
/// runtime grant, an explicit confirm, and unknown outcomes resolve by readback.
@MainActor final class IMConversationSafetyTests: XCTestCase {
    @MainActor private final class Reader: MessagingReading {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true
        var conversations: [[String: Any]] = [["conversationId": 9, "type": 1, "counterparty": ["id": 42]]]
        var blockedByMe: Bool? = false
        var conversationReads = 0
        func messagingConversations() async throws -> [MessagingConversation] {
            conversationReads += 1
            return try JSONDecoder().decode([MessagingConversation].self, from: JSONSerialization.data(withJSONObject: conversations))
        }
        func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
            var page: [String: Any] = ["list": [], "hasMore": false]
            if let blockedByMe { page["blocked"] = blockedByMe; page["blockedByMe"] = blockedByMe }
            return try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject: page))
        }
    }
    @MainActor private final class Writer: IMSafetyWriting {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var granted = true
        var failure: Error?
        var performed: [IMSafetyAction] = []
        var onPerform: ((IMSafetyAction) -> Void)?
        func permits(_ action: IMSafetyAction) -> Bool { granted }
        func perform(_ action: IMSafetyAction, expectedIdentity: MessagingReadIdentity) async throws {
            performed.append(action); onPerform?(action)
            if let failure { throw failure }
        }
    }
    private func owner(_ writer: Writer? = nil, _ reader: Reader? = nil) throws -> IMSafetyCoordinator {
        IMSafetyCoordinator(scope: try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 9), writer: writer ?? Writer(), reader: reader ?? Reader())
    }
    private func messages(_ json: String) throws -> [MessagingMessage] {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":\#(json),"hasMore":false}"#.utf8)).messages
    }

    func testActionsUseExactSourcePathsFieldsAndFeatures() throws {
        XCTAssertEqual(IMSafetyAction.hide(conversationID: 9).path, "api/im/delete")
        XCTAssertEqual(IMSafetyAction.hide(conversationID: 9).fields, ["conversation_id": "9"])
        XCTAssertEqual(IMSafetyAction.report(conversationID: 9, messageID: 31).fields, ["message_id": "31", "reason": "用户举报"])
        XCTAssertEqual(IMSafetyAction.block(conversationID: 9, targetMemberID: 42).fields, ["target_member_id": "42"])
        XCTAssertEqual(IMSafetyAction.unblock(conversationID: 9, targetMemberID: 42).path, "api/im/unblock")
        for action in [IMSafetyAction.hide(conversationID: 9), .report(conversationID: 9, messageID: 1),
                       .block(conversationID: 9, targetMemberID: 2), .unblock(conversationID: 9, targetMemberID: 2)] {
            XCTAssertTrue(action.feature.accepts(try .post(action.path)))
            XCTAssertFalse(action.feature.accepts(try .post("api/im/send")))
        }
        XCTAssertTrue(BusinessRuntimeFeature.imUnreadTotal.accepts(try .post("api/im/unread-total")))
    }
    func testReportTargetIsLatestPeerMessageOnly() throws {
        let list = try messages(#"[{"id":1,"conversationId":9,"status":0,"senderId":42},{"id":2,"conversationId":9,"status":0,"senderId":0},{"id":3,"conversationId":9,"status":0,"senderId":7},{"id":4,"conversationId":9,"status":1}]"#)
        XCTAssertEqual(IMSafetyAction.reportTarget(in: list, accountID: 7)?.id, 1)
        XCTAssertNil(IMSafetyAction.reportTarget(in: Array(list.dropFirst()), accountID: 7))
    }
    func testBlockTargetRequiresDirectRowWithAnotherMember() throws {
        let rows = try JSONDecoder().decode([MessagingConversation].self, from: Data(#"[{"conversationId":9,"type":1,"counterparty":{"id":42}},{"conversationId":10,"type":2,"counterparty":{"id":0}},{"conversationId":11,"type":1,"counterparty":{"id":7}},{"conversationId":12,"type":3,"counterparty":{"id":5}}]"#.utf8))
        XCTAssertEqual(IMSafetyAction.blockTarget(in: rows, conversationID: 9, accountID: 7), 42)
        XCTAssertNil(IMSafetyAction.blockTarget(in: rows, conversationID: 10, accountID: 7))
        XCTAssertNil(IMSafetyAction.blockTarget(in: rows, conversationID: 11, accountID: 7))
        XCTAssertNil(IMSafetyAction.blockTarget(in: rows, conversationID: 12, accountID: 7))
        XCTAssertNil(IMSafetyAction.blockTarget(in: rows, conversationID: 99, accountID: 7))
    }
    func testMenuAndReplyGateFollowSourceVariants() throws {
        let rows = try JSONDecoder().decode([MessagingConversation].self, from: Data(#"[{"conversationId":1,"type":2},{"conversationId":2,"type":1}]"#.utf8))
        XCTAssertEqual(IMSafetyMenu(conversation: rows[0], blockedByMe: nil).items, [.hide])
        XCTAssertEqual(IMSafetyMenu(conversation: rows[1], blockedByMe: false).items, [.report, .block, .hide])
        XCTAssertEqual(IMSafetyMenu(conversation: rows[1], blockedByMe: true).items, [.report, .unblock, .hide])
        XCTAssertEqual(IMReplyBlock.from(conversation: rows[0], page: nil, blockedByMe: nil), .systemNotice)
        XCTAssertNil(IMReplyBlock.from(conversation: rows[1], page: false, blockedByMe: false))
        XCTAssertNil(IMReplyBlock.from(conversation: rows[1], page: nil, blockedByMe: true))
        XCTAssertEqual(IMReplyBlock.from(conversation: rows[1], page: true, blockedByMe: true), .blockedByMe)
        XCTAssertEqual(IMReplyBlock.from(conversation: rows[1], page: true, blockedByMe: false), .peerUnavailable)
    }
    func testNothingDispatchesWithoutGrantOrConfirmation() async throws {
        let writer = Writer(); writer.granted = false
        let coordinator = try owner(writer)
        XCTAssertFalse(coordinator.review(.hide(conversationID: 9)))
        await coordinator.confirm()
        XCTAssertTrue(writer.performed.isEmpty)
        writer.granted = true
        XCTAssertFalse(coordinator.review(.hide(conversationID: 10)), "other conversation scope")
        XCTAssertTrue(coordinator.review(.hide(conversationID: 9)))
        XCTAssertTrue(writer.performed.isEmpty, "review alone never writes")
        coordinator.cancelReview()
        await coordinator.confirm()
        XCTAssertTrue(writer.performed.isEmpty)
    }
    func testConfirmedHideAcknowledges() async throws {
        let writer = Writer(); let coordinator = try owner(writer)
        XCTAssertTrue(coordinator.review(.hide(conversationID: 9)))
        await coordinator.confirm()
        XCTAssertEqual(writer.performed, [.hide(conversationID: 9)])
        XCTAssertEqual(coordinator.visibleState, .acknowledged(.hide(conversationID: 9)))
    }
    func testUnknownHideResolvesByConversationReadback() async throws {
        let writer = Writer(), reader = Reader()
        writer.failure = URLError(.networkConnectionLost)
        writer.onPerform = { _ in reader.conversations = [] }
        let coordinator = try owner(writer, reader)
        coordinator.review(.hide(conversationID: 9)); await coordinator.confirm()
        XCTAssertEqual(coordinator.visibleState, .outcomeUnknown(.hide(conversationID: 9)))
        XCTAssertFalse(coordinator.review(.hide(conversationID: 9)), "an unknown outcome cannot be replaced")
        await coordinator.verify()
        XCTAssertEqual(coordinator.visibleState, .acknowledged(.hide(conversationID: 9)))
        XCTAssertEqual(writer.performed.count, 1, "readback never resends")
    }
    func testUnknownHideStillVisibleIsNotApplied() async throws {
        let writer = Writer(); writer.failure = URLError(.timedOut)
        let coordinator = try owner(writer)
        coordinator.review(.hide(conversationID: 9)); await coordinator.confirm()
        await coordinator.verify()
        XCTAssertEqual(coordinator.visibleState, .notApplied(.hide(conversationID: 9)))
        writer.failure = nil
        await coordinator.retryUnchanged()
        XCTAssertEqual(writer.performed, [.hide(conversationID: 9), .hide(conversationID: 9)])
        XCTAssertEqual(coordinator.visibleState, .acknowledged(.hide(conversationID: 9)))
    }
    func testBlockResolvesPeerFromFreshReadAndVerifiesBlockedByMe() async throws {
        let writer = Writer(), reader = Reader()
        let coordinator = try owner(writer, reader)
        await coordinator.reviewBlock(unblock: false)
        XCTAssertEqual(reader.conversationReads, 1)
        XCTAssertEqual(coordinator.visibleState, .reviewing(.block(conversationID: 9, targetMemberID: 42)))
        writer.failure = URLError(.networkConnectionLost)
        writer.onPerform = { _ in reader.blockedByMe = true }
        await coordinator.confirm()
        await coordinator.verify()
        XCTAssertEqual(coordinator.visibleState, .acknowledged(.block(conversationID: 9, targetMemberID: 42)))
    }
    func testBlockWithoutDirectPeerIsUnavailable() async throws {
        let writer = Writer(), reader = Reader()
        reader.conversations = [["conversationId": 9, "type": 2, "counterparty": ["id": 0]]]
        let coordinator = try owner(writer, reader)
        await coordinator.reviewBlock(unblock: false)
        XCTAssertEqual(coordinator.visibleState, .unavailable(nil))
        XCTAssertTrue(writer.performed.isEmpty)
    }
    func testUnknownBlockWithoutBlockedFlagStaysUnknown() async throws {
        let writer = Writer(), reader = Reader()
        let coordinator = try owner(writer, reader)
        await coordinator.reviewBlock(unblock: true)
        writer.failure = URLError(.timedOut); reader.blockedByMe = nil
        await coordinator.confirm(); await coordinator.verify()
        XCTAssertEqual(coordinator.visibleState, .outcomeUnknown(.unblock(conversationID: 9, targetMemberID: 42)))
    }
    func testReportUnknownCannotBeVerifiedAndRejectedKeepsServerMessage() async throws {
        let writer = Writer(); writer.failure = URLError(.timedOut)
        let coordinator = try owner(writer)
        XCTAssertTrue(coordinator.reviewReport(messages: try messages(#"[{"id":5,"conversationId":9,"status":0,"senderId":42}]"#)))
        await coordinator.confirm(); await coordinator.verify()
        XCTAssertEqual(coordinator.visibleState, .outcomeUnknown(.report(conversationID: 9, messageID: 5)))
        writer.failure = MessagingReadFailure(code: 403, message: "无权操作")
        await coordinator.retryUnchanged()
        XCTAssertEqual(coordinator.visibleState, .rejected(.report(conversationID: 9, messageID: 5), message: "无权操作"))
        XCTAssertFalse(try owner(writer).reviewReport(messages: []))
    }
    func testAccountChangeHidesStateAndBlocksDispatch() async throws {
        let writer = Writer(), reader = Reader()
        let coordinator = try owner(writer, reader)
        coordinator.review(.hide(conversationID: 9))
        writer.identity = .init(accountID: 7, epoch: 2)
        XCTAssertEqual(coordinator.visibleState, .idle)
        await coordinator.confirm()
        XCTAssertTrue(writer.performed.isEmpty)
    }
    func testServiceSendsExactMultipartFieldsOnlyForGrantedPaths() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!)
        let transport = MessagingTestTransport([.json(#"{"code":200,"msg":"已拉黑"}"#), .json(#"{"code":500,"msg":"操作失败，请稍后重试"}"#)])
        let service = IMSafetyService(configuration: configuration, transport: transport, enabledPaths: ["api/im/block"])
        do { try await service.perform(.hide(conversationID: 9), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
        try await service.perform(.block(conversationID: 9, targetMemberID: 42), token: "synthetic-token")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/im/block")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.httpShouldHandleCookies)
        let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("name=\"target_member_id\"\r\n\r\n42"))
        do { try await service.perform(.block(conversationID: 9, targetMemberID: 42), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual((error as? MessagingReadFailure)?.code, 500) }
    }
    func testUnreadTotalDecodesSourceEnvelopeAndStaysDormantWithoutGrant() async throws {
        XCTAssertEqual(try IMUnreadTotalService.decode(Data(#"{"code":200,"data":12}"#.utf8)), 12)
        XCTAssertEqual(try IMUnreadTotalService.decode(Data(#"{"code":200,"data":null}"#.utf8)), 0)
        XCTAssertThrowsError(try IMUnreadTotalService.decode(Data(#"{"code":200,"data":-1}"#.utf8)))
        XCTAssertThrowsError(try IMUnreadTotalService.decode(Data(#"{"code":401}"#.utf8)))
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!)
        let transport = MessagingTestTransport([])
        let service = IMUnreadTotalService(configuration: configuration, transport: transport, enabledPaths: [])
        XCTAssertFalse(service.isConfigured)
        do { _ = try await service.total(token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
        let reader = IMUnreadTotalReader(service: nil, session: { nil })
        XCTAssertFalse(reader.isConfigured)
    }
}
