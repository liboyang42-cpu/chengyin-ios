"""Focused source checks; Apple compilation and UI execution are separate."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClubManagementReviewOwnerContracts(unittest.TestCase):
    def read(self, p): return (ROOT / p).read_text()
    def test_detail_mounts_only_concrete_uuid_presenter(self):
        v=self.read('App/ClubManagementView.swift')
        self.assertIn('if let item = reviewOwner.item {',v)
        self.assertIn('confirmationContent(item)\n                }.id(item.id)',v)
        self.assertNotIn('.sheet(isPresented: Binding(get: { confirmation',v)
        self.assertIn('ClubManagementReviewLifetime(covered:',v)
    def test_old_buttons_capture_attachment_and_context(self):
        v=self.read('App/ClubManagementView.swift')
        self.assertIn('let attachment = reviewOwner.attachment, source = reviewContext',v)
        self.assertIn('prepare(action, memberID: memberID, attachment: attachment, source: source)',v)
        self.assertIn('let attachment, source == reviewContext',v)
    def test_stale_cancel_cannot_operate_on_new_review(self):
        o=self.read('App/ClubManagementReviewOwner.swift')
        self.assertIn('guard isPresented, item == expected else { return false }',o)
        self.assertIn('guard !presented, self.cancel(expected) else { return }',o)
        self.assertIn('cancelled(expected)',o)
    def test_original_fresh_permission_prepare_and_dispatch(self):
        v=self.read('App/ClubManagementView.swift')
        self.assertEqual(v.count('coordinator.confirm(pending)'),1)
        self.assertIn('coordinator.prepare(clubID: clubID, action: action, memberID: memberID, expectedIdentity: identity, ownerID: ownerID)',v)
        self.assertIn('reviewOwner.stage(pending, attachment: attachment, context: source, active: scenePhase == .active)',v)
        self.assertIn('reviewOwner.permitsDispatch(item, context: reviewContext, active: scenePhase == .active)',v)
    def test_claim_is_synchronous_and_exact(self):
        v=self.read('App/ClubManagementView.swift');o=self.read('App/ClubManagementReviewOwner.swift')
        self.assertLess(v.index('guard reviewOwner.claim(item'),v.index('Task { await confirm(pending, item: item) }'))
        self.assertIn('claimed = expected.id; isPresented = false',o)
        self.assertIn('claimed == expected.id && expected.context == context',o)
    def test_real_departure_retires_current_attachment_only(self):
        v=self.read('App/ClubManagementView.swift');o=self.read('App/ClubManagementReviewOwner.swift')
        self.assertIn('if reviewOwner.depart(attachment) { detailHostVisible = false; leaveScreen() }',v)
        self.assertIn('guard self.attachment == attachment else { return false }',o)
        self.assertIn('if parent != nil { wasAttached = true } else if wasAttached { departed() }',o)
        self.assertIn('controller.isBeingDismissed || controller.isMovingFromParent',o)
        self.assertIn('controller.presentedViewController != nil { covered(); return }',o)
    def test_foreground_does_not_reactivate_hidden_detail(self):
        v=self.read('App/ClubManagementView.swift')
        self.assertIn('else if detailHostVisible { reviewOwner.appear(reviewContext) }',v)
        self.assertIn('if phase != .active { leaveScreen() }',v)
        self.assertIn('reviewOwner.attachment == presentedAttachment',v)
    def test_context_captures_access_and_coordinator(self):
        v=self.read('App/ClubManagementView.swift');o=self.read('App/ClubManagementReviewOwner.swift')
        self.assertIn('screenContext == readContext',v)
        self.assertIn('access: ObjectIdentifier(access), coordinator: ObjectIdentifier(coordinator)',v)
        self.assertIn('self.context == context && (visible || covered)',o)
    def test_ack_and_unknown_keep_existing_meaning(self):
        v=self.read('App/ClubManagementView.swift')
        self.assertIn('if case .acknowledged = state {',v)
        self.assertIn('selection = nil\n            onMembershipChanged?()',v)
        self.assertIn('case .received(let result): snapshot = result',v)
        self.assertIn('case .unavailable: readbackUnavailable = true',v)
        self.assertIn('case .outcomeUnknown:',v)
        o=self.read('App/ClubManagementReviewOwner.swift')
        for x in ['perform(', 'URLSession', 'UserDefaults', 'APIConfiguration'] : self.assertNotIn(x,o)
    def test_original_action_eligibility_remains(self):
        v=self.read('App/ClubManagementView.swift')
        for x in ['snapshot.allows(.approve, memberID: id)','snapshot.allows(.remove, memberID: id)','!state.preventsNewAction','!stale','pending.identity == identity'] : self.assertIn(x,v)
    def test_original_labels_no_new_catalog_dependency(self):
        v=self.read('App/ClubManagementView.swift')
        for x in ['club.management.target','club.management.club','club.management.confirm','club.management.cancel','club.management.readbackUnavailable']:self.assertIn(x,v)
    def test_model_and_real_host_cases_are_authored_separately(self):
        t=self.read('Tests/AppUnitTests/ClubManagementReviewOwnerTests.swift')
        for x in ['testUnknownDoesNotReplayOrBecomeAcknowledged','testRealHostInitiallyNilPresentsCancelsAndReopensConcreteReview','testRealHostDismantleRetiresReviewAndCannotReappearFromOldBinding','testActualAttachmentDepartureRejectsLatePrepare','UIHostingController']: self.assertIn(x,t)
if __name__ == '__main__': unittest.main()
