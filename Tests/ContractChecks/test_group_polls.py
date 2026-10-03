"""Native structure only; state/HTTP behavior lives in authored Swift tests, not claimed run here."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path): return (ROOT / path).read_text()

class GroupPollContracts(unittest.TestCase):
    def test_exact_independent_off_by_default_routes(self):
        config = read('Core/BusinessRuntimeConfiguration.swift')
        for feature, path in [('imPollCreate', 'create'), ('imPollVote', 'vote'), ('imPollClose', 'close'), ('imPollResult', 'result')]:
            self.assertIn(f'case .{feature}: paths = ["api/im/poll/{path}"]', config)
        self.assertIn('enabledPaths: Set<String> = []', read('Core/GroupPollService.swift'))
        self.assertIn('static var dormant: Self { .init() }', read('App/NativeRuntimeDependencies.swift'))
        self.assertIn('case .clubChat: paths = ["api/club/chat"]', config)
        self.assertIn('enabled: Bool = false', read('Core/ClubChatService.swift'))
    def test_exact_wire_fields_and_distinct_ids(self):
        service = read('Core/GroupPollService.swift')
        self.assertIn('["poll_id": String(reference.pollID)]', service)
        self.assertIn('OperationAdapterHTTP.json', service)
        model = read('Core/GroupPollContracts.swift')
        for key in ['conversationId', 'clientPollKey', 'question', 'options', 'deadlineAt', 'pollId', 'optionId', 'expectedVersion']:
            self.assertIn(key, model)
        self.assertIn('messageId == reference.messageID', model)
        self.assertIn('creatorMemberId == reference.creatorID', model)
        self.assertIn('selectionMode == "SINGLE", visibility == "PUBLIC"', model)
        self.assertIn('sum == totalVoters', model)
        self.assertNotIn('api/im/send', service)
    def test_fresh_membership_and_durable_replay_locks(self):
        source = read('Core/GroupPollCoordinator.swift')
        for check in ['let latest = try await client.result', 'let member = try await membership()', 'try journal.write(fresh)', 'try receipt.validateReceipt', 'reader.identity == scope.identity', 'self.generation == generation', 'poll.status == "CLOSED"']:
            self.assertIn(check, source)
        self.assertLess(source.index('try journal.write(fresh)'), source.index('try await client.perform'))
        self.assertIn('existing.operationID.uuidString.lowercased() == draft.clientPollKey', source)
        self.assertNotIn('retryVote', source)
        self.assertNotIn('retryClose', source)
    def test_normal_group_entries_and_type_four_rendering(self):
        self.assertIn('conversation?.supportsGroupPolls == true', read('App/MessagingHistoryView.swift'))
        self.assertIn('poll.createEntry', read('App/MessagingHistoryView.swift'))
        self.assertIn('case 4:', read('App/MessagingMessageDetailView.swift'))
        self.assertIn('poll.messageEntry', read('App/MessagingMessageDetailView.swift'))
        self.assertIn('SessionClubChatView(clubID: id, session: session)', read('App/ClubDetailView.swift'))
        self.assertIn('conversationID: conversation.id, conversation: conversation', read('App/ClubChatEntryView.swift'))
        self.assertIn('counterparty?.bizKey == "club_\\(clubID)"', read('Core/ClubChatService.swift'))
    def test_session_role_scope_is_captured_in_normal_composition(self):
        session = read('App/AppSession.swift')
        chunk = session[session.index('private var clubChatOwners:'):session.index('private let messagingService:')]
        self.assertGreaterEqual(chunk.count('self.currentRuntimeDependencyContext == captured'), 4)
        self.assertIn('composition.storage.operationJournal()', chunk)
        self.assertIn('clubChatOwners.removeAll(); groupPollOwners.removeAll()', session)
    def test_ui_is_localized_and_review_based(self):
        source = read('App/GroupPollViews.swift') + read('App/ClubChatEntryView.swift')
        keys = set(re.findall(r'"((?:poll|club\.chat)\.[A-Za-z]+)"', source))
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        accessibility_only = {'poll.screen','poll.cancel','poll.result','poll.loading','poll.refresh','poll.confirm','poll.cancelReview','poll.reviewClose','poll.result.question','poll.retryCreate','poll.acknowledged','poll.createAnother','club.chat.screen'}
        for key in keys - accessibility_only:
            self.assertIn(key, catalog, key)
            self.assertTrue(catalog[key]['localizations']['en']['stringUnit']['value'])
            self.assertTrue(catalog[key]['localizations']['zh-Hans']['stringUnit']['value'])
        for evidence in ['owner.cancelReview()', 'owner.suspend()', '.focused($focused)', '.confirmationDialog', '.privacySensitive()', 'poll.confirm']:
            self.assertIn(evidence, source)
    def test_option_label_identifier_does_not_override_choose_button(self):
        source = read('App/GroupPollViews.swift')
        self.assertIn('Text(verbatim: option.content).frame(maxWidth: .infinity, alignment: .leading)\n                            .accessibilityIdentifier("poll.result.option.\\(option.id)")', source)
        self.assertNotIn('}.accessibilityIdentifier("poll.result.option.\\(option.id)")', source)
        self.assertIn('}.accessibilityIdentifier("poll.choose.\\(option.id)")', source)
    def test_fixture_has_no_transport_and_excludes_production_session(self):
        fixture = read('App/GroupPollFixture.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('URLSession', fixture)
        self.assertNotIn('UserDefaults', fixture)
        self.assertGreaterEqual(read('App/QuestifyApp.swift').count('--group-poll-fixture'), 3)
        self.assertIn('MessagingHomeView(reader: store', fixture)
    def test_authored_behavior_coverage_remains_discoverable(self):
        core = read('Tests/CoreTests/GroupPollTests.swift')
        self.assertGreaterEqual(len(re.findall(r'func test', core)), 24)
        ui = read('Tests/AppUITests/GroupPollUITests.swift')
        for case in ['testNormalGroupMessageRendersAndVoteRequiresConfirmation', 'testUnknownVoteHasReadbackButNoRetryVoteOrNewChoice', 'testCreatorCloseReviewCanBeCancelledAndOtherMemberCannotClose', 'testDormantChineseGroupPollShowsExplanationWithoutSend', 'testCreateEntryDraftCancellationAndOptionLimits']:
            self.assertIn(case, ui)

if __name__ == '__main__': unittest.main()
