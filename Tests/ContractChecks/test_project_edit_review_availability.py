"""CI138 UI74: Review uses its existing signed-in lease, not guest editability.

Source checks only; the authored AppUnit and unchanged UI74 require Apple execution.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CAN_EDIT = '    var canEdit: Bool { ownsVisit && !coordinator.hasUnconfirmedChapterRemoval && loadedSnapshot && loadedSession == coordinator.session && coordinator.snapshot != nil && !busy && !coordinator.isLocked && coordinator.state != .simulated && coordinator.state != .acknowledged && coordinator.state != .blocked && !hasRestore }'
CAN_REVIEW = '    var canReview: Bool { currentReviewLease() != nil }'
BUTTON = '                Button("projectEdit.review") { focusedField = nil; model.review() }\n                    .buttonStyle(.borderedProminent).disabled(!model.canReview).accessibilityIdentifier("projectEdit.review")'


def verify(view, prepared):
    if view.count(CAN_EDIT) != 1 or view.count(CAN_REVIEW) != 1 or view.count(BUTTON) != 1:
        raise ValueError('Review availability must reuse the existing lease without changing guest editability')
    for required in (
        'guard canEdit, let session = coordinator.session, let identity = coordinator.identity else { return nil }',
        'return .init(session: session, identity: identity, incarnation: editorIncarnation)',
        'reviewLease.session == coordinator.session && reviewLease.identity == coordinator.identity &&',
        'reviewLease.incarnation == editorIncarnation',
    ):
        if prepared.count(required) != 1:
            raise ValueError('The existing session, identity and incarnation fences must remain intact')
    if 'guard let lease = currentReviewLease() else { return }' not in view:
        raise ValueError('The action must retain its independent lease guard')


class ProjectEditReviewAvailabilityContracts(unittest.TestCase):
    def sources(self):
        return ((ROOT / 'App/ProjectEditView.swift').read_text(),
                (ROOT / 'App/ProjectEditPreparedReview.swift').read_text())

    def test_button_uses_same_side_effect_free_lease_as_action(self):
        verify(*self.sources())

    def test_guest_editing_and_save_rules_are_preserved(self):
        view, _ = self.sources()
        self.assertIn(CAN_EDIT, view)
        self.assertIn('var canSaveLocal: Bool { canEdit && coordinator.session != nil }', view)
        self.assertIn('var fullEdit: Bool { canEdit && coordinator.snapshot?.scope == .full }', view)

    def test_guest_signed_in_remount_and_session_change_regressions_are_authored(self):
        source = (ROOT / 'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift').read_text()
        self.assertEqual(source.count('func test'), 10)
        for required in (
            'func testReviewAvailabilityReusesTheSignedInLeaseWithoutWriting()',
            'func testSignOutAndRemountDisableReviewWhileGuestDraftStaysEditable()',
            'func testAccountOrEpochChangeCannotReuseTheOldReviewLease()',
            'owner.session = nil; model.coordinator.synchronizeSession()',
            'let remounted = ProjectEditModel(coordinator: model.coordinator)',
            'XCTAssertTrue(remounted.canEdit); XCTAssertTrue(remounted.fullEdit)',
            'XCTAssertFalse(remounted.canSaveLocal); XCTAssertFalse(remounted.canReview)',
            'XCTAssertEqual(storage.data, bytes); XCTAssertEqual(storage.writes, writes)',
            'XCTAssertTrue(service.submissions.isEmpty)',
            'XCTAssertNotEqual(currentLease, oldLease)',
        ):
            self.assertIn(required, source)

    def test_weaker_availability_or_changed_lease_fences_are_rejected(self):
        view, prepared = self.sources()
        mutations = (
            (view.replace(CAN_REVIEW, '    var canReview: Bool { canEdit }'), prepared),
            (view.replace(CAN_REVIEW, '    var canReview: Bool { coordinator.session != nil }'), prepared),
            (view.replace(CAN_REVIEW, CAN_REVIEW + '\n' + CAN_REVIEW), prepared),
            (view.replace('.disabled(!model.canReview)', '.disabled(!model.canEdit)'), prepared),
            (view.replace(CAN_EDIT, CAN_EDIT.replace('ownsVisit && ', '')), prepared),
            (view, prepared.replace('let session = coordinator.session, ', '')),
            (view, prepared.replace('reviewLease.session == coordinator.session && ', '')),
            (view, prepared.replace('reviewLease.incarnation == editorIncarnation', 'true')),
        )
        for changed_view, changed_prepared in mutations:
            with self.subTest(view=changed_view == view, prepared=changed_prepared == prepared):
                with self.assertRaises(ValueError):
                    verify(changed_view, changed_prepared)


if __name__ == '__main__':
    unittest.main()
