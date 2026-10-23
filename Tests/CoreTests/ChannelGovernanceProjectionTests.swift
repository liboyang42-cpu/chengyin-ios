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
}
