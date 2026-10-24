"""Structural checks: channel permission is not friend permission. Not Swift execution."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXCLUSIVE = [
    'Core/ChannelGovernanceProjection.swift',
    'Core/ChannelRulesAdmission.swift',
    'Core/ChannelMemberAuthorizationProjection.swift',
    'Core/ChannelRevokeIsolation.swift',
    'Core/FriendPermissionDistinctFromChannel.swift',
]
FORBIDDEN_TOUCH = [
    'App/AppSession.swift',
    'Questify.xcodeproj/project.pbxproj',
]


class ChannelNotFriendPermissionContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def exclusive(self):
        return '\n'.join(self.read(path) for path in EXCLUSIVE)

    def test_exclusive_files_exist_and_do_not_clone_im_send_receipt(self):
        source = self.exclusive()
        for path in EXCLUSIVE:
            self.assertTrue((ROOT / path).is_file(), path)
        for banned in ['api/im/send', 'api/im/send-receipt', 'OperationPendingJournal',
                       'URLSession', 'URLRequest', 'HTTPTransport', 'AppSession',
                       'pbxproj', 'Native43', 'Native45', 'Native46', 'Native47']:
            self.assertNotIn(banned, source)
        self.assertNotIn('journal.write', source)
        self.assertNotIn('journal.clear', source)

    def test_consumes_existing_p04_cas_and_p38_account4(self):
        source = self.exclusive()
        self.assertIn('ACCOUNT4', source)
        self.assertIn('publishedVersion', source)
        self.assertIn('pendingVersion', source)
        self.assertIn('expectedVersion', source)
        self.assertIn('P04', source)
        self.assertIn('P38', source)
        self.assertNotIn('report them as missing', source.lower())
        self.assertIn('existing P04', source)
        self.assertIn('existing member-authorization', source)
        self.assertIn('WAITING_SOURCE', source)

    def test_channel_grant_cannot_impersonate_friend_permission(self):
        friend = self.read('Core/FriendPermissionDistinctFromChannel.swift')
        member = self.read('Core/ChannelMemberAuthorizationProjection.swift')
        self.assertIn('friendPermissionRequired', friend)
        self.assertIn('channelPermissionRequired', friend)
        self.assertNotEqual(friend.find('friendPermissionRequired'), friend.find('channelPermissionRequired'))
        self.assertIn('case .start:', member)
        self.assertIn('throw ChannelAuthorizationError.friendPermissionRequired', member)
        self.assertIn('case remarks, directMessage', friend)
        authorize = friend.split('action: FriendOnlyAction', 1)[1]
        self.assertIn('_ = channel', authorize)
        self.assertIn('throw ChannelAuthorizationError.friendPermissionRequired', authorize)

    def test_p44_progress_privacy_is_not_remarks_or_dm(self):
        friend = self.read('Core/FriendPermissionDistinctFromChannel.swift')
        self.assertIn('P44', friend)
        self.assertIn('progressPrivacyDenied', friend)
        self.assertIn('case .remarks, .directMessage:', friend)
        disclose = friend.split('func discloseProgress', 1)[1]
        self.assertIn('throw ChannelAuthorizationError.progressPrivacyDenied', disclose)
        self.assertIn('case .progressPrivacy:', disclose)

    def test_left_group_historical_votes_stay_read_only(self):
        isolation = self.read('Core/ChannelRevokeIsolation.swift')
        self.assertIn('historicalVoteRead', isolation)
        self.assertIn('historicalVoteWriteDenied', isolation)
        self.assertIn('GroupPoll', isolation)
        self.assertIn('voteWriteAllowed', isolation)
        self.assertIn('membershipActive && poll.isOpen()', isolation)

    def test_first_journey_is_authored_on_exclusive_tests(self):
        tests = self.read('Tests/CoreTests/ChannelGovernanceProjectionTests.swift')
        self.assertIn('testFirstJourneyJoinAfterConsentAuthorizedRWRevokeLateRequestAndFriendDenied', tests)
        self.assertIn('consentToPublishedRules', tests)
        self.assertIn('authorizeReadWrite', tests)
        self.assertIn('isolatedLateRequest', tests)
        self.assertIn('friendPermissionRequired', tests)
        revoke = self.read('Tests/CoreTests/ChannelRevokeIsolationTests.swift')
        self.assertIn('testLeftGroupHistoricalVotesStayReadOnly', revoke)
        self.assertIn('testOldPageAndLateWriteIsolateAfterLeave', revoke)
        self.assertIn('testUnusedHistoricalVoteReadDoesNotOccupyLeaveThenUniqueLeaveApplies', revoke)
        distinct = self.read('Tests/CoreTests/FriendPermissionDistinctFromChannelTests.swift')
        self.assertIn('testChannelGrantCannotSatisfyFriendRemarksOrDM', distinct)
        self.assertIn('testP44ProgressPrivacyIsNotRemarksOrDM', distinct)

    def test_account_switch_isolation_markers_present(self):
        tests = self.read('Tests/CoreTests/ChannelGovernanceProjectionTests.swift')
        self.assertIn('testOtherACCOUNT4DoesNotRewriteOriginalGrant', tests)
        self.assertIn('testInProcessRecoverKeepsOriginalGrantAndUnsignedOriginalWaitingSource', tests)
        self.assertIn('testCatalogedGrantDoesNotOccupyThenUniqueAuthorizeApplies', tests)
        self.assertIn('testUnusedAppealDoesNotOccupyBanThenUniqueBanApplies', tests)
        self.assertIn('testUnusedCatalogedLeaveDoesNotOccupyThenUniqueLeaveApplies', tests)
        self.assertIn('testUnusedCatalogedInviteDoesNotOccupyApplicantThenUniqueSubmitApplies', tests)
        self.assertIn('testUnusedCatalogedAssignDoesNotOccupyMemberThenUniqueAssignApplies', tests)
        self.assertIn('testMissingACCOUNT4StaysMismatchNeverEmptyIdentity', tests)
        self.assertIn('account4Mismatch', tests)
        governance = self.read('Core/ChannelGovernanceProjection.swift')
        self.assertIn('commitUnsignedOriginal', governance)
        self.assertIn('waitingSource', governance)
        self.assertIn('authorizeFromMembership', governance)
        self.assertIn('im.isActiveGroupMember', governance)
        self.assertIn('im.listMessages', governance)
        self.assertIn('readMessages', governance)
        self.assertIn('struct MessageContainerProjection', governance)
        self.assertIn('conversationType == 5', governance)
        self.assertIn('readStateUnknown', governance)
        self.assertIn('grantsSend: false', governance)
        self.assertIn('func consumeAuthorizedDetail', governance)
        self.assertIn('struct DirectoryMyState', governance)
        self.assertIn('NOT_APPLICABLE', governance)
        self.assertIn('read_state_available', governance)
        self.assertIn('struct MessageContainerReadHost', governance)
        self.assertIn('muted_until', governance)
        self.assertIn('last_read_visible_at', governance)
        self.assertIn('jsonBool(myState["indexed"]) == true', governance)
        self.assertIn('func acknowledge()', governance)
        self.assertIn('struct MessageContainerOriginalAck', governance)
        self.assertIn('ChannelNotificationService.acknowledge', governance)
        self.assertIn('exactInt(body["scope_type"]) == 1', governance)
        self.assertIn('jsonBool(body["must_refresh_state"])', governance)
        self.assertIn('jsonBool(body["result_redacted"])', governance)
        self.assertIn('originalAccount', governance)
        self.assertIn('api/im/read', governance)
        self.assertIn('api/im/notification-requests/', governance)
        self.assertIn('struct MessageContainerHistory', governance)
        self.assertIn('ChannelMessageService.history', governance)
        self.assertIn('before > 0, after != nil', governance)
        self.assertIn('testType5HistoryUsesOriginalCursorOrderAndDoesNotAcknowledge', tests)
        self.assertIn('testOriginalAckUsesSameScopeAndMissingReceiptStaysUnknown', tests)
        self.assertIn('is not an authority revision', governance)
        self.assertNotIn('MessagingConversationKind(rawValue: 5)', governance)
        self.assertIn('waitingListMessages', governance)
        tests = self.read('Tests/CoreTests/ChannelGovernanceProjectionTests.swift')
        self.assertIn('testAuthorizeFromMembershipRequiresImActiveGroupMemberThenLiveMemberIssuesGrant', tests)
        self.assertIn('testReadMessagesUsesListMessagesOnlyAfterActiveMembershipAndDoesNotChangePhase', tests)

    def test_does_not_touch_forbidden_shared_owners(self):
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
        governance = self.read('Core/ChannelGovernanceProjection.swift')
        self.assertIn('kind == .group', governance)
        self.assertIn('MessagingConversationKind', governance)
        self.assertNotIn('AppSession', governance)
        names = {path.name for path in (ROOT / 'Core').glob('Channel*.swift')}
        self.assertEqual(names, {
            'ChannelGovernanceProjection.swift',
            'ChannelRulesAdmission.swift',
            'ChannelMemberAuthorizationProjection.swift',
            'ChannelRevokeIsolation.swift',
        })
        self.assertTrue((ROOT / 'Core' / 'FriendPermissionDistinctFromChannel.swift').is_file())
        self.assertFalse(re.search(r'production.*(password|secret|token)', self.exclusive(), re.I))


if __name__ == '__main__':
    unittest.main()
