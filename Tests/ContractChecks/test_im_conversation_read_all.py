"""Structural checks for the P032 read-all slice; these do not run Swift behavior."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class IMConversationReadAllContractTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_loaded_snapshot_is_frozen_before_explicit_confirmation(self):
        core = self.read('Core/IMConversationReadAll.swift')
        home = self.read('App/MessagingHomeView.swift')
        self.assertIn('let frozen = Self.eligible(conversations)', core)
        self.assertIn('owners = frozen.map { coordinator($0.id) }', core)
        self.assertIn('[.direct, .system, .merchant].contains(conversation.kind)', core)
        self.assertIn('seen.insert(conversation.id).inserted', core)
        self.assertIn('presentReadAll(conversations)', home)
        self.assertIn('listModel.value == conversations', home)
        self.assertIn('listModel.loadedInput == MessagingReadScreenInput(reader: reader, refreshRevision: 0)', home)
        self.assertNotIn('presentReadAll(rows)', home)
        self.assertNotIn('presentReadAll(Array', home)
        init = core.split('public init(conversations:', 1)[1].split('public var isCurrent', 1)[0]
        self.assertNotIn('.review(', init)
        self.assertNotIn('.confirm(', init)

    def test_reuses_existing_session_owner_without_permissions_or_new_writer(self):
        core = self.read('Core/IMConversationReadAll.swift')
        for banned in ['URLSession', 'URLRequest', 'HTTPTransport', 'IMExpandedWriter(',
                       'IMExpandedService(', 'writesEnabled:', '.retryUnchanged(', '.send(', 'upload(']:
            self.assertNotIn(banned, core)
        self.assertIn('await owner.confirm()', core)
        self.assertIn('let mutation = IMMutation.read(conversationID: items[index].id)', core)
        self.assertIn('case .reviewing, .submitting, .outcomeUnknown, .closed: return false', core)

    def test_serial_finite_iteration_rechecks_every_original_owner(self):
        core = self.read('Core/IMConversationReadAll.swift')
        self.assertIn('for index in items.indices', core)
        self.assertIn('guard !stopRequested, !Task.isCancelled, isCurrent else { break }', core)
        self.assertIn('guard let owner = owners[index], matches(owner, at: index)', core)
        self.assertIn('owner.scope.identity == identity && owner.scope.conversationID == items[index].id', core)
        self.assertIn('owner.writer.isConfigured', core)
        self.assertIn('owner.visibleState == .reviewing(mutation)', core)
        self.assertIn('await Task.yield()', core)
        for banned in ['withTaskGroup', 'async let ', 'while true', 'Task {', 'await self.confirm()']:
            self.assertNotIn(banned, core)

    def test_close_retires_queued_token_and_stops_unstarted_work(self):
        app = self.read('App/IMConversationReadAllView.swift')
        self.assertIn('guard queued == token, appearance == token.appearance else { return }', app)
        self.assertIn('appearance = nil; queued = nil; executing = nil; isActionPending = false', app)
        self.assertIn('Button("action.close") { model.dismiss(); dismiss() }', app)
        self.assertIn('.onDisappear { model.dismiss() }', app)
        self.assertIn('guard appearance == token.appearance, executing == token else { return }', app)
        home = self.read('App/MessagingHomeView.swift')
        self.assertIn('.onChange(of: MessagingReadScreenInput(reader: reader, refreshRevision: 0)) { _, _ in retireReviews() }', home)
        self.assertIn('.onDisappear { readAll?.batch.stop() }', home)

    def test_unknown_partial_and_closed_sheet_outcomes_invalidate_real_list_once(self):
        app = self.read('App/IMConversationReadAllView.swift')
        home = self.read('App/MessagingHomeView.swift')
        invalidate = 'if batch.attemptedCount > 0, batch.isCurrent { invalidateList() }'
        self.assertEqual(app.count(invalidate), 1)
        self.assertLess(app.index(invalidate), app.index('guard appearance == token.appearance, executing == token'))
        self.assertIn('owner?.invalidate(reader: reader, identity: presentation.batch.identity)', home)
        self.assertIn('try await reader.messagingConversations()', home)
        for source in [app, home, self.read('Core/IMConversationReadAll.swift')]:
            self.assertNotRegex(source, r'\.unread\s*=(?!=)|\.muted\s*=(?!=)')
        self.assertIn('case .acknowledged(.read)', self.read('Core/IMConversationReadAll.swift'))
        self.assertNotIn('allSucceeded', app)

    def test_summary_distinguishes_each_outcome_and_never_retries(self):
        app = self.read('App/IMConversationReadAllView.swift')
        for value in ['acknowledgedCount', 'unknownCount', 'rejectedCount', 'remainingCount']:
            self.assertIn(value, app)
        self.assertNotIn('retryUnchanged', app)
        self.assertNotIn('im.full.retrySame', app)

    def test_bilingual_fragment_covers_new_visible_keys(self):
        fragment = json.loads(self.read('Resources/IMConversationReadAllLocalizations.fragment.json'))['strings']
        source = self.read('App/IMConversationReadAllView.swift') + self.read('App/MessagingHomeView.swift')
        ids = {'im.readAll.confirmButton', 'im.readAll.stopButton', 'im.readAll.closeButton',
               'im.readAll.reviewSheet', 'im.readAll.entryButton'}
        for key in set(re.findall(r'"(im\.readAll\.[A-Za-z]+)"', source)) - ids:
            self.assertIn(key, fragment)
        for key, value in fragment.items():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'], (key, language))
        self.assertIn('当前已加载', fragment['im.readAll.scopeHint']['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('不含群聊', fragment['im.readAll.scopeHint']['localizations']['zh-Hans']['stringUnit']['value'])

    def test_authored_behavioral_cases_exercise_shipping_owners(self):
        core = self.read('Tests/CoreTests/IMConversationReadAllTests.swift')
        app = self.read('Tests/AppUnitTests/IMConversationReadAllTests.swift')
        for marker in ['testPartialRejectionAndUnknown', 'testPendingReadMuteSendAndReview',
                       'testAccountChangeAfterFirstReply', 'testEachOriginalOwnerRechecksPermission',
                       'testStopDuringSuspendedRequest', 'testCancelledTaskKeepsUnknown',
                       'testLargeFrozenListHasBoundedConcurrency', 'testMismatchedReceipt']:
            self.assertIn(marker, core)
        for marker in ['UIHostingController', 'MessagingReadScreen(', 'testPartialUnknownAlsoRereads',
                       'testFailedReadbackShowsReadError', 'testQueuedConfirmationClose',
                       'testCloseInFlightStopsFurtherItems', 'testOffscreenCompletionOnlyInvalidates',
                       'testOldBatchCannotInvalidateReplacementReader', 'testQueuedAuthorityRevokedAndRestored']:
            self.assertIn(marker, app)


if __name__ == '__main__':
    unittest.main()
