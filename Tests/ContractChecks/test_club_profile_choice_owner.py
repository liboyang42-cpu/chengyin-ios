"""Focused presentation source checks, not SwiftUI execution."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


def require_specific_owner(source):
    close = span(source, 'func close(expectedID:', 'func presentationBinding(')
    binding = span(source, 'func presentationBinding(', 'func apply(')
    owner = span(source, 'struct ClubProfileChoicePresentationOwner:', 'private struct ClubProfileChoiceEditor:')
    for token in ['guard session?.id == expectedID else { return }', 'session = nil']:
        if token not in close:
            raise AssertionError('Missing exact close gate')
    for token in ['self.session == expected && isCurrent()', 'self.close(expectedID: expected.id)']:
        if token not in binding:
            raise AssertionError('Missing binding owner gate')
    for token in ['controller.session == session', 'context == session.context', 'draft == session.draft.source',
                  'isCurrent(session.context)', 'controller.presentationBinding(for: session, isCurrent: { current })',
                  'onDismiss: { controller.close(expectedID: session.id) }',
                  'cancel: { controller.close(expectedID: session.id) }',
                  'guard current,', 'controller.apply(edited, session: session, current: draft, isCurrent: isCurrent)',
                  'if !valid { controller.close(expectedID: session.id) }']:
        if token not in owner:
            raise AssertionError('Missing concrete owner fence: ' + token)
    if 'controller.close()' in owner:
        raise AssertionError('Unstamped presentation callback')


class ClubProfileChoiceOwnerContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.view = (ROOT / 'App/ClubProfileChoiceEditor.swift').read_text()
        cls.host = (ROOT / 'App/ClubOperationsViews.swift').read_text()

    def test_concrete_uuid_controls_binding_cancel_apply_and_dismiss(self):
        require_specific_owner(self.view)

    def test_each_missing_owner_gate_is_detected(self):
        for token in ['guard session?.id == expectedID else { return }', 'self.session == expected && isCurrent()',
                      'self.close(expectedID: expected.id)', 'draft == session.draft.source',
                      'onDismiss: { controller.close(expectedID: session.id) }',
                      'cancel: { controller.close(expectedID: session.id) }', 'guard current,']:
            with self.subTest(token=token):
                with self.assertRaises(AssertionError):
                    require_specific_owner(self.view.replace(token, '', 1))

    def test_lazy_control_is_observer_without_presentation_or_cleanup(self):
        control = span(self.view, 'struct ClubProfileChoiceControl:', 'struct ClubProfileChoicePresentationOwner:')
        self.assertIn('@ObservedObject var controller: ClubProfileChoiceController', control)
        for token in ['@StateObject', '.sheet(', '.onDisappear', '.onChange', 'controller.close(']:
            self.assertNotIn(token, control)
        self.assertIn('controller.open(kind: kind, source: draft, context: context, isCurrent: isCurrent)', control)

    def test_normal_stable_workspace_owns_both_controls_and_concrete_owner(self):
        for token in ['@StateObject private var profileChoice = ClubProfileChoiceController()',
                      '.background {\n            if let session = profileChoice.session {',
                      'ClubProfileChoicePresentationOwner(controller: profileChoice, session: session, draft: $draft,',
                      '.id(session.id)', 'choiceController: profileChoice',
                      'kind: .type, draft: $draft, context: choiceContext, isCurrent: choiceIsCurrent, controller: choiceController',
                      'kind: .directions, draft: $draft, context: choiceContext, isCurrent: choiceIsCurrent, controller: choiceController']:
            self.assertIn(token, self.host)
        self.assertEqual(self.host.count('ClubProfileChoicePresentationOwner('), 1)

    def test_host_keeps_live_identity_profile_revision_and_state_fences(self):
        live = span(self.host, 'private func profileChoiceIsCurrent(', '@ViewBuilder private func content(')
        for token in ['scenePhase == .active', 'screenIdentity == identity', '!loading', '!state.locksForm', 'review == nil',
                      'expected.matches(target: target, identity: identity, access: access, profile: snapshot?.profile, sourceRevision: artworkRevision)']:
            self.assertIn(token, live)
        self.assertIn('.onChange(of: profileChoiceContext)', self.host)
        self.assertIn('if phase != .active { profileChoice.close() }', self.host)
        self.assertIn('.onDisappear {\n            profileChoice.close()', self.host)

    def test_only_current_apply_assigns_the_parent_local_draft(self):
        owner = span(self.view, 'struct ClubProfileChoicePresentationOwner:', 'private struct ClubProfileChoiceEditor:')
        self.assertEqual(owner.count('draft = next; return true'), 1)
        for token in ['.send(', '.perform(', 'coordinator', 'requestID', '.create(', '.update(']:
            self.assertNotIn(token, owner)
        self.assertIn('edited.source == expected.draft.source', self.view)
        self.assertIn('let next = try? edited.applying(to: current)', self.view)

    def test_editor_preserves_local_validation_max_three_and_known_catalogs(self):
        editor = self.view.split('private struct ClubProfileChoiceEditor:', 1)[1]
        for token in ['ClubOperationsCatalog.types', 'ClubOperationsCatalog.directions', 'draft.directions.count >= 3',
                      'draft.isValid', 'guard isCurrent()', 'Button("action.cancel", action: cancel)']:
            self.assertIn(token, editor)
        self.assertIn('.presentationDetents([.medium, .large])', self.view)

    def test_authored_native_regressions_invoke_real_binding_and_controller(self):
        tests = (ROOT / 'Tests/AppUnitTests/ClubProfileChoiceFlowTests.swift').read_text()
        self.assertEqual(len(re.findall(r'^    func test', tests, re.M)), 15)
        for name in ['testLateFalseBindingFromCancelledAOnlyRetiresAAfterSameFieldReopen',
                     'testLateCancelAndDismissFromACannotCloseDifferentFieldB',
                     'testPresentationBindingCannotResurrectClosedOwner',
                     'testPresentationGetterUsesCurrentOwnerGateWithoutADeferredClose',
                     'testStaleApplyAfterReopenDoesNotAlterParentOrNewSession',
                     'testExactCurrentBindingCancelDiscardsOnlyStagedDirections',
                     'testHostInvalidationRetiresSelectionAndOldBindingBeforeFreshReopen']:
            self.assertIn('func ' + name, tests)
        self.assertIn('oldBinding.wrappedValue = false', tests)
        self.assertIn('XCTAssertEqual(m.session, second)', tests)


if __name__ == '__main__':
    unittest.main()
