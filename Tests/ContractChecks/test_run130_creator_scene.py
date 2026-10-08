"""Exact test-host-only repair; UIKit execution remains an Apple CI obligation."""
from pathlib import Path
import hashlib
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = Path(__file__).parent / 'fixtures/run130_creator_scene.json'
CONTRACT_SHA = 'b88a3c437443a1886ac85c6b3a2a85b069c9bcbc5677872fe1ded02cce1c88b3'


def contract():
    raw = CONTRACT_PATH.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == CONTRACT_SHA
    return json.loads(raw)


def original_creator_source(name, source):
    spec = contract()
    record = spec['files'][name]
    assert hashlib.sha256(source.encode()).hexdigest() == record['after_sha256']
    if name == 'WorkshopCreatorConsentNormalFlowTests.swift':
        assert source.count(spec['helper']) == 1
        source = source.replace(spec['helper'], '', 1)
    for hunk in record['hunks']:
        assert source.count(hunk['after']) == 1
        source = source.replace(hunk['after'], hunk['before'], 1)
    assert hashlib.sha256(source.encode()).hexdigest() == record['before_sha256']
    return source


class CreatorSceneHostContract(unittest.TestCase):
    def test_three_host_changes_restore_every_original_assertion_action_wait_and_probe(self):
        spec = contract()
        self.assertEqual(set(spec['files']), {'WorkshopCreatorConsentNormalFlowTests.swift', 'WorkshopCreatorPendingNormalFlowTests.swift'})
        self.assertEqual(sum(len(v['hunks']) for v in spec['files'].values()), 3)
        for name in spec['files']:
            source = (ROOT / 'Tests/AppUnitTests' / name).read_text()
            original = original_creator_source(name, source)
            self.assertEqual(original[original.index('    private func waitUntil'):], source[source.index('    private func waitUntil'):])
            self.assertNotIn('XCTSkip', source)
            self.assertEqual(source.count('try WorkshopHostedSceneWindow()'), len(spec['files'][name]['hunks']))

    def test_scene_selection_and_cleanup_require_actual_connected_active_scene(self):
        helper = contract()['helper']
        for part in ['#if DEBUG', '@MainActor final class WorkshopHostedSceneWindow',
                     'activeScenes.count == 1 ? activeScenes.first : nil', 'try XCTUnwrap(',
                     '.filter { $0.activationState == .foregroundActive }',
                     'window = UIWindow(windowScene: selected)', 'window.frame = selected.coordinateSpace.bounds',
                     'private weak var previousKeyWindow: UIWindow?', 'let ownedKeyWindow = window.isKeyWindow',
                     'window.isHidden = true', 'window.rootViewController = nil', 'window.windowScene = nil',
                     'guard ownedKeyWindow, let scene, scene.activationState == .foregroundActive,',
                     'UIApplication.shared.connectedScenes.contains(where: { $0 === scene })',
                     'previousKeyWindow.windowScene === scene, !previousKeyWindow.isHidden,',
                     'previousKeyWindow.windowLevel == .normal, previousKeyWindow.rootViewController != nil,',
                     'scene.windows.contains(where: { $0 === previousKeyWindow })', 'previousKeyWindow.makeKey()']:
            self.assertIn(part, helper)
        for forbidden in ['UIScreen.main', 'UIWindowScene(', 'beginAppearanceTransition', 'endAppearanceTransition',
                          'viewDidAppear(', 'onAppear(', 'XCTSkip', 'Task.sleep', 'print(', 'accountID', 'token']:
            self.assertNotIn(forbidden, helper)

    def test_mutations_of_scene_gate_cleanup_or_original_wait_fail_closed(self):
        name = 'WorkshopCreatorConsentNormalFlowTests.swift'
        source = (ROOT / 'Tests/AppUnitTests' / name).read_text()
        for before, after in [('activeScenes.count == 1', 'activeScenes.count >= 1'),
                              ('window = UIWindow(windowScene: selected)', 'window = UIWindow(frame: .zero)'),
                              ('try XCTUnwrap(', 'try XCTSkipIf('),
                              ('window.frame = selected.coordinateSpace.bounds', 'window.frame = UIScreen.main.bounds'),
                              ('guard ownedKeyWindow, let scene', 'guard let scene'),
                              ('previousKeyWindow.windowScene === scene,', ''),
                              ('!previousKeyWindow.isHidden,', ''),
                              ('previousKeyWindow.rootViewController != nil,', 'true,'),
                              ('addingTimeInterval(5)', 'addingTimeInterval(50)'),
                              ('XCTAssertEqual(c.phase,.reviewing)', 'XCTAssertTrue(true)')]:
            with self.subTest(before=before):
                self.assertIn(before, source)
                with self.assertRaises(AssertionError): original_creator_source(name, source.replace(before, after, 1))

    def test_missing_duplicate_or_extra_helper_calls_fail_closed(self):
        for name in contract()['files']:
            source = (ROOT / 'Tests/AppUnitTests' / name).read_text()
            call = 'let sceneWindow = try WorkshopHostedSceneWindow()'
            for modified in [source.replace(call, '', 1), source.replace(call, call + '\n        ' + call, 1),
                             source + '\n// extra unreviewed source\n']:
                with self.assertRaises(AssertionError): original_creator_source(name, modified)


if __name__ == '__main__': unittest.main()
