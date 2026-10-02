"""Portable source assertions. These do not execute or typecheck Swift."""
import json
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class ClubGovernanceSourceChecks(unittest.TestCase):
    def text(self,name): return (ROOT/name).read_text()
    def test_closed_source_endpoint_inventory(self):
        read=self.text('Core/ClubGovernanceContracts.swift')
        writes=self.text('Core/ClubGovernanceCommands.swift')
        self.assertEqual(len(re.findall(r'case \.\w+: return "api/',read)),34)
        self.assertEqual(len(re.findall(r'case \.\w+: return "api/',writes)),23)
        for path in ['api/club/roles/assign','api/club/governance/owner/transfer','api/club/event-notification/send','api/club-compensation/hours/report','api/verify/groupcode/issue']:
            self.assertIn(path,writes)
    def test_default_writes_and_media_are_off(self):
        service=self.text('Core/ClubGovernanceService.swift')
        self.assertIn('offlineRisks = []',service)
        self.assertIn('guard offlineRisks.contains(command.operation.risk.rawValue)',service)
        self.assertIn('public protocol ClubGovernanceOfflineTransport: HTTPTransport',service)
        self.assertIn('transport = nil; approvedHosts = []',self.text('Core/ClubGovernanceGroupCode.swift'))
    def test_no_fabricated_financial_or_reconciliation_endpoints(self):
        core=self.text('Core/ClubGovernanceCommands.swift')
        for endpoint in ['api/club/settlement/withdraw','api/club-compensation/status','api/club/reconcile']:
            self.assertNotIn(endpoint,core)
    def test_native_entry_is_outside_legacy_admin_gate(self):
        view=self.text('App/ClubDetailView.swift')
        self.assertLess(view.index('ClubGovernanceEntryButton('),view.index('if (club.isOwner || club.viewerIsAdmin)'))
        contracts=self.text('Core/ClubGovernanceContracts.swift')
        self.assertIn('permissions.contains(permission)',contracts)
        self.assertNotIn('viewerIsAdmin',contracts)
        self.assertIn('eventAccesses.contains',contracts)
    def test_app_session_retains_single_coordinator_and_namespace(self):
        session=self.text('App/AppSession.swift')
        self.assertEqual(session.count('lazy var clubGovernanceCoordinator'),1)
        self.assertIn('storageNamespace: storageScope?.service ?? ""',session)
        self.assertIn('clubGovernanceService=ClubGovernanceService(configuration:configuration,transport:transport)',session)
        self.assertIn('governance:clubGovernanceContext',session)
        self.assertGreater(session.count('clubGovernanceCoordinator.cancelReview()'),3)
        self.assertIn('ClubGovernanceHomeEntries(',self.text('App/ClubHomeView.swift'))
    def test_review_has_account_epoch_namespace_and_fresh_targets(self):
        service=self.text('Core/ClubGovernanceService.swift');coordinator=self.text('Core/ClubGovernanceCoordinator.swift')
        for token in ['guard snapshot == review.snapshot','session.identity == review.identity','session.storageNamespace == review.storageNamespace','members == review.supportingMembers']:
            self.assertIn(token,service)
        for token in ['fresh == pending.snapshot','locked.insert(lock)','outcomeLocked','state = .unknown']:
            self.assertIn(token,coordinator)
    def test_scope_wire_keys_and_nullable_activity_are_explicit(self):
        source=self.text('Core/ClubGovernanceContracts.swift')
        self.assertIn('fields = ["id": fields["clubId"] ?? .null]',source)
        self.assertIn('fields["activityId"] = scope.activityID.map(ClubGovernanceValue.integer) ?? .null',source)
        self.assertIn('case .notificationStatus: return ["campaignId"]',source)
    def test_source_phone_and_financial_state_safety(self):
        validation=self.text('Core/ClubGovernanceValidation.swift')
        for token in ['value["phoneIncluded"] == .bool(false)','unverifiedSettledCount','"settled", "pending", "void"','counted == missing','publicProjection: operation == .topicOverview']:
            self.assertIn(token,validation)
    def test_story_uses_club_projection_and_separate_answers(self):
        view=self.text('App/ClubGovernanceViews.swift')
        self.assertIn('ClubGovernanceStoryView',view);self.assertIn('cmsMemberTemplate',view)
        self.assertIn('operation: .nodeAnswer',view);self.assertNotIn('TopicDetailView(',view)
    def test_fixture_does_not_construct_production_session(self):
        root=self.text('App/QuestifyApp.swift')
        self.assertEqual(root.count('contains("--uitesting-club-governance")'),2)
        self.assertIn('ClubGovernanceFixtureHost()',root)
    def test_complete_bilingual_fragment_merged(self):
        fragment=json.loads(self.text('Resources/ClubGovernanceLocalizations.fragment.json'))['strings']
        catalog=json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment),327)
        for key,value in fragment.items():
            self.assertEqual(catalog[key],value)
            for language in ['en','zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'])
    def test_runtime_evidence_explicitly_not_run(self):
        evidence=json.loads(self.text('docs/club-governance-static-evidence.json'))
        self.assertTrue(evidence['swift_test'].startswith('NOT_RUN'))
        self.assertTrue(evidence['xcode_ui'].startswith('NOT_RUN'))
        self.assertEqual(evidence['authored_core_tests'],58)
        self.assertEqual(evidence['authored_ui_tests'],6)
if __name__=='__main__':unittest.main()
