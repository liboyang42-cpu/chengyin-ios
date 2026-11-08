"""Source wiring checks only; these do not claim SwiftUI/device execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubMemberAuthorityNavigationChecks(unittest.TestCase):
    def test_selection_and_destination_use_same_issuance_fence(self):
        code = (ROOT / 'App/ClubMembersView.swift').read_text()
        for field in ('target.authorizationGeneration == governance?.access.authorizationGeneration',
                      'target.accessID == governance.map { ObjectIdentifier($0.access) }',
                      'target.namespace == governance?.access.storageNamespace'):
            self.assertIn(field, code)
        selection = code.split('private func select(', 1)[1].split('private func memberRow', 1)[0]
        self.assertIn('guard matchesSource(target)', selection)
        navigation = code.split('.navigationDestination(item: $destination)', 1)[1].split('.onChange(of: reader.clubIdentity)', 1)[0]
        self.assertIn('if matchesSource(target)', navigation)

    def test_issuance_and_namespace_change_retire_old_choices(self):
        code = (ROOT / 'App/ClubMembersView.swift').read_text()
        issuance = code.split('.onChange(of: reportContext)', 1)[1].split('.onAppear', 1)[0]
        self.assertIn('destination = nil; choice = nil; choosing = false', issuance)
        namespace = code.split('.onChange(of: governance?.access.storageNamespace)', 1)[1].split('private func reportButton', 1)[0]
        self.assertIn('destination = nil; choice = nil; choosing = false', namespace)
        self.assertIn('reportRefreshRevision &+= 1', namespace)
