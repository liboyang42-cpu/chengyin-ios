"""Supplementary source wiring assertions. Not Swift compilation or UI execution."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class IMConversationReplyPolicyContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_policy_blocks_only_confirmed_system_kind_and_keeps_read_mute(self):
        source = self.read('Core/IMConversationReplyPolicy.swift')
        self.assertIn('conversation?.kind == .system', source)
        self.assertIn('case .read, .mute: return true', source)
        self.assertIn('case .send: return permitsReply', source)
        self.assertIn('mutation.conversationID == conversationID', source)
        self.assertNotIn('HTTP', source)

    def test_real_history_mounts_notice_instead_of_system_composer(self):
        source = self.read('App/MessagingHistoryView.swift')
        self.assertIn('if replyPolicy.isSystemNotice, currentHistoryReady', source)
        self.assertIn('else if replyPolicy.permitsReply, let sender', source)
        self.assertIn('canReply: { authority.permitsReply(lease) }', source)
        self.assertIn('replyPolicy: replyPolicy', source)
        self.assertIn('isConversationCurrent: { authority.isCurrent(lease) }', source)
        self.assertIn('loadedReaderID == ObjectIdentifier(reader)', source)
        self.assertIn('let lease = authority.bind(reader: reader, policy: replyPolicy, ready: currentHistoryReady)', source)
        self.assertIn('guard lease == expected, let input, let reader', source)
        self.assertIn('loadedIdentity == reader.identity', source)
        reload = source.split('private func reload() async', 1)[1].split('private func loadEarlier', 1)[0]
        self.assertLess(reload.index('replyAuthority.invalidate()'), reload.index('loadedIdentity = nil'))
        terminal = source.split('if failure.isTerminal {', 1)[1].split('} else', 1)[0]
        self.assertLess(terminal.index('replyAuthority.invalidate()'), terminal.index('history ='))

    def test_controls_keep_read_mute_outside_reply_only_sections(self):
        source = self.read('App/IMExpandedViews.swift').split('private struct IMMutationSummary:', 1)[0]
        self.assertLess(source.index('Section("im.full.conversation")'), source.index('if permitsReply {'))
        for key in ['im.full.image', 'im.full.route', 'im.full.location']:
            self.assertGreater(source.index('Section("' + key + '")'), source.index('if permitsReply {'))
        self.assertIn('if permits(mutation) { Button("im.full.retrySame") { submit(.retry) } }', source)
        self.assertIn('model.prepare(operation, permits: permits)', source)
        self.assertIn('Task { await model.perform(token, permits: permits) }', source)

    def test_text_tokens_are_created_before_tasks_and_consumed_before_live_gate(self):
        source = self.read('App/MessageActionComposer.swift')
        self.assertIn('model.prepare(.send(model.draft), identity: identity, canReply: ready)', source)
        self.assertIn('model.prepare(.retry(clientID), identity: identity, canReply: ready)', source)
        self.assertIn('Task { await model.perform(token, canReply: { ready }) }', source)
        perform = source.split('@discardableResult func perform', 1)[1].split('@MainActor struct', 1)[0]
        self.assertLess(perform.index('queued = nil'), perform.index('canReply()'))
        self.assertIn('appearance == token.appearance', perform)
        self.assertIn('coordinator.pendingClientMessageID == clientID', perform)
        self.assertNotIn('UUID()', perform)
        self.assertIn('.onDisappear { model.retire(); confirmsRetry=false; typing=false }', source)

    def test_expanded_tokens_preserve_exact_pending_mutation(self):
        source = self.read('App/IMExpandedViews.swift').split('/// Host presents this', 1)[0]
        perform = source.split('@discardableResult func perform', 1)[1]
        self.assertLess(perform.index('queued = nil'), perform.index('permits(token.mutation)'))
        self.assertIn('pending == token.mutation', perform)
        self.assertIn('owner.isCurrent', perform)
        self.assertIn('await owner.retryUnchanged()', perform)
        self.assertNotIn('UUID()', perform)

    def test_media_child_guards_queued_picker_upload_and_local_review(self):
        source = self.read('App/IMExpandedViews.swift')
        self.assertIn('IMImageComposeView(owner: uploadOwner, identity: identity, canReply: { permitsReply })', source)
        self.assertIn('owner.visibleState == token.state', source)
        self.assertIn('model.apply(url, canReply: canReply(), consume: onReviewImage)', source)
        self.assertIn('Task { await model.perform(token, canReply: { identity == model.owner.scope.identity && canReply() }) }', source)
        for forbidden in ['requestWhenInUseAuthorization', 'CLLocationManager', 'import MapKit']:
            self.assertNotIn(forbidden, source)

    def test_bilingual_fragment_covers_new_text(self):
        fragment = json.loads(self.read('Resources/IMConversationReplyPolicyLocalizations.fragment.json'))['strings']
        source = self.read('App/MessagingHistoryView.swift') + self.read('App/IMExpandedViews.swift')
        keys = set(re.findall(r'(?:Text|Label)\("(im\.reply\.[A-Za-z]+)"', source))
        self.assertEqual(keys, set(fragment))
        for value in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'])

    def test_shipping_owner_tests_cover_revocation_unknown_and_media_return(self):
        source = self.read('Tests/AppUnitTests/IMConversationReplyPolicyAppTests.swift')
        for name in ['testSystemReadMuteStillDispatchThroughExistingOwner',
                     'testQueuedTextRevocationConsumesTokenWithoutRevival',
                     'testClosedOrReplacedTextAppearanceCannotDispatchOldToken',
                     'testTextTokenCannotCrossSameAccountEpochChange',
                     'testUnknownTextSurvivesCloseAndRetriesOnlyOriginalIDAfterNewTap',
                     'testLateTextCompletionDoesNotClearReopenedDraft',
                     'testQueuedExpandedReplyRevalidatesSystemPolicyAndCannotRevive',
                     'testExpandedUnknownIsNotReplacedBySystemReadAndRetryStaysExact',
                     'testMediaQueuedUploadRevokedNeverWritesAndRequiresNewTap',
                     'testNormalMediaChildReturnsLocalReviewWithoutParentAppearanceOrAutomaticSend',
                     'testRetainedTextClosureRechecksLatestPolicyLeaseWithoutLifecycleCleanup',
                     'testRetainedExpandedClosureCannotAdoptReplacementReaderWithSameIdentity',
                     'testRetainedMediaClosureAndReadLeaseRejectRevokedHistory']:
            self.assertIn(name, source)

if __name__ == '__main__':
    unittest.main()
