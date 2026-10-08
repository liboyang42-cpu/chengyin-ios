import Foundation
import XCTest
@testable import QuestifyCore

final class IMConversationReplyPolicyTests: XCTestCase {
    private func row(_ type: Int?, id: Int = 9) throws -> MessagingConversation {
        try JSONDecoder().decode(MessagingConversation.self,
            from: Data("{\"conversationId\":\(id),\"type\":\(type.map(String.init) ?? "null")}".utf8))
    }
    func testSystemNoticeCannotReplyButReadAndMuteStayAvailable() throws {
        let policy = IMConversationReplyPolicy(conversationID: 9, conversation: try row(2))
        XCTAssertTrue(policy.isSystemNotice); XCTAssertFalse(policy.permitsReply)
        XCTAssertTrue(policy.permits(.read(conversationID: 9)))
        XCTAssertTrue(policy.permits(.mute(conversationID: 9, muted: true)))
        XCTAssertTrue(policy.permits(.mute(conversationID: 9, muted: false)))
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 9)
        let payloads: [IMOutgoingPayload] = [.route(topicID: 11), .image(URL(string: "https://example.test/a.jpg")!),
            .location(name: "A", address: "B", latitude: 0, longitude: 0)]
        for payload in payloads { XCTAssertFalse(policy.permits(.send(try IMOutgoingIntent(scope: scope, payload: payload)))) }
    }
    func testOtherKindsContinueToUseExistingWriterAndHistoryGates() throws {
        for type in [1, 3, 4, 99, nil] as [Int?] {
            let policy = IMConversationReplyPolicy(conversationID: 9, conversation: try row(type))
            XCTAssertFalse(policy.isSystemNotice); XCTAssertTrue(policy.permitsReply)
        }
    }
    func testNewlyStartedConversationWithoutMetadataKeepsExistingFlow() {
        let policy = IMConversationReplyPolicy(conversationID: 9, conversation: nil)
        XCTAssertTrue(policy.permitsReply); XCTAssertFalse(policy.isSystemNotice)
    }
    func testMismatchedAndInvalidConversationCannotBorrowSystemOrReplyAuthority() throws {
        for policy in [IMConversationReplyPolicy(conversationID: 0, conversation: nil),
                       IMConversationReplyPolicy(conversationID: 9, conversation: try row(2, id: 10))] {
            XCTAssertFalse(policy.permitsReply); XCTAssertFalse(policy.isValidConversation)
            XCTAssertFalse(policy.permits(.read(conversationID: 9)))
        }
    }
    func testCrossConversationAndStartNeverUseThisPolicy() throws {
        let policy = IMConversationReplyPolicy(conversationID: 9, conversation: try row(1))
        XCTAssertFalse(policy.permits(.read(conversationID: 10)))
        XCTAssertFalse(policy.permits(.start(targetMemberID: 42)))
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 10)
        XCTAssertFalse(policy.permits(.send(try IMOutgoingIntent(scope: scope, payload: .route(topicID: 11)))))
    }
}
