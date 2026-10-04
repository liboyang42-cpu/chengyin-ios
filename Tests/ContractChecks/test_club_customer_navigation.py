"""Source guards only. These do not execute Swift or establish UI behavior."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClubCustomerNavigationContracts(unittest.TestCase):
    def test_current_viewer_flags_only_expose_choice(self):
        s=(ROOT/'App/ClubMembersView.swift').read_text()
        self.assertIn('directory.club.id == id, directory.club.canGovern, matchesGovernance(target.identity)',s)
        self.assertIn('} else { destination = target }',s)
        self.assertNotIn('member.isAdmin {\n                                    choice',s)
    def test_crm_reuses_existing_scoped_authority(self):
        s=(ROOT/'App/ClubMembersView.swift').read_text()
        self.assertIn('ClubGovernanceReadView(operation: .customer, scope: .init(clubID: target.clubID, memberID: target.memberID)',s)
        pipeline=(ROOT/'Core/ClubGovernanceService.swift').read_text()
        self.assertIn('post(.access, scope: scope',pipeline)
        self.assertIn('guard permitted else { throw ClubGovernanceFailure.forbidden }',pipeline)
    def test_selection_is_immutable_and_stale_callback_is_ignored(self):
        s=(ROOT/'App/ClubMembersView.swift').read_text()
        for needle in ['let selectionID = UUID()', 'let clubID: Int', 'let memberID: Int', 'let identity: ClubReadIdentity', 'guard choice == target else { return }']:
            self.assertIn(needle,s)
    def test_role_revision_fences_render_not_only_chooser(self):
        s=(ROOT/'App/ClubMembersView.swift').read_text()
        section=s.split('.navigationDestination(item: $destination)')[1]
        self.assertIn('target.viewerRevision == governance?.viewerRevision',section)
        self.assertIn('.onChange(of: governance?.viewerRevision) { _, _ in destination = nil; choice = nil; choosing = false }',section)
        self.assertIn('viewerRevision: compositionViewerRevision, access: clubGovernanceAccess',(ROOT/'App/AppSession.swift').read_text())
    def test_customer_payload_stays_server_redacted_and_member_validated(self):
        s=(ROOT/'Core/ClubGovernanceValidation.swift').read_text()
        self.assertIn('summary["memberId"].int == scope.memberID',s)
        view=(ROOT/'App/ClubGovernanceViews.swift').read_text()
        self.assertIn('snapshot = nil; failure = nil; loading = true',view)
        self.assertIn('access.identity == expected',view)
if __name__ == '__main__': unittest.main()
