import Foundation
import XCTest
@testable import QuestifyCore

final class ChannelGovernanceProjectionTests: XCTestCase {
    private func identity(_ account: Int = 7, epoch: UInt64 = 1) throws -> ChannelAccount4Identity {
        try ChannelAccount4Identity(accountID: account, epoch: epoch)
    }
    private func rules(published: Int = 3, pending: Int? = 4, expected: Int = 3) throws -> ChannelRulesCAS {
        try ChannelRulesCAS(publishedVersion: published, pendingVersion: pending, expectedVersion: expected)
    }
    private func catalog() throws -> ChannelCatalogEntry {
        try ChannelCatalogEntry(channelID: 21, conversationID: 12, kind: .group, rules: try rules())
    }
    private func admission(_ identity: ChannelAccount4Identity, version: Int = 3) throws -> ChannelRulesAdmission {
        try ChannelRulesAdmission(identity: identity, consentedVersion: version)
    }
    private func joined() throws -> (ChannelGovernanceProjection, ChannelAuthorizationGrant, ChannelPageLease) {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        try journey.requireRulesConsent()
        try journey.consentToPublishedRules(try admission(try identity()))
        try journey.submitInviteOrApply()
        try journey.assignMemberRole(.member)
        let grant = try journey.authorizeReadWrite()
        return (journey, grant, try journey.pageLease())
    }

