"""Integration guards for the independently reviewed session-owner seams.

These preserve wiring only; hosted AppUnit lifetime tests remain mandatory.
"""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ComposedSessionInvalidationChecks(unittest.TestCase):
    def test_gate_notifies_social_and_private_home_in_reviewed_order(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        observer = source.split('private var gate = SessionOperationGate()', 1)[1].split('private let vault:', 1)[0]
        social = 'retainedSocialMemberActions?.synchronizeSession()'
        home = 'synchronizePrivateHome()'
        self.assertIn('didSet', observer)
        self.assertEqual(observer.count(social), 1)
        self.assertEqual(observer.count(home), 1)
        self.assertLess(observer.index(social), observer.index(home))

    def test_home_template_and_atomic_context_fences_survive_composition(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        entry = source.split('private func synchronizeAccountMarketingEntry() {', 1)[1]
        before_identity, after_identity = entry.split('if identityChanged {', 1)
        self.assertIn('synchronizePrivateHome()', before_identity)
        self.assertTrue(after_identity.lstrip().startswith('publicTemplateDetails.invalidate()'))
        context = source.split('private var currentRuntimeDependencyContext: RuntimeDependencyContext? {', 1)[1]
        self.assertTrue(context.lstrip().startswith('guard !committingAuthenticatedSession,'))
