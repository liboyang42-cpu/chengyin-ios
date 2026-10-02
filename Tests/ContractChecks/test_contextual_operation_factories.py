"""Offline composition checks. Swift tests and Apple runtime are separate gates."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ContextualOperationFactoryContracts(unittest.TestCase):
    def text(self, path): return (ROOT/path).read_text()
    def test_normal_hosts_consume_independent_default_off_inputs(self):
        app = self.text('App/AppSession.swift')
        for s in ['ClubOpsTimeConfiguredService(', 'approval: runtimeDependencies.clubOpsTimeApproval',
                  'ContextualReviewConfiguredWriter(', 'approval: runtimeDependencies.contextualReviewApproval',
                  'journal: contextualOperationJournal', 'self?.currentRuntimeDependencyContext']:
            self.assertIn(s, app)
        dependencies = self.text('App/NativeRuntimeDependencies.swift')
        self.assertIn('clubOpsTimeApproval: ClubOpsTimeApproval? = nil', dependencies)
        self.assertIn('contextualReviewApproval: ContextualReviewApproval? = nil', dependencies)
    def test_known_source_routes_and_no_owner_domain_alias(self):
        code = self.text('Core/ContextualOperationProduction.swift')
        for route in ['api/activity/info','api/topic/info-to-user','api/club/lead/team-progress','api/club/lead/edit-ops','api/comment/add']:
            self.assertIn('"'+route+'"', code)
        self.assertIn('targets.contains(target)', code)
        self.assertIn('receipt["ownerType"].int == target.ownerType', code)
        self.assertNotIn('api/comment/eligibility', code)
        self.assertNotIn('api/club/lead/notify', code)
    def test_source_leader_and_pending_sale_lock_are_mandatory(self):
        code = self.text('Core/ContextualOperationProduction.swift')
        for s in ['data["timeLocationLocked"].bool == false', 'leader["exists"].bool == true',
                  'leader["isLeader"].bool == true', 'leader["leaderMemberId"].int == captured.session.accountID',
                  'data["clubId"].int == target.clubID']:
            self.assertIn(s, code)
    def test_single_use_durable_dispatch_boundary(self):
        code = self.text('Core/ContextualOperationProduction.swift')
        for s in ['private var consumed = false', 'self.command == command', 'try pending()',
                  'authorization.consume(.clubTime(request)', 'authorization.consume(.review(target, draft)',
                  'public let requiresDurableJournal = true']:
            self.assertIn(s, code)
        for path in ['Core/ContextualReviews.swift', 'Core/ClubContextualOperations.swift']:
            value = self.text(path)
            self.assertIn('try journal?.write(record)', value)
            self.assertIn('journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record', value)
            self.assertIn('public private(set) var runtimeContext: RuntimeDependencyContext?', value)
    def test_normal_contextual_callers_remain_mounted(self):
        self.assertIn('opsTimeFactory: { [weak self] in self?.clubOpsTimeHost?.coordinator(activityID: $0)', self.text('App/AppSession.swift'))
        self.assertIn('session.contextualReviews?.coordinator(.topic(id))', self.text('App/PlatformConsumerSessionOwner.swift'))
        self.assertIn('contextualReviews?.coordinator(.activity(id))', self.text('App/ActivityDetailView.swift'))