    func testCatalogRejectsNonGroupConversationsAndInvalidIDs() {
        XCTAssertThrowsError(try ChannelCatalogEntry(channelID: 21, conversationID: 12, kind: .direct, rules: try rules())) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog)
        }
        XCTAssertThrowsError(try ChannelAccount4Identity(accountID: 0, epoch: 1)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        XCTAssertEqual(ChannelAccount4Identity.realm, "ACCOUNT4")
    }

    func testP04DualVersionCASRejectsPendingAndStaleExpectedVersion() throws {
        let id = try identity()
        XCTAssertThrowsError(try ChannelRulesCAS(publishedVersion: 3, pendingVersion: 2, expectedVersion: 3)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesCASConflict)
        }
        let stale = try ChannelCatalogEntry(channelID: 21, conversationID: 12, kind: .group,
                                            rules: try rules(published: 3, pending: 4, expected: 2))
        XCTAssertThrowsError(try admission(id).admit(identity: id, catalog: stale)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesCASConflict)
        }
        let pendingJoin = try admission(id, version: 4)
        XCTAssertThrowsError(try pendingJoin.admit(identity: id, catalog: try catalog())) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesCASConflict)
        }
        XCTAssertThrowsError(try admission(id, version: 2).admit(identity: id, catalog: try catalog())) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesConsentRequired)
        }
    }

    func testJoinWithoutRulesConsentCannotAuthorizeRW() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertThrowsError(try journey.submitInviteOrApply()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesConsentRequired)
        }
        try journey.requireRulesConsent()
        XCTAssertEqual(journey.phase, .rulesConsentRequired)
        XCTAssertNil(journey.grant)
        XCTAssertThrowsError(try journey.authorizeReadWrite()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember)
        }
    }

    func testFirstJourneyJoinAfterConsentAuthorizedRWRevokeLateRequestAndFriendDenied() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        try journey.requireRulesConsent()
        try journey.consentToPublishedRules(try admission(try identity()))
        XCTAssertEqual(journey.phase, .inviteOrApply)
        try journey.submitInviteOrApply()
        try journey.assignMemberRole(.member)
        let grant = try journey.authorizeReadWrite()
        XCTAssertEqual(journey.phase, .authorizedReadWrite)
        XCTAssertTrue(grant.permits(.read))
        XCTAssertTrue(grant.permits(.write))
        XCTAssertEqual(grant.identity.accountID, 7)
        XCTAssertEqual(grant.consentedRulesVersion, 3)
        let lease = try journey.pageLease()
        XCTAssertNoThrow(try ChannelMemberAuthorizationProjection.denyFriendImpersonation(grant, mutation: .read(conversationID: 12)))
        XCTAssertThrowsError(try ChannelMemberAuthorizationProjection.denyFriendImpersonation(grant, mutation: .start(targetMemberID: 82))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .friendPermissionRequired)
        }
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.authorize(channel: grant, friend: .none, action: .directMessage)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .friendPermissionRequired)
        }
        XCTAssertThrowsError(try FriendPermissionDistinctFromChannel.discloseProgress(channel: grant, friend: .friend(accountID: 82), surface: .remarks)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .progressPrivacyDenied)
        }
        try journey.leave()
        XCTAssertEqual(journey.phase, .left)
        XCTAssertNil(journey.grant)
        let late = ChannelIsolatedRequest(lease: lease, action: .channelWrite)
        XCTAssertThrowsError(try journey.admit(late)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest)
        }
        XCTAssertEqual(try journey.admit(ChannelIsolatedRequest(lease: lease, action: .historicalVoteRead)), .allowed)
        XCTAssertThrowsError(try journey.admit(ChannelIsolatedRequest(lease: lease, action: .historicalVoteWrite))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .historicalVoteWriteDenied)
        }
    }

    func testModeratorGovernanceThenBanKeepsAppealDistinctFromLateRW() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        try journey.consentToPublishedRules(try admission(try identity()))
        try journey.submitInviteOrApply()
        try journey.assignMemberRole(.moderator)
        try journey.govern()
        XCTAssertEqual(journey.phase, .governing)
        let lease = try journey.pageLease()
        try journey.ban()
        XCTAssertEqual(journey.phase, .banned)
        XCTAssertThrowsError(try journey.admit(ChannelIsolatedRequest(lease: lease, action: .governance))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest)
        }
        XCTAssertEqual(try journey.admit(ChannelIsolatedRequest(lease: lease, action: .appeal)), .allowed)
        try journey.appeal()
        XCTAssertEqual(journey.phase, .appealing)
    }

    func testApplicantCannotBorrowMemberRWAndWrongACCOUNT4CannotConsent() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        try journey.consentToPublishedRules(try admission(try identity()))
        try journey.submitInviteOrApply()
        XCTAssertEqual(journey.role, .applicant)
        XCTAssertThrowsError(try journey.authorizeReadWrite()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .roleRequired)
        }
        let other = try identity(9)
        XCTAssertThrowsError(try admission(try identity()).admit(identity: other, catalog: try catalog())) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        XCTAssertThrowsError(try journey.assignMemberRole(.none)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .roleRequired)
        }
    }

    func testJoinedHelperProducesAuthorizedGrant() throws {
        let (_, grant, lease) = try joined()
        XCTAssertEqual(grant.channelID, 21)
        XCTAssertEqual(lease.conversationID, 12)
        XCTAssertTrue(lease.capabilities.contains(.write))
    }

    func testOtherACCOUNT4DoesNotRewriteOriginalGrant() throws {
        var (journey, grant, lease) = try joined()
        XCTAssertEqual(grant.identity.accountID, 7)
        XCTAssertEqual(grant.identity.epoch, 1)
        let other = try identity(9)
        let otherEpoch = try identity(7, epoch: 2)
        XCTAssertThrowsError(try admission(try identity()).admit(identity: other, catalog: try catalog())) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        XCTAssertThrowsError(try admission(try identity()).admit(identity: otherEpoch, catalog: try catalog())) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        let foreignLease = ChannelPageLease(channelID: 21, conversationID: 12, generation: grant.generation,
                                            identity: other, capabilities: [.write], consentedRulesVersion: 3)
        XCTAssertThrowsError(try journey.admit(ChannelIsolatedRequest(lease: foreignLease, action: .channelWrite))) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        XCTAssertEqual(journey.grant?.identity.accountID, 7)
        XCTAssertEqual(journey.grant?.identity.epoch, 1)
        XCTAssertNotEqual(journey.grant?.identity, other)
        XCTAssertEqual(lease.identity.accountID, 7)
    }

    func testInProcessRecoverKeepsOriginalGrantAndUnsignedOriginalWaitingSource() throws {
        let (original, grant, _) = try joined()
        XCTAssertEqual(grant.identity.accountID, 7)
        XCTAssertEqual(original.phase, .authorizedReadWrite)
        let restarted = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertEqual(restarted.phase, .cataloged)
        XCTAssertNil(restarted.grant)
        XCTAssertEqual(original.grant?.identity.accountID, 7)
        XCTAssertEqual(original.grant?.role, .member)
        XCTAssertEqual(original.grant?.consentedRulesVersion, 3)
        XCTAssertThrowsError(try original.commitUnsignedOriginal(capability: "D5-native-43")) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .waitingSource)
        }
        XCTAssertEqual(original.grant?.identity.accountID, 7)
    }

    func testCatalogedGrantDoesNotOccupyThenUniqueAuthorizeApplies() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertEqual(journey.phase, .cataloged)
        XCTAssertNil(journey.grant)
        try journey.requireRulesConsent()
        XCTAssertNil(journey.grant)
        try journey.consentToPublishedRules(try admission(try identity()))
        XCTAssertNil(journey.grant)
        try journey.submitInviteOrApply()
        XCTAssertNil(journey.grant)
        try journey.assignMemberRole(.member)
        XCTAssertEqual(journey.phase, .memberRoleAssigned)
        XCTAssertNil(journey.grant)
        let grant = try journey.authorizeReadWrite()
        XCTAssertEqual(grant.identity.accountID, 7)
        XCTAssertEqual(grant.role, .member)
        XCTAssertEqual(grant.consentedRulesVersion, 3)
        XCTAssertEqual(journey.grant?.identity.accountID, 7)
        XCTAssertEqual(journey.phase, .authorizedReadWrite)
    }

    func testUnusedAppealDoesNotOccupyBanThenUniqueBanApplies() throws {
        var journey = try joined().0
        XCTAssertThrowsError(try journey.appeal()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .revoked)
        }
        XCTAssertEqual(journey.phase, .authorizedReadWrite)
        XCTAssertNotNil(journey.grant, "在籍未封禁申诉不得占 ban")
        try journey.ban()
        XCTAssertEqual(journey.phase, .banned)
        XCTAssertNil(journey.grant)
        try journey.appeal()
        XCTAssertEqual(journey.phase, .appealing)
    }

    func testUnusedCatalogedLeaveDoesNotOccupyThenUniqueLeaveApplies() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertEqual(journey.phase, .cataloged)
        XCTAssertThrowsError(try journey.leave()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .roleRequired)
        }
        XCTAssertEqual(journey.phase, .cataloged, "cataloged leave 观察不得占 LEFT")
        XCTAssertNil(journey.grant)
        try journey.consentToPublishedRules(try admission(try identity()))
        try journey.submitInviteOrApply()
        try journey.assignMemberRole(.member)
        _ = try journey.authorizeReadWrite()
        try journey.leave()
        XCTAssertEqual(journey.phase, .left)
        XCTAssertNil(journey.grant)
    }

    func testUnusedCatalogedInviteDoesNotOccupyApplicantThenUniqueSubmitApplies() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertEqual(journey.role, .none)
        XCTAssertThrowsError(try journey.submitInviteOrApply()) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesConsentRequired)
        }
        XCTAssertEqual(journey.role, .none, "cataloged invite 观察不得占 applicant")
        XCTAssertEqual(journey.phase, .cataloged)
        try journey.consentToPublishedRules(try admission(try identity()))
        XCTAssertEqual(journey.role, .none)
        try journey.submitInviteOrApply()
        XCTAssertEqual(journey.role, .applicant)
        XCTAssertEqual(journey.phase, .inviteOrApply)
        XCTAssertNil(journey.grant)
    }

    func testUnusedCatalogedAssignDoesNotOccupyMemberThenUniqueAssignApplies() throws {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertEqual(journey.role, .none)
        XCTAssertThrowsError(try journey.assignMemberRole(.member)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .roleRequired)
        }
        XCTAssertEqual(journey.role, .none, "cataloged assign 观察不得占 member")
        XCTAssertEqual(journey.phase, .cataloged)
        try journey.consentToPublishedRules(try admission(try identity()))
        try journey.submitInviteOrApply()
        XCTAssertEqual(journey.role, .applicant)
        try journey.assignMemberRole(.member)
        XCTAssertEqual(journey.role, .member)
        XCTAssertEqual(journey.phase, .memberRoleAssigned)
        XCTAssertNil(journey.grant)
    }

    func testAuthorizeFromMembershipRequiresImActiveGroupMemberThenLiveMemberIssuesGrant() throws {
        var missing = try memberReady()
        XCTAssertThrowsError(try missing.authorizeFromMembership(memberID: 70, isActiveGroupMember: nil)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .waitingSource)
        }
        XCTAssertNil(missing.grant)
        XCTAssertEqual(missing.phase, .memberRoleAssigned)
        var denied = try memberReady()
        XCTAssertThrowsError(try denied.authorizeFromMembership(memberID: 70, isActiveGroupMember: { _, _ in false })) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember)
        }
        XCTAssertNil(denied.grant)
        var live = try memberReady()
        let grant = try live.authorizeFromMembership(memberID: 70, isActiveGroupMember: { memberID, conversationID in
            memberID == 70 && conversationID == 12
        })
        XCTAssertEqual(live.phase, .authorizedReadWrite)
        XCTAssertEqual(grant.identity.accountID, 7)
    }

    func testReadMessagesUsesListMessagesOnlyAfterActiveMembershipAndDoesNotChangePhase() throws {
        var missing = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertThrowsError(try missing.readMessages(
            memberID: 70, cursorID: nil, size: 20, afterID: nil,
            isActiveGroupMember: { _, _ in true }, listMessages: nil)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .waitingListMessages)
        }
        XCTAssertEqual(missing.phase, .cataloged)
        var reads = 0
        var denied = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        XCTAssertThrowsError(try denied.readMessages(
            memberID: 70, cursorID: nil, size: 20, afterID: nil,
            isActiveGroupMember: { _, _ in false },
            listMessages: { _, _, _, _, _ in reads += 1; return ["ok": "1"] })) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(denied.phase, .cataloged)
        var live = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        let page = try live.readMessages(
            memberID: 70, cursorID: nil, size: 20, afterID: nil,
            isActiveGroupMember: { member, conversation in member == 70 && conversation == 12 },
            listMessages: { _, conversation, _, size, _ in
                reads += 1
                return ["conversationId": String(conversation), "size": String(size)]
            })
        XCTAssertEqual(page?["conversationId"], "12")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(live.phase, .cataloged)
        XCTAssertEqual(live.generation, 1)
        let foreign = try live.readMessages(
            memberID: 70, cursorID: nil, size: 20, afterID: nil,
            isActiveGroupMember: { _, _ in true },
            listMessages: { _, _, _, _, _ in ["conversationId": "99"] })
        XCTAssertNil(foreign)
    }

    func testReadMessagesAfterBanOrLeaveDoesNotCallListMessagesWhenMembershipStaysTrue() throws {
        var reads = 0
        let listMessages: (Int64, Int64, Int64?, Int, Int64?) -> [String: String] = { _, _, _, _, _ in
            reads += 1
            return ["called": "1"]
        }
        var banned = try memberReady()
        try banned.ban()
        XCTAssertThrowsError(try banned.readMessages(
            memberID: 70, cursorID: nil, size: 20, afterID: nil,
            isActiveGroupMember: { _, _ in true }, listMessages: listMessages)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .revoked)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(banned.phase, .banned)
        XCTAssertEqual(banned.role, .none)
        XCTAssertEqual(banned.revokeReason, .ban)

        var left = try memberReady()
        try left.leave()
        XCTAssertThrowsError(try left.readMessages(
            memberID: 70, cursorID: nil, size: 20, afterID: nil,
            isActiveGroupMember: { _, _ in true }, listMessages: listMessages)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .revoked)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(left.phase, .left)
        XCTAssertEqual(left.role, .none)
        XCTAssertEqual(left.revokeReason, .leave)
    }

    private func memberReady() throws -> ChannelGovernanceProjection {
        var journey = ChannelGovernanceProjection(catalog: try catalog(), identity: try identity())
        try journey.consentToPublishedRules(try admission(try identity()))
        try journey.submitInviteOrApply()
        try journey.assignMemberRole(.member)
        return journey
    }

    func testMissingACCOUNT4StaysMismatchNeverEmptyIdentity() {
        XCTAssertThrowsError(try ChannelAccount4Identity(accountID: 0, epoch: 1)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        XCTAssertThrowsError(try ChannelAccount4Identity(accountID: -1, epoch: 1)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .account4Mismatch)
        }
        XCTAssertEqual(ChannelAccount4Identity.realm, "ACCOUNT4")
        XCTAssertNotEqual(ChannelAccount4Identity.realm, "")
    }

    func testJSONMyStateHidesUnreadWhenIndexIsNotABoolean() throws {
        let raw = try JSONSerialization.data(withJSONObject: [
            "pinned": 0, "hidden": 0, "muted": 0, "permanent_muted": false, "effective_level": 1,
            "muted_until": NSNull(), "read_state_available": 1, "indexed": false, "unread_count": 7,
            "last_read_msg_id": "42", "last_read_visible_at": "2026-10-24T09:00:00Z"
        ])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let state = try XCTUnwrap(DirectoryMyState.read(object))
        XCTAssertNil(state.unreadCount)
        XCTAssertEqual(state.readStateAvailable, 0)
        XCTAssertNil(state.lastReadVisibleAt)
        let legal = try JSONSerialization.data(withJSONObject: [
            "pinned": 0, "hidden": 0, "muted": 0, "permanent_muted": false, "effective_level": 1,
            "muted_until": "2026-10-24T10:00:00Z", "read_state_available": 1, "indexed": true,
            "unread_count": 7, "last_read_msg_id": "9223372036854775807",
            "last_read_visible_at": "2026-10-24T09:00:00Z"
        ])
        let shown = try XCTUnwrap(DirectoryMyState.read(try XCTUnwrap(try JSONSerialization.jsonObject(with: legal) as? [String: Any])))
        XCTAssertEqual(shown.unreadCount, 7)
        XCTAssertEqual(shown.lastReadMessageID, "9223372036854775807")
        XCTAssertEqual(shown.mutedUntil, "2026-10-24T10:00:00Z")
        XCTAssertEqual(shown.lastReadVisibleAt, "2026-10-24T09:00:00Z")
        XCTAssertFalse(shown.grantsSend)
    }

    func testOriginalAckUsesSameScopeAndMissingReceiptStaysUnknown() throws {
        let ack = MessageContainerOriginalAck()
        let requestID = "ack-request-0001"
        var writes = 0
        XCTAssertThrowsError(try ack.acknowledge(actor: 70, channelID: 12, lastMessageID: 4, requestID: requestID,
                                                 channelKind: 1, sameScope: { _, _ in false }, writer: { _, _, _, _ in
            writes += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember) }
        XCTAssertEqual(writes, 0)
        XCTAssertThrowsError(try ack.acknowledge(actor: 70, channelID: 12, lastMessageID: 4, requestID: requestID,
                                                 channelKind: 0, sameScope: { _, _ in true }, writer: { _, _, _, _ in
            writes += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertEqual(writes, 0)
        let applied = try ack.acknowledge(actor: 70, channelID: 12, lastMessageID: 4, requestID: requestID,
                                          channelKind: 1, sameScope: { actor, channel in actor == 70 && channel == 12 },
                                          writer: { actor, channel, cursor, request in
            writes += 1
            XCTAssertEqual(actor, 70)
            XCTAssertEqual(channel, 12)
            XCTAssertEqual(cursor, 4)
            XCTAssertEqual(request, requestID)
            return try json([
                "request_id": request, "operation": "ACK", "scope_type": 1, "scope_id": "12",
                "status": "APPLIED", "replayed": false, "must_refresh_state": false, "result_redacted": false
            ])
        })
        XCTAssertEqual(applied.status, "APPLIED")
        XCTAssertEqual(applied.resultRedacted, false)
        XCTAssertEqual(applied.mustRefreshState, false)
        XCTAssertFalse(applied.markedReadOnLoad)
        XCTAssertFalse(applied.grantsSend)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(MessageContainerOriginalAck.readPath, "api/im/read")
        XCTAssertEqual(MessageContainerOriginalAck.receiptPathPrefix, "api/im/notification-requests/")
        let missing = try ack.recover(actor: 70, channelID: 12, requestID: requestID, channelKind: 1,
                                      originalAccount: { actor, request in actor == 70 && request == requestID },
                                      receipt: { _, request in
            try json(["request_id": request, "status": "NOT_FOUND", "outcome": "UNKNOWN",
                      "resume_with_same_request": true])
        })
        XCTAssertEqual(missing.outcome, "UNKNOWN")
        XCTAssertEqual(missing.requestID, requestID)
        XCTAssertTrue(missing.resumeSameRequest)
        XCTAssertNil(missing.resultRedacted)
        XCTAssertEqual(writes, 1)
        var reads = 0
        let revoked = try ack.recover(actor: 70, channelID: 12, requestID: requestID, channelKind: 1,
                                      originalAccount: { _, _ in true }, receipt: { _, request in
            reads += 1
            return try json([
                "request_id": request, "operation": "ACK", "scope_type": 1, "scope_id": "12",
                "status": "APPLIED", "replayed": true, "must_refresh_state": true, "result_redacted": true
            ])
        })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(revoked.resultRedacted, true)
        XCTAssertEqual(revoked.mustRefreshState, true)
        XCTAssertEqual(revoked.outcome, "APPLIED")
        XCTAssertThrowsError(try ack.recover(actor: 70, channelID: 12, requestID: requestID, channelKind: 1,
                                             originalAccount: { _, _ in false }, receipt: { _, _ in
            reads += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember) }
        XCTAssertEqual(reads, 1)
        XCTAssertThrowsError(try ack.acknowledge(actor: 70, channelID: 12, lastMessageID: 4, requestID: requestID,
                                                 channelKind: 1, sameScope: { _, _ in true }, writer: { _, _, _, request in
            try json(["request_id": request, "operation": "ACK", "scope_type": true, "scope_id": "12",
                      "status": "APPLIED", "replayed": false, "must_refresh_state": false, "result_redacted": false])
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertThrowsError(try ack.recover(actor: 70, channelID: 12, requestID: requestID, channelKind: 1,
                                             originalAccount: { _, _ in true }, receipt: { _, request in
            try json(["request_id": request, "status": "NOT_FOUND", "outcome": "UNKNOWN",
                      "resume_with_same_request": 1])
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertThrowsError(try ack.recover(actor: 70, channelID: 12, requestID: requestID, channelKind: 1,
                                             originalAccount: { _, _ in true }, receipt: { _, request in
            try json([
                "request_id": request, "operation": "ACK", "scope_type": 1, "scope_id": "12",
                "status": "APPLIED", "replayed": true, "must_refresh_state": true, "result_redacted": true,
                "result": ["text": "old body"]
            ])
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
    }

    func testType5HistoryUsesOriginalCursorOrderAndDoesNotAcknowledge() throws {
        let history = MessageContainerHistory()
        var calls: [(Int64, Int64, Int64?, Int, Int64?)] = []
        let page = try history.read(actor: 70, channelID: 12, before: 9, after: nil, limit: 100,
                                    conversationType: 5, channelKind: 1,
                                    canReadHistory: { actor, channel in actor == 70 && channel == 12 },
                                    listMessages: { actor, channel, before, limit, after in
            calls.append((actor, channel, before, limit, after))
            return Self.historyPage(after: nil)
        })
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, 70)
        XCTAssertEqual(calls[0].1, 12)
        XCTAssertEqual(calls[0].2, 9)
        XCTAssertEqual(calls[0].3, 50)
        XCTAssertNil(calls[0].4)
        XCTAssertEqual(page["sync_contract"] as? String, "VISIBLE_ORDER_PLUS_MUTATIONS_V1")
        XCTAssertEqual(page["legacy_cache_action"] as? String, "RELOAD_ON_RESUME")
        XCTAssertNil(page["operation"])
        var resumed = 0
        _ = try history.read(actor: 70, channelID: 12, before: nil, after: 4, limit: 0,
                             conversationType: 5, channelKind: 1, canReadHistory: { _, _ in true },
                             listMessages: { _, _, before, limit, after in
            resumed += 1
            XCTAssertNil(before)
            XCTAssertEqual(limit, 20)
            XCTAssertEqual(after, 4)
            return Self.historyPage(after: "4")
        })
        XCTAssertEqual(resumed, 1)
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: 9, after: 4, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            calls.append((0, 0, nil, 0, nil))
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertEqual(calls.count, 1)
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                              conversationType: 5, channelKind: 0,
                                              canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            calls.append((0, 0, nil, 0, nil))
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in false }, listMessages: { _, _, _, _, _ in
            calls.append((0, 0, nil, 0, nil))
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember) }
        XCTAssertEqual(calls.count, 1)
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in true }, listMessages: nil)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .waitingListMessages)
        }
        var acknowledged = Self.historyPage(after: nil)
        acknowledged["operation"] = "ACK"
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            acknowledged
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        var nullList = Self.historyPage(after: nil)
        nullList["list"] = NSNull()
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: 0, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, after in
            XCTAssertEqual(after, 0)
            return nullList
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        var textFlag = Self.historyPage(after: nil)
        textFlag["has_more"] = "false"
        textFlag["hasMore"] = "false"
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            textFlag
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        var conflict = Self.historyPage(after: nil)
        conflict["has_more"] = true
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                              conversationType: 5, channelKind: 1,
                                              canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            conflict
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertThrowsError(try history.read(actor: 70, channelID: 12, before: nil, after: 0, limit: 20,
                                              conversationType: 5, channelKind: 1, canReadHistory: { _, _ in true },
                                              listMessages: { _, _, _, _, _ in
            var page = Self.historyPage(after: nil)
            page["list"] = [] as [Any]
            page["mutation_cursor"] = 0
            page["next_after"] = NSNull()
            page["nextAfter"] = NSNull()
            return page
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        let kept = try history.read(actor: 70, channelID: 12, before: nil, after: 0, limit: 20,
                                    conversationType: 5, channelKind: 1, canReadHistory: { _, _ in true },
                                    listMessages: { _, _, _, _, _ in
            var page = Self.historyPage(after: nil)
            page["list"] = [] as [Any]
            page["next_after"] = "0"
            page["nextAfter"] = "0"
            return page
        })
        XCTAssertEqual(kept["nextAfter"] as? String, "0")
        let ordinary = try history.read(actor: 70, channelID: 12, before: nil, after: nil, limit: 20,
                                        conversationType: 5, channelKind: 1, canReadHistory: { _, _ in true },
                                        listMessages: { _, _, _, _, _ in
            var page = Self.historyPage(after: nil)
            page["list"] = [] as [Any]
            page["next_cursor"] = NSNull()
            page["nextCursor"] = NSNull()
            return page
        })
        XCTAssertEqual((ordinary["list"] as? [[String: Any]])?.count, 0)
    }

    func testLateIdentityDoesNotReadHistoryOrAcknowledge() throws {
        let (journey, _, lease) = try joined()
        let history = MessageContainerHistory()
        let open = ChannelRevokeIsolation(channelID: lease.channelID, identity: lease.identity,
                                          revokedAtGeneration: nil, reason: nil, phase: journey.phase)
        var reads = 0
        let page = try history.readIsolated(actor: 7, channelID: 12, before: nil, after: nil, limit: 20,
                                            conversationType: 5, channelKind: 1, lease: lease, currentLease: { lease }, isolation: open,
                                            canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            reads += 1
            var page = Self.historyPage(after: nil)
            page["list"] = [
                ["id": "7", "conversationId": "12", "senderId": "3", "content": "hello", "status": NSNumber(value: 0)],
                ["id": "8", "conversationId": "12", "senderId": "3", "content": "secret", "status": NSNumber(value: 2), "extraJson": ["x": 1]],
                ["id": "6", "conversationId": "12", "senderId": "3", "content": "nope", "status": NSNumber(value: false)],
                ["id": "5", "conversationId": "12", "senderId": "3", "content": "half", "status": NSNumber(value: 0.5)],
                ["id": "9", "conversationId": "99", "senderId": "3", "content": "other", "status": NSNumber(value: 0)]
            ]
            return page
        })
        XCTAssertEqual(reads, 1)
        let rows = try XCTUnwrap(page["list"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0]["content"] as? String, "hello")
        XCTAssertEqual(rows[1]["content"] as? String, "")
        XCTAssertTrue(rows[1]["extraJson"] is NSNull)
        XCTAssertEqual(rows[2]["content"] as? String, "")
        XCTAssertEqual(rows[3]["content"] as? String, "")
        var allow = true
        var revokedDuringRead = 0
        XCTAssertThrowsError(try history.readIsolated(actor: 7, channelID: 12, before: nil, after: nil, limit: 20,
                                                      conversationType: 5, channelKind: 1, lease: lease, currentLease: { lease }, isolation: open,
                                                      canReadHistory: { _, _ in allow }, listMessages: { _, _, _, _, _ in
            revokedDuringRead += 1
            allow = false
            return Self.historyPage(after: nil)
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .notMember) }
        XCTAssertEqual(revokedDuringRead, 1)
        XCTAssertThrowsError(try history.projectList(NSNull(), channelID: 12)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog)
        }
        var generation = lease.generation
        var rejoined = 0
        XCTAssertThrowsError(try history.readIsolated(actor: 7, channelID: 12, before: nil, after: nil, limit: 20,
                                                      conversationType: 5, channelKind: 1, lease: lease,
                                                      currentLease: {
            ChannelPageLease(channelID: lease.channelID, conversationID: lease.conversationID,
                             generation: generation, identity: lease.identity, capabilities: lease.capabilities,
                             consentedRulesVersion: lease.consentedRulesVersion)
        }, isolation: open, canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            rejoined += 1
            generation += 1
            return Self.historyPage(after: nil)
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest) }
        XCTAssertEqual(rejoined, 1)
        var left = journey
        try left.leave()
        let closed = ChannelRevokeIsolation(channelID: left.catalog.channelID, identity: left.identity,
                                            revokedAtGeneration: left.generation, reason: left.revokeReason, phase: left.phase)
        XCTAssertThrowsError(try history.readIsolated(actor: 7, channelID: 12, before: nil, after: nil, limit: 20,
                                                      conversationType: 5, channelKind: 1, lease: lease, currentLease: { lease }, isolation: closed,
                                                      canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            reads += 1
            return Self.historyPage(after: nil)
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest) }
        XCTAssertEqual(reads, 1)
        let ack = MessageContainerOriginalAck()
        let requestID = "ack-request-0001"
        var writes = 0
        XCTAssertThrowsError(try ack.acknowledgeExplicit(actor: 7, channelID: 12, lastMessageID: 4, requestID: requestID,
                                                         channelKind: 1, lease: lease, currentLease: { lease }, isolation: closed,
                                                         sameScope: { _, _ in true }, writer: { _, _, _, _ in
            writes += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .isolatedLateRequest) }
        XCTAssertEqual(writes, 0)
        let applied = try ack.acknowledgeExplicit(actor: 7, channelID: 12, lastMessageID: 4, requestID: requestID,
                                                  channelKind: 1, lease: lease, currentLease: { lease }, isolation: open,
                                                  sameScope: { _, _ in true }, writer: { _, _, _, request in
            writes += 1
            return try json([
                "request_id": request, "operation": "ACK", "scope_type": 1, "scope_id": "12",
                "status": "APPLIED", "replayed": false, "must_refresh_state": false, "result_redacted": false
            ])
        })
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(applied.status, "APPLIED")
        XCTAssertFalse(applied.markedReadOnLoad)
    }

    func testHistoryOpenDoesNotAckAndRecoverUsesTheSameRequest() throws {
        let (journey, _, lease) = try joined()
        let openIsolation = ChannelRevokeIsolation(channelID: lease.channelID, identity: lease.identity,
                                                   revokedAtGeneration: nil, reason: nil, phase: journey.phase)
        var entry = MessageHistoryAckEntry()
        var reads = 0
        var writes = 0
        let actor = Int64(lease.identity.accountID)
        let channel = Int64(lease.conversationID)
        let page = try entry.open(actor: actor, channelID: channel, before: nil, after: nil, limit: 20,
                                  conversationType: 5, channelKind: 1, lease: lease, currentLease: { lease },
                                  isolation: openIsolation, canReadHistory: { _, _ in true }, listMessages: { _, _, _, _, _ in
            reads += 1
            return Self.historyPage(after: nil)
        })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual((page["list"] as? [[String: Any]])?.count, 0)
        XCTAssertNil(entry.intent)
        XCTAssertEqual(entry.phase, .idle)
        let receipt = try entry.acknowledge(actor: actor, channelID: channel, lastMessageID: 4, channelKind: 1,
                                            lease: lease, currentLease: { lease }, isolation: openIsolation,
                                            sameScope: { _, _ in true }, writer: { _, _, _, request in
            writes += 1
            return try json([
                "request_id": request, "operation": "ACK", "scope_type": 1, "scope_id": String(channel),
                "status": "APPLIED", "replayed": false, "must_refresh_state": false, "result_redacted": false
            ])
        })
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(receipt.requestID, entry.intent?.requestID)
        XCTAssertFalse(receipt.markedReadOnLoad)
        XCTAssertThrowsError(try entry.acknowledge(actor: actor, channelID: channel, lastMessageID: 4, channelKind: 1,
                                                   lease: lease, currentLease: { lease }, isolation: openIsolation,
                                                   sameScope: { _, _ in true }, writer: { _, _, _, _ in
            writes += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertEqual(writes, 1)
        let recovered = try entry.recover(originalAccount: { _, _ in true }, receipt: { _, request in
            try json([
                "request_id": request, "operation": "ACK", "scope_type": 1, "scope_id": String(channel),
                "status": "APPLIED", "replayed": true, "must_refresh_state": true, "result_redacted": true
            ])
        })
        XCTAssertEqual(recovered.requestID, entry.intent?.requestID)
        XCTAssertEqual(recovered.outcome, "APPLIED")
        XCTAssertEqual(entry.phase, .applied)
        XCTAssertEqual(writes, 1)
        let body = try XCTUnwrap(entry.originalReadBody())
        XCTAssertEqual(body["conversation_id"], String(channel))
        XCTAssertEqual(body["last_message_id"], "4")
        XCTAssertEqual(body["request_id"], entry.intent?.requestID)
        XCTAssertNil(body["scope_type"])
        XCTAssertNil(body["scope_id"])
        var rejected = MessageHistoryAckEntry()
        XCTAssertThrowsError(try rejected.acknowledge(actor: actor, channelID: channel, lastMessageID: 4, channelKind: 1,
                                                      lease: lease, currentLease: { lease }, isolation: openIsolation,
                                                      sameScope: { _, _ in false }, writer: { _, _, _, _ in
            writes += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertNil(rejected.intent)
        XCTAssertEqual(writes, 1)
        var fresh = MessageHistoryAckEntry()
        XCTAssertThrowsError(try fresh.recover(originalAccount: { _, _ in true }, receipt: { _, _ in
            writes += 1
            return [:]
        })) { XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog) }
        XCTAssertEqual(writes, 1)
    }

    private static func historyPage(after: String?) -> [String: Any] {
        var page: [String: Any] = [
            "list": [] as [Any], "next_cursor": "9", "has_more": NSNumber(value: false), "nextCursor": "9",
            "hasMore": NSNumber(value: false),
            "mutation_cursor": "0", "sync_contract": "VISIBLE_ORDER_PLUS_MUTATIONS_V1",
            "legacy_cache_action": "RELOAD_ON_RESUME"
        ]
        if let after { page["next_after"] = after; page["nextAfter"] = after }
        return page
    }

    private func json(_ body: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
