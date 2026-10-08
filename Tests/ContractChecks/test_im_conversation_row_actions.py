"""Supplementary integration checks. These do not execute Swift or prove UI parity."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class IMConversationRowActionsContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_normal_list_has_native_swipe_and_accessible_alternative(self):
        source = self.read('App/MessagingHomeView.swift')
        self.assertIn('.swipeActions(edge: .trailing, allowsFullSwipe: false)', source)
        self.assertIn('.contextMenu { rowActions(for: conversation) }', source)
        self.assertIn('expanded?.coordinator(conversation.id)', source)
        self.assertIn('.disabled(!actions.canPrepare)', source)
        self.assertIn('.onChange(of: reader.identity) { _, _ in rowAction = nil }', source)
        self.assertIn('owner?.invalidate(reader: reader, identity: presentation.actions.identity)', source)

    def test_acknowledgment_invalidates_snapshot_for_actual_reread(self):
        home = self.read('App/MessagingHomeView.swift')
        screen = self.read('App/MessagingComponents.swift')
        self.assertIn('model: listModel, load:', home)
        self.assertIn('try await reader.messagingConversations()', home)
        self.assertIn('let owner = listModel', home)
        self.assertIn('{ [weak owner] in', home)
        self.assertIn('refreshRevision: UInt64 = 0', screen)
        self.assertIn('@StateObject private var model: MessagingReadScreenModel<Value>', screen)
        self.assertIn('queue(model.updateInput(reader: reader, refreshRevision: refreshRevision, appearance: appearance))', screen)
        self.assertIn('guard queued == token, hasCurrentBinding(token) else { return }', screen)
        self.assertIn('value = nil; loadedInput = nil; issue = nil', screen)
        self.assertIn('value = result; loadedInput = token.input', screen)
        self.assertNotIn('await reload()', screen)
        for source in [home, self.read('App/IMConversationRowActions.swift'), self.read('Core/IMConversationRowActions.swift')]:
            self.assertNotRegex(source, r'\.unread\s*=(?!=)|\.muted\s*=(?!=)')

    def test_row_adapts_existing_owner_without_new_service_or_dispatch(self):
        source = self.read('Core/IMConversationRowActions.swift')
        self.assertIn('await coordinator.confirm()', source)
        self.assertIn('await coordinator.retryUnchanged()', source)
        self.assertIn('case .outcomeUnknown(let mutation) = state', source)
        self.assertIn('mutation == action.mutation(conversationID: conversation.id)', source)
        self.assertIn('action.matches(receipt)', source)
        for forbidden in ['URLSession', 'URLRequest', 'HTTPTransport', 'IMExpandedWriter(', 'IMExpandedService(', 'writesEnabled:', 'upload(', '.send(']:
            self.assertNotIn(forbidden, source)

    def test_shipping_models_consume_appearance_tokens_without_rebinding_tasks(self):
        sheet = self.read('App/IMConversationRowActions.swift')
        screen = self.read('App/MessagingComponents.swift')
        self.assertIn('guard queued == token, appearance == token.appearance', sheet)
        self.assertIn('guard appearance == token.appearance, executing == token', sheet)
        self.assertIn('Button("action.close") { model.dismiss(); dismiss() }', sheet)
        self.assertIn('model.prepare(.retryUnchanged, appearance: appearance)', sheet)
        self.assertIn('Task { _ = await model.perform(token) }', sheet)
        self.assertIn('Task { await owner.perform(token, load: operation) }', screen)
        self.assertIn('currentRequest == token', screen)
        self.assertIn('next.refreshRevision < input.refreshRevision', screen)
        perform = screen.split('func perform(_ token: MessagingReadScreenToken', 1)[1].split('func disappear()', 1)[0]
        for forbidden in ['appear(', 'updateInput(', 'prepareRefresh(', 'UUID()']:
            self.assertNotIn(forbidden, perform)

    def test_shipping_model_tests_cover_queued_and_suspended_races(self):
        app = self.read('Tests/AppUnitTests/IMConversationRowActionsTests.swift')
        for marker in ['testQueuedUnknownRetryDismissedBeforeExecution',
                       'testOldRetryTokenCannotConsumeOrClearNewAppearance',
                       'testQueuedConfirmCannotOutliveClosedReview',
                       'testInFlightRetryCompletionCannotNotifyOrOverwriteDismissedSheet',
                       'testQueuedAppearanceReadAfterDisappearance',
                       'testOldReadTokenCannotConsumeReplacementAppearance',
                       'testQueuedOlderRevisionCannotCancelOrRebindNewRevision',
                       'testOldInFlightReadSuccessOrFailureCannotOverwriteNewRevision',
                       'testOldToolbarAndRetryInputsCannotBindToNewAccountOrReader',
                       'testCancelledQueuedReadDoesNotDispatchOrKeepSpinnerLocked']:
            self.assertIn(marker, app)

    def test_confirmed_receipt_invalidates_cache_independently_of_sheet_lifetime(self):
        sheet = self.read('App/IMConversationRowActions.swift')
        screen = self.read('App/MessagingComponents.swift')
        invalidate = sheet.index('if matchingReceipt { invalidateList() }')
        retire = sheet.index('guard appearance == token.appearance, executing == token')
        self.assertLess(invalidate, retire)
        self.assertIn('.onChange(of: model.invalidationRevision)', screen)
        invalidation = screen.split('func invalidate(reader source:', 1)[1].split('func disappear()', 1)[0]
        self.assertIn('input.readerID == ObjectIdentifier(source)', invalidation)
        self.assertIn('input.identity == expected', invalidation)
        self.assertIn('invalidationRevision &+= 1', invalidation)
        for forbidden in ['appear(', 'prepareRefresh(', 'Task {', 'load(', 'UUID()']:
            self.assertNotIn(forbidden, invalidation)
        app = self.read('Tests/AppUnitTests/IMConversationRowActionsTests.swift')
        for marker in ['testCloseDuringAcceptedMutationRefreshesVisibleListWithoutRevivingSheet',
                       'testAckWhileListIsAwayOnlyInvalidatesAndReturnStartsFreshRead',
                       'testClosedSheetUnknownOutcomeNeverInvalidatesConfirmedList',
                       'testOldReceiptCannotInvalidateReplacementReaderOrAccountSnapshot',
                       'testInvalidationDiscardsAlreadyStartedPreMutationReadWithoutCancellingNetwork']:
            self.assertIn(marker, app)

    def test_localization_fragment_covers_new_user_text(self):
        fragment = json.loads(self.read('Resources/IMConversationRowActionsLocalizations.fragment.json'))['strings']
        source = self.read('App/IMConversationRowActions.swift') + self.read('App/MessagingHomeView.swift')
        ids = {'im.row.confirm', 'im.row.submitting', 'im.row.retrySame', 'im.row.close', 'im.row.review'}
        for key in set(re.findall(r'"(im\.row\.[A-Za-z]+)"', source)) - ids:
            self.assertIn(key, fragment)
        for key, value in fragment.items():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'], (key, language))

    def test_behavioral_tests_cover_unknown_scope_and_real_app_refresh(self):
        core = self.read('Tests/CoreTests/IMConversationRowActionsTests.swift')
        app = self.read('Tests/AppUnitTests/IMConversationRowActionsTests.swift')
        for marker in ['testUnknownReopenUsesOriginalAction', 'testUnknownMessageCannotBeReplaced', 'testAccountChangeDuringReply', 'testSecondTapCannotDuplicateInFlight', 'testMismatchedReceipt', 'testBusinessRejection']:
            self.assertIn(marker, core)
        for marker in ['UIHostingController', 'MessagingReadScreen(', 'testAcceptedActionRefreshesServerSnapshot', 'testFailedReadbackDoesNotPublishAnInventedZeroBadge', 'testUnknownResultAndDismissal']:
            self.assertIn(marker, app)

if __name__ == '__main__':
    unittest.main()
