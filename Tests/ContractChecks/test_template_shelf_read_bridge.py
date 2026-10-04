"""Supplementary source contracts. Authored Apple tests are not execution evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class TemplateShelfReadBridge(unittest.TestCase):
    def test_default_nil_outer_fence_and_clone_selectors(self):
        s = read('App/AppCompositionRoot.swift')
        self.assertEqual(s.count('templateShelfReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval? = { _ in nil }'), 2)
        self.assertIn('templateShelfReadApproval: templateShelfReadApproval', s)
        for token in ['TemplateShelfReadRoute(request: request, baseURL: api.baseURL)', 'currentApproval.revision == approval.revision', 'readApprovalStillValid?() != false']:
            self.assertIn(token, s)
        self.assertNotIn('TemplateShelfReadApproval', read('App/RegionalLaunchConfiguration.swift'))
    def test_read_capability_does_not_enable_authoring(self):
        s = read('Core/TemplateAuthoringService.swift')
        self.assertIn('public var canRead: Bool { shelfReadTransport?.available == true || canSubmit }', s)
        self.assertIn('public var canSubmit: Bool { canSimulate || transport?.authority == .injectedHTTP }', s)
        self.assertIn('guard canSubmit, let transport else', s.split('func listMine()')[1].split('func listMinePage')[0])
        self.assertIn('!descriptor.mutates', read('Core/TemplateShelfReadApproval.swift'))
        factory = read('App/AppSession.swift').split('func templateShelfCoordinator')[1].split('var templateAuthoringViewIdentity')[0]
        self.assertIn('TemplateAuthoringAdapter(shelfReadTransport: makeTemplateShelfReadTransport())', factory)
        self.assertNotIn('TemplateAuthoringHTTPTransport', factory)
        self.assertIn('if coordinator.canSubmit { await coordinator.loadMine() }', read('App/TemplateAuthoringMineView.swift'))
        self.assertIn('TemplateAuthoringView(coordinator: session.templateAuthoringEditor()', read('App/TemplateAuthoringLaunchView.swift'))
    def test_exact_multipart_read_bounds(self):
        s = read('Core/TemplateShelfReadApproval.swift')
        for token in ['body.count <= 4096', 'keyword.utf8.count <= 512', 'fields["pageSize"] == "10"', 'Set(fields.keys) == ["id"]', 'fields[key] == nil', 'split.lowerBound > keyStart', 'canonical.httpBody == body', 'value.memberID == context.session.accountID', 'request.httpBodyStream == nil']:
            self.assertIn(token, s)
        self.assertNotIn('api/template/info"', s)
        self.assertNotIn('api/common/dict', s)
    def test_complete_lifetime_fences_and_authored_negative_cases(self):
        s = read('App/AppSession.swift')
        for token in ['self.compositionViewerRevision == revision', 'self.currentTemplateShelfReadApproval?.revision == approval.revision', 'self.templateShelfViewIdentity == identity']:
            self.assertIn(token, s)
        tests = read('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift')
        for token in ['"roleABA"', '"sessionABA"', '"reissue"', '"expire"', '"cancel"', '[200, 401, -1]', 'testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations']:
            self.assertIn(token, tests)
        self.assertIn('testReadOnlyRefreshRevocationAndReopenPreserveBothPendingJournals', read('Tests/CoreTests/TemplateShelfReadTests.swift'))
    def test_normal_root_recorder_not_live_api(self):
        s = read('App/IntegratedNativeAcceptanceFixture.swift')
        self.assertIn('templateShelfReadApproval: { self.grants($0)?.shelf }', s)
        self.assertIn('case "api/template/my-list":', s)
        self.assertIn('case "api/template/myinfo":', s)
        self.assertIn('testNormalRootOwnedShelfPaginationAndDetailWithoutMutation', read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift'))
