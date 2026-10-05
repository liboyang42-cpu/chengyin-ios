"""Supplementary source checks for authored acceptance; not Apple compilation or UI execution."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TemplateControlsUIAcceptanceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui_sources = [(ROOT / ('Tests/AppUITests/' + name + '.swift')).read_text() for name in ['TemplateEditorControlsFlowTests', 'TemplateHistoricalHintFlowTests']]
        cls.ui = '\n'.join(cls.ui_sources)
        cls.fixture = (ROOT / 'App/TemplateAuthoringFixtureSupport.swift').read_text()
        cls.form = (ROOT / 'App/TemplateAuthoringDetailForms.swift').read_text()
        cls.model = (ROOT / 'App/TemplateAuthoringView.swift').read_text()
        cls.catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']

    def test_exactly_three_single_launch_methods_with_real_normal_entry(self):
        methods = re.findall(r'    func (test\w+)\(', self.ui)
        self.assertEqual(methods, [
            'testRuleRowsPreserveSourceUntilEditAndBoundASCIIThroughLocalRestore',
            'testTimelineEditsDeriveCurrentSummaryAndSurviveExplicitRestore',
            'testHistoricalBytesHintOffRestoreAndSameOwnerLockedReadback',
        ])
        self.assertEqual(self.ui.count('let app = launch('), 3)
        for source in self.ui_sources: self.assertEqual(source.count('app.launch()'), 1)
        for token in ['tap("templateAuthor.begin", in: app)', 'tap("templateAuthor.continue", in: app)',
                      'field.tap(); field.typeText(addition)', 'tapFixtureNativeSwitch',
                      'attachFailureScreenshot(self, app: application)', 'maximumSwipes: 40']:
            self.assertIn(token, self.ui)
        self.assertNotIn('sleep(', self.ui)
        self.assertNotIn('setValue(', self.ui)

    def test_debug_fixture_seeds_only_source_and_probe_observes_coordinator(self):
        self.assertTrue(self.fixture.startswith('#if DEBUG\n'))
        for env, target in [
            ('rules-raw', 'seed.ruleInstructions = raw'),
            ('story-raw', 'seed.storyJson = raw; seed.storyTimelineEdited = nil'),
            ('story-text', 'seed.storyText = text'),
            ('hint1', 'seed.hint1 = text'), ('hint2', 'seed.hint2 = text'),
            ('answer-reveal', 'seed.answerReveal = text'),
        ]:
            self.assertIn('environment["--template-author-' + env + '"]', self.fixture)
            self.assertIn(target, self.fixture)
        for token in ['draft: coordinator.draft', 'requestCount: transport.requests.count',
                      'locked: coordinator.locked', 'state: String(describing: coordinator.state)',
                      'inspectionSequence += 1', 'TemplateAuthoringMemoryStorage()']:
            self.assertIn(token, self.fixture)
        # No fixture lock shortcut or live HTTP transport is added for these journeys.
        self.assertNotIn('func lock', self.fixture)
        self.assertNotIn('URLSession', self.fixture)
        self.assertNotIn('savePending(', self.fixture)
        self.assertIn('app.launchArguments = ["--ui-template-authoring", "--template-author-local-probe"', self.ui)

    def test_story_ids_resolve_rows_without_changing_stable_row_identity(self):
        for token in ['ForEach(Array(editor.visibleBeats.enumerated()), id: \\.element.id)',
                      'accessibilityPrefix: "templateStory.beat.\\(index)"',
                      '.accessibilityIdentifier("templateStory.open")',
                      '.accessibilityIdentifier("templateStory.summary")',
                      '.accessibilityIdentifier("templateStory.beat.\\(index).imageCount")']:
            self.assertIn(token, self.form)
        for suffix in ['tag', 'text', 'images']:
            self.assertIn('accessibilityPrefix.map { $0 + ".' + suffix + '" }', self.form)
        self.assertIn('accessibilityIdentifier(accessibilityID ?? "templateAuthor.field." + key)', self.model)
        self.assertIn('accessibilityID: String? = nil', self.model)
        self.assertIn('var accessibilityPrefix: String? = nil', self.form)

    def test_raw_historical_corpus_has_real_lexical_distinctions_and_rejects_supported_schema(self):
        raw = re.search(r'private let historicalStory = " \\r\\n" \+ #"(.*?)"# \+ "\\t "', self.ui)
        self.assertIsNotNone(raw)
        payload = json.loads(raw[1])
        self.assertEqual(payload[0]['future']['integer'], 9007199254740993)
        self.assertIn('"decimal":1.2300', raw[1])
        self.assertNotEqual(set(payload[0]), {'text', 'tag', 'imgs'})
        self.assertIn('(1...13).map', self.ui)
        self.assertIn('joined(separator: "\\r\\n")', self.ui)
        self.assertIn('actual.map { Array($0.utf8) }', self.ui)
        self.assertIn('bytes(restored.draft.storyJson, historicalStory)', self.ui)
        self.assertIn('bytes(restored.draft.ruleInstructions, originalRules)', self.ui)

    def test_local_save_restore_clear_and_locked_readback_are_observed_not_seeded(self):
        for token in ['tap("templateAuthor.saveLocal", in: app)', 'tap("templateAuthor.fixture.reopen", in: app)',
                      'tap("templateAuthor.restore", in: app)', 'setHints(false, in: app)',
                      'assertHints(["", "", ""], draft: cleared.draft)',
                      'assertHints(["", "", ""], draft: restored.draft)',
                      'XCTAssertEqual(restored.draft.legacyHintsEnabled, false)',
                      'tap("templateAuthor.cancelReview", in: app)',
                      'tap("templateAuthor.confirmSimulation", in: app)',
                      'inspect(app, requests: 1, locked: true)',
                      'hintsEnabled(true, in: app, editable: false, towardTop: true)',
                      'tap("templateAuthor.fixture.signOut", in: app)',
                      'XCTAssertEqual(snapshot.requestCount, requests',
                      'value != %@ AND value BEGINSWITH %@']:
            self.assertIn(token, self.ui)
        # The final base must contain the accepted visibility/edit-permission separation.
        hints = (ROOT / 'App/TemplateLegacyHintFields.swift').read_text()
        self.assertIn('canReadLegacyHints && coordinator.session == session', hints)
        self.assertIn('guard self.canEdit, self.legacyHintLeaseIsCurrent', hints)
        self.assertIn('var canReadLegacyHints: Bool', self.model)
        self.assertIn('var canReadStoryDraft: Bool', self.model)
        self.assertIn('if let issue = editor.visibleIssueKey', self.form)
        self.assertIn('transport = .init(scenario:', self.fixture)
        self.assertIn('XCTAssertFalse(app.buttons["templateAuthor.confirmRequest"].exists)', self.ui)

    def test_scope_change_checks_observable_child_content_clearing(self):
        for token in ['tap("templateAuthor.fixture.switch", in: app)',
                      'Observable scope-change behavior only; retained callback leases have separate unit tests.',
                      'XCTAssertNil(switched.draft.storyJson); XCTAssertNil(switched.draft.storyText)',
                      'XCTAssertFalse(app.staticTexts["Third scene"].exists)']:
            self.assertIn(token, self.ui)
        self.assertIn('predicate: NSPredicate(format: "exists == false")', self.ui)

    def test_catalog_expectations_and_story_boundary_scope_match_source(self):
        for key in ['templateRules.asciiLimit', 'templateStory.unsupported', 'templateAuthor.localSaved',
                    'templateAuthor.simulated', 'templateAuthor.method.1', 'templateAuthor.method.2',
                    'templateAuthor.storyTimeline']:
            value = self.catalog[key]['localizations']['en']['stringUnit']['value']
            self.assertIn('"' + value + '"', self.ui, key)
        for token in ['let sixty = String(repeating: "a", count: 60)', 'last.typeText("Z")',
                      'No non-ASCII length parity claim', 'XCTAssertEqual(beats[0].imgs.count, 6)',
                      'XCTAssertNil(untouched.draft.storyTimelineEdited',
                      'bytes(changed.draft.storyText, legacySummary', 'bytes(restored.draft.storyJson, json)']:
            self.assertIn(token, self.ui)
        self.assertIn('images.split(separator: "\\n").map(String.init)', self.ui)
        self.assertNotIn('Unicode60', self.ui)
        self.assertNotIn('UIPasteboard', self.ui)


if __name__ == '__main__':
    unittest.main()
