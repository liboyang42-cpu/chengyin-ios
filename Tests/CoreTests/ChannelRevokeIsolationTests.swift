import Foundation
import XCTest
@testable import QuestifyCore

final class ChannelRevokeIsolationTests: XCTestCase {
    private func identity() throws -> ChannelAccount4Identity { try ChannelAccount4Identity(accountID: 7, epoch: 1) }
    private func rules() throws -> ChannelRulesCAS {
        try ChannelRulesCAS(publishedVersion: 3, pendingVersion: 4, expectedVersion: 3)
    }
    private func journey() throws -> ChannelGovernanceProjection {
        var value = ChannelGovernanceProjection(
            catalog: try ChannelCatalogEntry(channelID: 21, conversationID: 12, kind: .group, rules: try rules()),
            identity: try identity())
        try value.consentToPublishedRules(try ChannelRulesAdmission(identity: try identity(), consentedVersion: 3))
        try value.submitInviteOrApply(kind: 1, spaceID: 12, requestID: "c08-join-01") { _, _, _, _, _, request in
            ["request_id": request, "status": 0, "join_state": "PENDING_REVIEW"]
        }
        try value.assignMemberRole(.member)
        _ = try value.authorizeReadWrite()
        return value
    }
    private func poll(_ status: String = "OPEN", myOption: Int? = nil) throws -> GroupPoll {
        var row: [String: Any] = ["id": 31, "conversationId": 12, "creatorMemberId": 7,
            "clientPollKey": "source-key", "question": "Which route?", "selectionMode": "SINGLE",
            "visibility": "PUBLIC", "status": status, "version": 1, "messageId": 44,
            "options": [
                ["id": 51, "pollId": 31, "position": 1, "content": "River", "voteCount": myOption == 51 ? 1 : 0],
                ["id": 52, "pollId": 31, "position": 2, "content": "Park", "voteCount": myOption == 52 ? 1 : 0]
            ], "totalVoters": myOption == nil ? 0 : 1]
        if let myOption { row["myOptionId"] = myOption }
        return try JSONDecoder().decode(GroupPoll.self, from: JSONSerialization.data(withJSONObject: row))
    }

    func testOldPageAndLateWriteIsolateAfterLeave() throws {
        var value = try journey()
        let lease = try value.pageLease()
        try value.leave()
        XCTAssertThrowsError(try value.pageLease()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember)
        }
        XCTAssertThrowsError(try value.admit(ChannelIsolatedRequest(lease: lease, action: .channelRead))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest)
        }
        XCTAssertThrowsError(try value.admit(ChannelIsolatedRequest(lease: lease, action: .lateJoin))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest)
        }
        XCTAssertThrowsError(try value.authorizeReadWrite()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .revoked)
        }
    }

    func testLeftGroupHistoricalVotesStayReadOnly() throws {
        var value = try journey()
        let lease = try value.pageLease()
        let open = try poll()
        XCTAssertTrue(ChannelRevokeIsolation.voteWriteAllowed(poll: open, membershipActive: true))
        try value.leave()
        let isolation = ChannelRevokeIsolation(channelID: 21, identity: try identity(),
                                               revokedAtGeneration: value.generation, reason: .leave, phase: .left)
        XCTAssertEqual(try isolation.historicalVoteAccess(poll: open, membershipActive: false), .allowed)
        XCTAssertFalse(ChannelRevokeIsolation.voteWriteAllowed(poll: open, membershipActive: false))
        XCTAssertEqual(try value.admit(ChannelIsolatedRequest(lease: lease, action: .historicalVoteRead)), .allowed)
        XCTAssertThrowsError(try value.admit(ChannelIsolatedRequest(lease: lease, action: .historicalVoteWrite))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .historicalVoteWriteDenied)
        }
        XCTAssertEqual(try isolation.historicalVoteAccess(poll: try poll("CLOSED", myOption: 51), membershipActive: false), .allowed)
    }

    func testForeignACCOUNT4LeaseCannotUseRevokedChannel() throws {
        var value = try journey()
        let lease = try value.pageLease()
        try value.leave()
        let foreign = ChannelPageLease(channelID: 21, conversationID: 12, generation: lease.generation,
                                       identity: try ChannelAccount4Identity(accountID: 9, epoch: 1),
                                       capabilities: lease.capabilities, consentedRulesVersion: 3)
        XCTAssertThrowsError(try value.admit(ChannelIsolatedRequest(lease: foreign, action: .historicalVoteRead))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
    }

    func testBanAppealRemainsWhileRWStaysIsolated() throws {
        var value = try journey()
        let lease = try value.pageLease()
        try value.ban()
        XCTAssertThrowsError(try value.admit(ChannelIsolatedRequest(lease: lease, action: .channelWrite))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest)
        }
        XCTAssertEqual(try value.admit(ChannelIsolatedRequest(lease: lease, action: .appeal)), .allowed)
    }

    func testUnusedHistoricalVoteReadDoesNotOccupyLeaveThenUniqueLeaveApplies() throws {
        var value = try journey()
        let lease = try value.pageLease()
        XCTAssertEqual(try value.admit(ChannelIsolatedRequest(lease: lease, action: .historicalVoteRead)), .allowed)
        XCTAssertEqual(value.phase, .authorizedReadWrite)
        XCTAssertNotNil(value.grant, "在籍历史投票只读不得占 leave")
        try value.leave()
        XCTAssertEqual(value.phase, .left)
        XCTAssertNil(value.grant)
        XCTAssertThrowsError(try value.authorizeReadWrite()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .revoked)
        }
        XCTAssertEqual(try value.admit(ChannelIsolatedRequest(lease: lease, action: .historicalVoteRead)), .allowed)
    }
}
