"""Finite M1/M2/T1 source contracts; these do not compile Swift or prove UI behavior."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path): return (ROOT / path).read_text()

class ReferenceChatTaskContracts(unittest.TestCase):
    def test_shared_bubble_is_presentation_only(self):
        text = read('App/ChatMessageBubble.swift')
        for forbidden in ['URLSession', 'AsyncImage', 'import AVFoundation', 'Coordinator', 'MessagingMessage', 'ShopNPCMessage', 'delivered', 'readReceipt']:
            self.assertNotIn(forbidden, text)
        self.assertIn('typeSize.isAccessibilitySize ? 0 : 28', text)
        self.assertIn('fixedSize(horizontal: false, vertical: true)', text)
        for file in ['MessagingHistoryView.swift', 'ShopNPCView.swift', 'MerchantNPCViews.swift']:
            self.assertIn('ChatMessageBubble(', read('App/' + file))
    def test_history_preserves_authority_and_pagination_anchor(self):
        text = read('App/MessagingHistoryView.swift')
        for token in ['message.senderID == accountID && accountID > 0', 'scrollPosition(id: $visibleMessageID, anchor: .top)', 'visibleMessageID = anchor', 'loadedIdentity == reader.identity', 'generation == request', 'MessagingMessageDetailView', 'MessageActionComposer', 'scrollDismissesKeyboard(.interactively)']:
            self.assertIn(token, text)
    def test_im_outcomes_not_mapped_to_delivery(self):
        text = read('App/MessageActionComposer.swift')
        for token in ['case .sending:', 'case .outcomeUnknown,.rejected:', 'message.send.unknown', 'message.send.accepted', 'model.draft="";confirmsRetry=false', 'message.send.keyboard.done']:
            self.assertIn(token, text)
        self.assertNotIn('checkmark', text)
    def test_npc_requires_review_and_preserves_cancelled_draft(self):
        text = read('App/ShopNPCView.swift')
        self.assertIn('coordinator.reviewText(draft)', text)
        self.assertIn('await coordinator.transmit(reviewID: review.id)', text)
        self.assertIn('coordinator.pending == nil, coordinator.failure == nil', text)
        self.assertIn('Button(role: .cancel) { coordinator.cancelReview(); revision += 1 }', text)
        self.assertIn('.safeAreaInset(edge: .bottom) { composer }', text)
    def test_npc_lifecycle_and_voice_grants_still_fail_closed(self):
        text = read('App/ShopNPCView.swift')
        for token in ['shopNPC.disclosure', 'shopNPC.assistant', 'shopNPC.voiceDisclosure', 'shopNPC.transmissionDisclosure', '.onDisappear { invalidate() }', '.onChange(of: coordinator.scope)', '.onChange(of: coordinator.grants)', 'phase != .active', 'capture?.cancel()', 'grants.voiceAllowed', 'grants.microphone', 'startAfterExplicitMicrophoneIntent']:
            self.assertIn(token, text)
        self.assertNotIn('requestRecordPermission', text)
    def test_merchant_resources_and_chat_have_separate_authority(self):
        text = read('App/MerchantNPCViews.swift')
        for token in ['MerchantNPCChatCoordinator', 'MerchantNPCResourcesCoordinator', 'model.coordinator.canSend', 'model.coordinator.canRetry', 'model.coordinator.invalidate()', 'referenceChat.merchantAI', 'reply.safeText', 'reply.outcomeStatus']:
            self.assertIn(token, text)
        self.assertNotIn('ShopNPCCoordinator', text)
    def test_progress_never_infers_total_or_success(self):
        text = read('Core/PlayTaskSummaryPresentation.swift')
        for token in ['snapshot.displayedDoneCount', 'snapshot.result.total', 'count > 0', '(0...count).contains(done)', 'candidates.count == 1', 'snapshot.availability == .active']:
            self.assertIn(token, text)
        for forbidden in ['total = snapshot.visibleNodes.count', 'func submit', 'Timer', 'URLSession']:
            self.assertNotIn(forbidden, text)
    def test_status_uses_existing_server_facts(self):
        text = read('Core/PlayTaskSummaryPresentation.swift')
        self.assertIn('if snapshot.isDone(node)', text)
        self.assertIn('snapshot.isLocked(node)', text)
        self.assertIn('snapshot.result.mode == 2 && node.selfReported == true', text)
        self.assertIn('else { self = .unknown }', text)
    def test_summary_is_bilingual_phase_only_and_motion_aware(self):
        text = read('App/PlayTaskSummaryView.swift')
        for token in ['@Environment(\\.locale)', 'appLocalized("referenceTask.completedCount", locale: locale)', 'referenceTask.phaseOnly', '@QuestifyReduceMotion', '$0.animation = nil', 'QuestifyStatusBadge']:
            self.assertIn(token, text)
        self.assertNotIn('String(localized:', text)
    def test_current_task_uses_existing_destination_and_unknown_gate(self):
        text = read('App/PlayExperienceView.swift')
        for token in ['model.hasCurrentMediaSnapshot, !model.unresolved', 'PlayTaskSummaryPresentation(snapshot: snapshot).currentNodeID', 'Button("referenceTask.open") { selectedNode = id }', '.navigationDestination(item: $selectedNode)']:
            self.assertIn(token, text)
    def test_key_only_fragment_is_additive_and_bilingual(self):
        fragment = json.loads(read('Resources/ReferenceChatTaskLocalizations.fragment.json'))['strings']
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 10)
        for key, value in fragment.items():
            self.assertTrue(key.startswith(('referenceChat.', 'referenceTask.')))
            self.assertEqual(catalog[key], value)
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
    def test_runtime_regressions_authored_without_claiming_execution(self):
        ui = read('Tests/AppUITests/ReferenceChatTaskFlowTests.swift')
        for token in ['testNPCCancelReviewRetainsDraftAndCanReopen', 'testNPCPendingDisablesDuplicateTransmissionAndScopeClearsPrivateText', 'testNPCChineseMaximumTextKeyboardAndReduceMotion', 'testMessageEarlierPageAndDetailReturnRetainHistory', 'testUnknownTotalShowsPhaseWithoutPercentage']:
            self.assertIn(token, ui)
        self.assertEqual(read('Tests/CoreTests/PlayTaskSummaryPresentationTests.swift').count('func test'), 10)
        self.assertEqual(read('Tests/AppUnitTests/ReferenceChatTaskAppTests.swift').count('func test'), 3)
