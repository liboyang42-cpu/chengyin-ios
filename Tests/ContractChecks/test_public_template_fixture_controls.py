"""Keep fixed harness controls separate from real scrolling template content."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublicTemplateFixtureControlChecks(unittest.TestCase):
    def test_only_debug_probes_have_bounded_dynamic_type(self):
        source = (ROOT / 'App/PublicPlayTemplateFixtureHost.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertEqual(source.count('.dynamicTypeSize(.large)'), 1)
        before, browser = source.split('            NavigationStack {')
        self.assertIn('.font(.caption).dynamicTypeSize(.large)', before)
        self.assertNotIn('.dynamicTypeSize', browser)
        for token in ['String(images.readCount)', 'String(reader.detailReads)',
                      'images.onRead = { reader.revision += 1 }']:
            self.assertIn(token, before)

    def test_fixed_controls_require_one_visible_enabled_native_action(self):
        source = (ROOT / 'Tests/AppUITests/PublicPlayTemplatePresentationFlowTests.swift').read_text()
        fixed = source.split('private func tap(_ id: String) {')[1].split('let element = app.buttons.matching')[0]
        self.assertIn('id == "media.gallery.close" || id == "publicPlay.fixture.replaceOnImage"', fixed)
        for token in ['waitForExistence(timeout: 5)', 'leaves.count, 1',
                      'button.isEnabled && button.isHittable', 'app.frame.contains(button.frame)', 'button.tap()']:
            self.assertIn(token, fixed)
        self.assertNotIn('revealFixtureElement', fixed)
        self.assertIn('revealFixtureElement(element, in: app)', source)
        self.assertIn('assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5")', source)
        for token in ['publisherValue', 'useCount', 'discovery.template.storyText',
                      "label == '2 / 2'", 'XCTAssertFalse(app.alerts.firstMatch.exists)',
                      'XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)']:
            self.assertIn(token, source)


if __name__ == '__main__': unittest.main()
