"""Offline source-contract and mount checks. No Swift compiler or live API claims."""
from pathlib import Path
import json, unittest
R = Path(__file__).resolve().parents[2]
def read(p): return (R / p).read_text()
class SquareReportContractChecks(unittest.TestCase):
    def test_exact_policy_submit_and_case_routes_are_separate_from_legacy(self):
        source = read('Core/SquareReportService.swift')
        for route in ['api/v1/community/capabilities', 'api/v1/community/reports', 'api/community-trust/reports/']:
            self.assertIn(route, source)
        for key in ['targetType', 'targetId', 'reasonCode', 'policyVersion', 'description', 'evidenceAssetIds', 'requestId']:
            self.assertIn('"' + key + '"', source)
        for forbidden in ['api/creativesquare/report', 'api/comment/report', 'api/club/', 'evidenceAssetIds": .array([.integer']:
            self.assertNotIn(forbidden, source)
    def test_versioned_subjects_need_read_generation_parent_and_version(self):
        source = read('Core/SquareReportContracts.swift')
        for token in ['post.generation == .communityV1', 'comment.communityPostID == post.id', 'postVersion', 'subject.post?.version == target.postVersion', 'description.utf16.count <= 2000']:
            self.assertIn(token, source)
        self.assertNotIn('init(_ source: SocialActionTarget)', source)
    def test_confirmation_revalidates_policy_context_and_persists_before_dispatch(self):
        source = read('Core/SquareReportCoordinator.swift')
        self.assertIn('fresh.sameContext(as: review.snapshot)', source)
        self.assertLess(source.index('journal.claim('), source.index('service.submit('))
        self.assertIn('!consumed.contains(review.id)', source)
        self.assertIn('value.id == receipt.id', source)
        self.assertNotIn('journal.remove', source)
    def test_normal_entry_keeps_default_off_and_never_uses_bare_v1_id_for_legacy_reads(self):
        host = read('App/AppSession.swift')
        self.assertIn('func squareReportContext()', host)
        self.assertIn('snapshot(target: target, generation: .communityV1)', host)
        self.assertNotIn('SquareReportService(offlineConfiguration:', host)
        self.assertNotIn('grant: .reviewedInjection', host)
        self.assertIn(r'.environment(\.squareReportContext, session.squareReportContext())', read('App/SessionSquareBrowserView.swift'))
        self.assertIn('contentGeneration: .communityV1', read('App/SquareBrowserView.swift'))
        detail = read('App/SquareDetailView.swift')
        self.assertIn('SquareReportTarget(post: post, comment: comment)', detail)
        self.assertIn('squareDetail(route: .init(id: id, generation: contentGeneration))', detail)
    def test_related_actions_and_workspace_keep_namespace(self):
        action = read('Core/SocialActionContracts.swift')
        for token in ['requiredGeneration', 'snapshot.post?.generation == requiredGeneration', 'communityComment', 'communityCommentLike', 'clientRequestId', 'parentId']:
            self.assertIn(token, action)
        workspace = read('Core/SquareWorkspaceContracts.swift')
        self.assertIn('guard sourceLane == lane', workspace)
        self.assertIn('lane: value.lane', read('Core/SquareWorkspaceCoordinator.swift'))
        self.assertIn('comment.generation == .communityV1', read('Core/SquareGovernanceService.swift'))
    def test_reason_keyboard_cancel_localizations_and_synthetic_capture_hooks(self):
        view = read('App/SquareReportView.swift')
        for token in ['squareReport.reasonCancel', 'squareReport.keyboardDone', 'squareReport.reviewBack', 'selectedReason == nil || !validDescription', '.interactiveDismissDisabled(hasDraft || busy)', 'reasonCode = nil; snapshot = nil']:
            self.assertIn(token, view)
        fragment = json.loads(read('Resources/SquareReportLocalizations.fragment.json'))
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        for key, value in fragment.items():
            self.assertEqual(catalog[key], value)
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        self.assertTrue(read('App/SquareReportFixtureHost.swift').startswith('#if DEBUG'))
        self.assertIn('attachFixtureScreenshot', read('Tests/AppUITests/SquareReportFlowTests.swift'))
