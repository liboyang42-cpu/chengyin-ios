"""Privacy projection wiring checks; not Swift/Apple execution evidence."""
import json
import re
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class IMMessageVisibilityContract(unittest.TestCase):
    def read(self, name): return (ROOT/name).read_text()
    def test_payload_is_dropped_before_rendering(self):
        model = self.read('Core/MessagingContracts.swift')
        for text in ['MessagingMessageStatus', 'case normal, recalled, blocked, unknown',
                     'guard status == .normal else', 'content = nil; extraJSON = nil',
                     'senderName = nil; senderAvatar = nil', 'lastMessageType = nil', 'lastMessageText = nil']:
            self.assertIn(text, model)
        self.assertLess(model.index('guard status == .normal else'), model.index('content = try c.decodeIfPresent'))
    def test_all_payload_projection_surfaces_require_visibility(self):
        for path in ['Core/SocialMessageMedia.swift', 'Core/GroupPollContracts.swift', 'Core/IMExpandedContracts.swift']:
            self.assertIn('message.isPayloadVisible', self.read(path))
        detail = self.read('App/MessagingMessageDetailView.swift')
        self.assertIn('messaging.message.recalled', detail)
        self.assertIn('messaging.message.withheld', detail)
        self.assertIn('if let currentMessage { return currentMessage() }', detail)
        self.assertIn('currentSnapshot?.isPayloadVisible == true', detail)
        self.assertIn('currentSnapshot == message', detail)
        self.assertIn('currentMessage: { history.messages.first { $0.id == message.id } }', self.read('App/MessagingHistoryView.swift'))
        media = self.read('App/SocialMessageMediaView.swift')
        self.assertIn('guard run == generation, isMessageCurrent()', media)
        self.assertIn('.onChange(of: isMessageCurrent())', media)
    def test_actual_response_and_unknown_legacy_tests_are_authored(self):
        tests = self.read('Tests/CoreTests/MessagingVisibilityTests.swift')
        for text in ['Synthetic recalled content', '"status" : 1', 'testActualServiceRecalledEnvelope',
                     'testRecalledBlockedUnknownMissingAndMalformedStatus',
                     'testExplicitNormalStatusPreservesTextImageCardAndPollProjections',
                     'testConversationSummaryWithoutStatusProvenance',
                     'testRefreshedRecalledRowAndHistoryReset']:
            self.assertIn(text, tests)
    def test_shared_account_media_fixture_is_explicitly_normal(self):
        source = self.read('Core/SocialAccountSyntheticFixtures.swift')
        body = source.split('public static func imageMessage()', 1)[1]
        match = re.search(r'Data\(#"(.*?)"#\.utf8\)', body)
        self.assertIsNotNone(match)
        row = json.loads(match.group(1))
        self.assertIs(type(row.get('status')), int)
        self.assertEqual(row['status'], 0)
        self.assertEqual(row['msgType'], 2)
        self.assertEqual(row['content'], 'https://media.example.test/synthetic.png')
        regression = self.read('Tests/CoreTests/SocialMessageMediaTests.swift')
        self.assertIn('testSharedAccountMediaFixtureHasExplicitNormalStatusAndValidProjection', regression)
        self.assertIn('SocialAccountSyntheticFixtures.imageMessage()', regression)
