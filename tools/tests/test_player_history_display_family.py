"""Exact wrapper-family coverage; no generic exemption for unobserved display flags."""
from pathlib import Path
import unittest
from tools.tests.test_fixture_environment_contract import reviewed_branch_history_display_family

ROOT = Path(__file__).resolve().parents[2]
MAIN = 'PlayBranchHistoryFlowTests'
LIFETIME = 'PlayBranchHistoryLifetimeFlowTests'


class PlayerHistoryDisplayFamilyTests(unittest.TestCase):
    def sources(self):
        return {name: (ROOT / 'Tests/AppUITests' / (name + '.swift')).read_text()
                for name in [MAIN, LIFETIME]}

    def rejects(self, name, before, after):
        sources = self.sources()
        self.assertIn(before, sources[name])
        sources[name] = sources[name].replace(before, after, 1)
        with self.assertRaises(AssertionError):
            reviewed_branch_history_display_family(sources)

    def test_exact_five_original_methods_and_helpers_share_original_observation(self):
        checked = reviewed_branch_history_display_family(self.sources())
        self.assertEqual(checked.count('func test'), 5)
        self.assertEqual(checked.count('assertFixtureEnvironment(in: app'), 1)

    def test_missing_or_extra_wrapper_fails_closed(self):
        for mutation in ['missing', 'extra']:
            sources = self.sources()
            if mutation == 'missing': sources.pop(LIFETIME)
            else: sources['AnotherClass'] = sources[LIFETIME]
            with self.assertRaises(AssertionError): reviewed_branch_history_display_family(sources)

    def test_added_omitted_duplicated_and_renamed_methods_are_rejected(self):
        token = 'func testLinearSummaryHasNoHistoryEntryBeforeOrAfterRefresh()'
        for replacement in ['func hiddenJourney()', 'func testRenamedJourney()',
                            'func testNewJourney() {}\n    ' + token,
                            token + ' {}\n    ' + token]:
            with self.subTest(replacement=replacement): self.rejects(LIFETIME, token, replacement)

    def test_literal_variable_or_indirect_chinese_calls_and_helper_changes_are_rejected(self):
        for replacement in ['let app = launch(chinese: true)',
                            'let option = true; let app = launch(chinese: option)',
                            'let app = launch(chinese: [true].first!)',
                            'let app = launch(chinese: { true }())']:
            with self.subTest(replacement=replacement): self.rejects(LIFETIME, 'let app = launch()', replacement)
        self.rejects(LIFETIME, 'chinese: Bool = false', 'chinese: Bool = true')
        self.rejects(LIFETIME, 'app.launch(); return app', 'app.launch(); app.launch(); return app')

    def test_removed_or_altered_actual_environment_assertion_is_rejected(self):
        original = 'assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")'
        self.rejects(MAIN, original, 'XCTAssertTrue(true)')
        self.rejects(MAIN, original, 'assertFixtureEnvironment(in: app, dynamicTypeSize: "large")')


if __name__ == '__main__': unittest.main()
