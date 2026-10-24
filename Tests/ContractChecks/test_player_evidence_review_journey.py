"""Source-only controls for the normal PLAYER evidence review journey."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PlayerEvidenceReviewJourneyContract(unittest.TestCase):
    def setUp(self):
        self.owner = (ROOT/'App/PlayerTaskEvidenceReview.swift').read_text()
        self.host = (ROOT/'App/PlayerTaskEvidenceView.swift').read_text()
        self.core = (ROOT/'Core/PlayerTaskEvidence.swift').read_text()
        self.device = (ROOT/'Core/PlayDeviceTasks.swift').read_text()
    def test_explicit_output_identity_is_required_even_without_interaction(self):
        guard = 'guard expectedOutputID == nil || expectedOutputID == outputID,\n              capturedInteraction == nil || expectedOutputID != nil,'
        self.assertEqual(self.device.count(guard), 2)
        self.assertNotIn('capturedInteraction == nil || (expectedOutputID != nil && expectedOutputID == outputID)', self.device)
    def test_core_review_pins_full_projection_and_existing_owner(self):
        for x in ['fileprivate let projection: PlayPlayerGameProjection', 'fileprivate let owner: PlayExperienceSession',
                  'currentSession() == context.owner && hasCurrentProjection',
                  'ownsEvidenceReview(context) && acceptsEvidence(context.target) && pending == nil && projection == context.projection',
                  'command: try reviewEvidence(context.target, scan: scan, photo: photo)',
                  'guard !Task.isCancelled, acceptsEvidenceReview(review.context) else { return }', 'await submit(review.command)']:
            self.assertIn(x, self.core)
    def test_input_ticket_is_issued_and_rechecked_before_queued_hardware(self):
        for x in ['struct InputTicket', 'return .init(visit: visit, context: context)',
                  'return canInteract && visit == ticket.visit && player.acceptsEvidenceReview(ticket.context)',
                  'guard !Task.isCancelled, accepts(offered), let offered, let device else { return }']:
            self.assertIn(x, self.owner)
        self.assertIn('let opening = sameTarget ? reviewOwner.captureInput() : nil, outputID = device?.outputID', self.host)
        self.assertEqual(self.host.count('offered: opening'), 8)
    def test_review_contains_concrete_scan_photo_and_output_identity(self):
        for x in ['let scan: String?', 'let photo: Data?', 'let outputID: UUID?',
                  'let outputID, outputID == device.outputID', 'scan: scan, photo: nil, outputID: outputID',
                  'action: .upload, scan: nil, photo: bytes, outputID: outputID',
                  'device.reviewedPhoto(expectedOutputID: outputID)']:
            self.assertIn(x, self.owner)
        self.assertIn('Text(verbatim: scan)', self.owner)
        self.assertIn('UIImage(data: bytes)', self.owner)
    def test_claim_is_synchronous_single_use_and_rechecked_before_async_dispatch(self):
        for x in ['guard canConfirm(offered) else { return nil }', 'claimed = offered.id; working = true; review = nil',
                  'guard claimed == offered.id, working, !Task.isCancelled, current(offered) else',
                  'claimed = nil\n        defer', 'await device?.uploadPhoto(expectedOutputID: outputID)',
                  'await player.submitEvidenceReview(prepared)']:
            self.assertIn(x, self.owner)
        self.assertLess(self.owner.index('guard let claim = owner.claim(offered)'), self.owner.index('Task { if await owner.execute(claim)'))
        self.assertNotIn('uploadPhoto()', self.host+self.owner)
    def test_cancel_preserves_input_but_exit_clears_it_and_changes_visit(self):
        self.assertIn('func cancel(_ offered: Review) { guard review?.id == offered.id else { return }; review = nil }', self.owner)
        self.assertIn('guard accepts(offered) else { return }; manualText = text', self.owner)
        self.assertIn('visit = UUID(); review = nil; claimed = nil; working = false; issue = nil; manualText = ""; device?.cancel()', self.owner)
        self.assertIn('set: { reviewOwner.updateManual($0, offered: opening) }', self.host)
        self.assertNotIn('@State private var manualCode', self.host)
    def test_actual_native_parent_lifetime_is_checked_without_own_review_sheet(self):
        for x in ['guard parent != nil else { return true }', 'current.isBeingDismissed || current.isMovingFromParent',
                  'navigation.topViewController !== current', 'tabs.selectedViewController !== current',
                  'current.presentedViewController?.viewIfLoaded?.window != nil',
                  'guard self.root === root else { return }', 'if root?.isActuallyLeaving == false { return }']:
            self.assertIn(x, self.owner)
        self.assertIn('.background { PlayerTaskEvidenceRoot(owner: reviewOwner)', self.host)
        self.assertIn('if phase == .background { clear(); dismiss() }', self.host)
        self.assertNotIn('.confirmationDialog(', self.host)
        self.assertNotIn('.sheet(', self.host+self.owner)
        self.assertIn('guard self.root === root, root.isActuallyLeaving else { return }; retire()', self.owner)
        self.assertEqual(self.owner.count('owner?.departed(self)'), 2)
        self.assertNotIn('owner?.retire()', self.owner)
        self.assertIn('reviewOwner.target.id == target.id', self.host)
        self.assertIn('.onChange(of: target.id) { _, _ in clear(); dismiss() }', self.host)
    def test_normal_host_uses_stable_owner_and_specific_review(self):
        for x in ['@StateObject private var reviewOwner', 'StateObject(wrappedValue: .init(target: target, player: player, device: device))',
                  'if sameTarget, let offered = reviewOwner.review', '}.id(offered.id)',
                  'prepareCapturedScan(outputID: outputID, offered: opening)',
                  'prepareUpload(outputID: outputID, offered: opening)',
                  'prepareUploadedPhoto(outputID: outputID, offered: opening)']:
            self.assertIn(x, self.host)
        self.assertIn('PlayerTaskEvidenceView(target: target, player: model, device: deviceModel?(target.nodeID))', (ROOT/'App/PlayPlayerAndCircleViews.swift').read_text())
    def test_no_new_network_or_authority_and_unknown_result_stays_original(self):
        new = self.core.split('public struct PlayerTaskEvidenceReviewContext',1)[1]+self.host+self.owner
        for forbidden in ['URLSession', 'transport.send', 'api/', 'retryExact()', '.recover()', 'await recover()', 'enabled.insert', 'grant(', 'award(', 'complete(']:
            self.assertNotIn(forbidden, new)
        runtime=(ROOT/'Core/PlayGameSessionRuntime.swift').read_text()
        self.assertIn('guard pending == nil, phase == "ready"',runtime)
        self.assertIn('if receipt.outcome == "PENDING" { phase = "unknown"; return }',runtime)
        self.assertIn('let value = try await service.playerProjection',runtime)
    def test_catalog_has_exact_bilingual_review_and_two_distinct_actions(self):
        c=json.loads((ROOT/'Resources/PlayerTaskEvidenceReview.xcstrings').read_text())
        self.assertEqual(set(c['strings']), {'title','photo','upload','submit','cancel','expired','uploadDetail','submitDetail'})
        for row in c['strings'].values():
            self.assertEqual(set(row['localizations']), {'en','zh-Hans'})
            for loc in row['localizations'].values():
                self.assertEqual(loc['stringUnit']['state'],'translated'); self.assertTrue(loc['stringUnit']['value'])
        self.assertIn('table: "PlayerTaskEvidenceReview", locale: locale',self.owner)
        self.assertIn('return false\n        case .submit',self.owner)
    def test_authored_native_tests_cover_claim_owner_hardware_and_real_host(self):
        app=(ROOT/'Tests/AppUnitTests/PlayerTaskEvidenceReviewControllerTests.swift').read_text()
        for name in ['testCancelPreservesExactManualInputAndReopenFreezesTrimmedWireValue',
                     'testQueuedConfirmAfterExitAndReopenCannotBorrowNewVisit',
                     'testReplacementPhotoBetweenClaimAndExecuteCannotUploadDifferentBytes',
                     'testUploadAndTaskSubmissionRemainSeparateExplicitConfirmations',
                     'testNativeParentDepartureClearsMemoryAndCancelsQueuedWork',
                     'testNormalHostInitialAppearanceEnablesExactInPageReview']:
            self.assertIn('func '+name+'(',app)
        self.assertIn('UIHostingController(rootView: PlayerTaskEvidenceView(',app)
        self.assertEqual(len(re.findall(r'func test\w+\(',app)),16)
    def test_existing_privacy_keyboard_and_capability_controls_remain(self):
        for x in ['.privacySensitive()', '.focused($manualFocused)', '.scrollDismissesKeyboard(.interactively)',
                  'playerEvidence.keyboard.done', 'playerEvidence.manual', 'playerEvidence.manual.review',
                  'device?.supports(.scan) != true', 'device?.supports(.photo) != true', 'device?.supportsLibraryPhotos != true']:
            self.assertIn(x,self.host)
        self.assertNotIn('TextField("', self.owner)
if __name__ == '__main__': unittest.main()
