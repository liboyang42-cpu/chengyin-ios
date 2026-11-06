"""Offline source checks only, never Swift compilation, iOS runtime or live API evidence."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

class GrowthNormalEntrySourceChecks(unittest.TestCase):
    def test_exact_three_routes_no_anonymous_or_write_admission(self):
        source = read('Core/GrowthNormalReadTransport.swift')
        paths = re.findall(r'case \w+ = "(api/[^"\s]+)"', source)
        self.assertEqual(paths, ['api/growth/center', 'api/play/growth', 'api/play/my-completed'])
        for shape in ['request.httpMethod == "POST"', 'request.httpBody == Data("{}".utf8)',
                      'request.httpBodyStream == nil', 'url.query == nil', 'url.fragment == nil',
                      '"Content-Type") == "application/json"', '"Accept") == "application/json"',
                      '== expectedHeaders', 'absoluteString.utf8.elementsEqual']:
            self.assertIn(shape, source)
    def test_explicit_lease_is_bounded_revocable_and_not_persisted(self):
        source = read('Core/GrowthNormalReadTransport.swift')
        for proof in ['58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4', 'public let revision = UUID()',
                      'ContentDraftContextFence.matches(self.context, context)', 'now < expiresAt',
                      '!isRevoked', 'duration <= 86_400', 'public func revoke()']:
            self.assertIn(proof, source)
        for forbidden in ['UserDefaults', 'Keychain', 'URLSession', 'Bearer ', 'https://']:
            self.assertNotIn(forbidden, source)
    def test_normal_caller_uses_own_child_without_changing_generic_allowlist(self):
        session = read('App/AppSession.swift')
        self.assertIn('let transport = transport.growthNormalReadTransport(approval: composition.growthNormalReadApproval)', session)
        self.assertIn('growthCenterService=GrowthCenterService(configuration:configuration,transport:transport)', session)
        composition = read('App/AppCompositionRoot.swift')
        self.assertIn('growthNormalReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> GrowthNormalReadApproval? = { _ in nil }', composition)
        generic = composition.split('    func send(_ request: URLRequest) async throws -> (Data, Int) {', 1)[1]
        self.assertNotIn('GrowthNormalReadRoute', generic)
        self.assertNotIn('growthNormalReadApproval', generic)
    def test_original_transport_is_reused_without_dispatch_fallback_or_authority_issue(self):
        source = read('App/GrowthNormalReadCompositionTransport.swift')
        self.assertEqual(source.count('underlying.send(request)'), 1)
        for proof in ['self.current() == captured', 'self.selectApproval(context) === approval',
                      'approval.matches(context)', 'GrowthNormalReadRoute.accepts(request',
                      'catch {', 'guard !Task.isCancelled, live() else { throw CancellationError() }']:
            self.assertIn(proof, source)
        for forbidden in ['URLSession', 'GrowthNormalReadApproval(context:', 'generic.send', 'request.setValue', 'UserDefaults']:
            self.assertNotIn(forbidden, source)
    def test_full_session_and_scope_retire_with_permission_or_viewer_revision(self):
        session = read('App/AppSession.swift')
        self.assertIn('$0.matches(context) ? $0.revision : nil', session)
        self.assertIn('approvalRevision:approvalRevision,viewerRevision:compositionViewerRevision', session)
        core = read('Core/GrowthCenterReading.swift')
        self.assertIn('approvalRevision: UUID? = nil, viewerRevision: UInt64 = 0', core)
        self.assertIn('currentSession() == session, scope == captured', core)
    def test_overview_owned_task_cancellation_reaches_reader_on_leave_and_background(self):
        core = read('Core/GrowthNormalReadTransport.swift')
        self.assertIn('withTaskCancellationHandler', core)
        self.assertIn('onCancel: { current.cancel() }', core)
        components = read('App/GrowthCenterComponents.swift')
        self.assertIn('overviewReads.cancel(); state.cancelPending()', components)
        self.assertRegex(components, r'if phase == \.background \{\s+needsRefresh = true; cancel\(\)')
        for path in ['App/GrowthCenterView.swift', 'App/ProfileSelfGrowthSection.swift']:
            source = read(path)
            self.assertIn('model.overviewReads', source)
            self.assertIn('reads.run { await readOverview() }', source)
            self.assertIn('cancel: model.cancelPending', source)
    def test_existing_score_semantics_are_preserved_and_hold_is_separate(self):
        source = read('App/GrowthCenterView.swift')
        self.assertIn('GrowthCenterInteger(value: board.me.score)', source)
        self.assertIn('GrowthCenterInteger(value: overview.center.value?.points)', source)
        self.assertIn('if issue == .notConfigured { GrowthNormalLeaderboardHoldView() }', source)
        self.assertIn('GrowthNormalLeaderboardHoldView()', read('App/GrowthLeaderboardView.swift'))
        self.assertIn('if let issue = overview.progress.issue', source)
        self.assertIn('if let issue = overview.completed.issue', source)
        self.assertIn('completed.isEmpty', source)
        self.assertIn('center.missions.isEmpty', source)
    def test_new_keys_are_bilingual_and_large_type_and_navigation_remain_native(self):
        catalog = json.loads(read('Resources/GrowthNormalEntry.xcstrings'))
        self.assertEqual(len(catalog['strings']), 3)
        for key, value in catalog['strings'].items():
            self.assertTrue(key.startswith('growthNormalEntry.'))
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(v['stringUnit']['state'] == 'translated' and v['stringUnit']['value'] for v in value['localizations'].values()))
        components = read('App/GrowthCenterComponents.swift')
        self.assertIn('dynamicTypeSize.isAccessibilitySize', components)
        self.assertIn('.accessibilityElement(children: .combine)', components)
        source = read('App/ProfileSelfGrowthSection.swift')
        self.assertIn('ProfileSelfGrowthDestination(reader: scopedReader)', source)
        self.assertIn('.frame(minHeight: 44)', source)
        self.assertNotIn('.ignoresSafeArea', source)

if __name__ == '__main__':
    unittest.main()
