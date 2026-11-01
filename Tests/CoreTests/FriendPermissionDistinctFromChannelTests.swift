import Foundation
import XCTest
@testable import QuestifyCore

final class FriendPermissionDistinctFromChannelTests: XCTestCase {
    private func grant() throws -> ChannelAuthorizationGrant {
        try ChannelAuthorizationGrant(
            identity: ChannelAccount4Identity(accountID: 7, epoch: 1),
            channelID: 21, conversationID: 12, role: .member,
            consentedRulesVersion: 3, generation: 4)
    }

    func testChannelGrantCannotSatisfyFriendRemarksOrDM() throws {
        let channel = try grant()
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.authorize(channel: channel, friend: .none, action: .remarks)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .friendPermissionRequired)
        }
        XCTAssertNoThrow(try FriendPermissionDistinctFromChannel.authorize(channel: channel, friend: .friend(accountID: 82), action: .directMessage))
        XCTAssertNoThrow(try FriendPermissionDistinctFromChannel.authorize(channel: nil, friend: .friend(accountID: 82), action: .directMessage))
        XCTAssertNotEqual(ChannelAuthorizationError.friendPermissionRequired, ChannelAuthorizationError.channelPermissionRequired)
        XCTAssertNotEqual(ChannelAuthorizationError.friendPermissionRequired, ChannelAuthorizationError.isolatedLateRequest)
    }

    func testFriendGrantCannotSatisfyChannelRWOrGovernance() throws {
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.authorize(channel: nil, friend: .friend(accountID: 82), action: .channelWrite)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .channelPermissionRequired)
        }
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.authorize(channel: nil, friend: .friend(accountID: 82), action: .governance)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .channelPermissionRequired)
        }
        XCTAssertNoThrow(try FriendPermissionDistinctFromChannel.authorize(channel: try grant(), friend: .none, action: .channelRead))
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.authorize(channel: try grant(), friend: .none, action: .governance)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .channelPermissionRequired)
        }
    }

    func testP44ProgressPrivacyIsNotRemarksOrDM() throws {
        let channel = try grant()
        for surface: ProgressPrivacySurface in [.remarks, .directMessage, .channelMessage] {
            XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.discloseProgress(channel: channel, friend: .friend(accountID: 82), surface: surface)) {
                XCTAssertEqual($0 as? ChannelAuthorizationError, .progressPrivacyDenied)
            }
        }
        XCTAssertNoThrow(try FriendPermissionDistinctFromChannel.discloseProgress(channel: channel, friend: .none, surface: .progressPrivacy))
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.discloseProgress(channel: nil, friend: .friend(accountID: 82), surface: .progressPrivacy)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .progressPrivacyDenied)
        }
    }

    func testStartMutationIsFriendDomainAndSendIsChannelDomain() throws {
        XCTAssertEqual(FriendPermissionDistinctFromChannel.domain(for: .start(targetMemberID: 82)), .friend)
        XCTAssertEqual(FriendPermissionDistinctFromChannel.domain(for: .read(conversationID: 12)), .channel)
        let grant = try grant()
        XCTAssertThrowsError(try ChannelMemberAuthorizationProjection.denyFriendImpersonation(grant, mutation: .start(targetMemberID: 82))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .friendPermissionRequired)
        }
        XCTAssertNoThrow(try ChannelMemberAuthorizationProjection.denyFriendImpersonation(grant, mutation: .send(
            try IMOutgoingIntent(scope: IMScope(identity: grant.identity.messagingIdentity, conversationID: 12),
                                 payload: .route(topicID: 11)))))
    }
}
