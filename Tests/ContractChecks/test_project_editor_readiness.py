"""Source/geometry regression contracts only; no SwiftUI or XCUITest execution.

The exact inverse proves preservation, but is deliberately not plugged into the
historical planning layers. Added readiness work still needs reviewed costing.
"""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_SHA256 = 'e6a48f0e2ca5f9e4c64524097c3ff61279d68c15e70d287bc3ea4e9752f8a438'
_contract_bytes = (ROOT / 'Tests/ContractChecks/fixtures/project_editor_readiness.json').read_bytes()
if hashlib.sha256(_contract_bytes).hexdigest() != CONTRACT_SHA256:
    raise ValueError('Unreviewed editor-readiness preservation contract')
CONTRACT = json.loads(_contract_bytes)


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def original_source(path, source):
    from tools.ci138_followon_projection import source_before_followons
    source = source_before_followons(path, source.encode()).decode()
    row = CONTRACT['files'][path]
    if digest(source) != row['after_sha256']:
        raise ValueError('Unknown current editor-readiness source')
    if row['before_sha256'] is None:
        return None
    for hunk in reversed(row['hunks']):
        if source.count(hunk['after']) != 1:
            raise ValueError('Missing or ambiguous exact readiness hunk')
        source = source.replace(hunk['after'], hunk['before'], 1)
    if digest(source) != row['before_sha256']:
        raise ValueError('Original editor source not restored exactly')
    return source


class ProjectEditorReadinessContracts(unittest.TestCase):
    def test_exact_inverse_preserves_all_original_assertions_and_helpers(self):
        self.assertEqual(set(CONTRACT['files']), {
            'Tests/AppUITests/ProjectEditFlowTests.swift',
            'Tests/AppUITests/ApprovedTopicSelectedCoverChineseFlowTests.swift',
            'App/ProjectEditFixtureSupport.swift',
            'Tests/AppUITests/ApprovedTopicReviewCurrentChineseFlowTests.swift',
            'Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift',
            'Questify.xcodeproj/project.pbxproj',
            'Tests/AppUITests/ApprovedReleaseRecoveryFlowTests.swift',
            'Tests/AppUITests/OwnedTopicCoverRecoveryFlowTests.swift',
            'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift',
        })
        for path, row in CONTRACT['files'].items():
            with self.subTest(path=path):
                source = (ROOT / path).read_text()
                before = original_source(path, source)
                self.assertEqual(digest(before) if before is not None else None, row['before_sha256'])

    def test_inverse_rejects_unrelated_changed_missing_or_repeated_hunks(self):
        for path, row in CONTRACT['files'].items():
            source = (ROOT / path).read_text()
            for mutant in [source + '\n', source[:-1] + ('X' if source[-1:] != 'X' else 'Y')]:
                with self.subTest(path=path), self.assertRaises(ValueError):
                    original_source(path, mutant)
            for hunk in row['hunks']:
                for mutant in [source.replace(hunk['after'], hunk['before'], 1),
                               source.replace(hunk['after'], hunk['after'] * 2, 1)]:
                    with self.subTest(path=path), self.assertRaises(ValueError):
                        original_source(path, mutant)

    def test_shared_helpers_environment_workflow_and_budget_history_are_unchanged(self):
        for path, expected in CONTRACT['protected_sha256'].items():
            with self.subTest(path=path):
                from tools.run138_current_source_projection import historical_entry_bytes
                self.assertEqual(hashlib.sha256(historical_entry_bytes(ROOT, path)).hexdigest(), expected)

    def test_root_name_reveal_uses_form_bounds_and_actual_fixed_actions(self):
        source = (ROOT / 'Tests/AppUITests/ProjectEditFlowTests.swift').read_text()
        helper = source.split('func revealProjectEditorNameInForm(', 1)[1].split('/// Authored for Xcode', 1)[0]
        for token in ['forms.count == 1', 'app.navigationBars.count == 1',
                      'formFrame.intersection(app.frame)', 'navigation.frame.maxY + 8',
                      'min(save.frame.minY, review.frame.minY) - 24',
                      'keyboard.frame.minY - 4', 'bottom - top > 80',
                      'viewport.contains(frame), name.isHittable', 'for attempt in 0...10',
                      'guard attempt < 10', 'viewport.width * 0.06',
                      'towardTop ? 0.3 : 0.75', 'towardTop ? 0.75 : 0.3']:
            self.assertIn(token, helper)
        for forbidden in ['waitForExistence', 'sleep(', 'while ', 'app.swipeUp()',
                          'revealFixtureElement(', '.tap()', 'label.contains']:
            self.assertNotIn(forbidden, helper)
        self.assertEqual(source.count('XCTAssertTrue(revealProjectEditorNameInForm(in: app)'), 1)
        review = (ROOT / 'Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift').read_text()
        self.assertIn('XCTAssertTrue(revealFixtureElement(app.staticTexts["Reviewed fixture name"], in: app, requiresHittable: false), app.debugDescription)\n        XCTAssertTrue(app.staticTexts["Reviewed fixture name"].waitForExistence(timeout: 3))', review)

    def test_chinese_launch_and_fixture_chrome_leave_production_maximum_type(self):
        source = (ROOT / 'Tests/AppUITests/ApprovedTopicSelectedCoverChineseFlowTests.swift').read_text()
        self.assertIn('"--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"', source)
        self.assertIn('app.launch()\n        XCTAssertTrue(revealProjectEditorNameInForm(in: app), app.debugDescription)\n        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))\n        if chinese { assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5") }', source)
        fixture = (ROOT / 'App/ProjectEditFixtureSupport.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG\n'))
        controls = fixture.split('            HStack {', 1)[1].split('            if ProcessInfo', 1)[0]
        self.assertIn('.dynamicTypeSize(.large)', controls)
        production = fixture.split('            NavigationStack { ProjectEditView(', 1)[1]
        self.assertNotIn('.dynamicTypeSize(', production)

    def test_gesture_endpoints_stay_inside_short_form_viewport(self):
        # Synthetic geometry in points, not measurements or SwiftUI execution.
        # Includes an asymmetric maximum-text inset where Save is taller than Review.
        scenarios = [
            dict(form_top=100, form_bottom=900, nav_bottom=160, save_top=815, review_top=815),
            dict(form_top=280, form_bottom=900, nav_bottom=395, save_top=710, review_top=755),
            dict(form_top=100, form_bottom=900, nav_bottom=160, save_top=710, review_top=755, keyboard_top=650),
        ]
        for values in scenarios:
            top = max(values['form_top'], values['nav_bottom'] + 8)
            bottom = min(values['form_bottom'], min(values['save_top'], values['review_top']) - 24)
            if 'keyboard_top' in values:
                bottom = min(bottom, values['keyboard_top'] - 4)
            self.assertGreater(bottom - top, 80)
            for toward_top in [False, True]:
                start = top + (bottom - top) * (0.3 if toward_top else 0.75)
                end = top + (bottom - top) * (0.75 if toward_top else 0.3)
                self.assertTrue(top < start < bottom)
                self.assertTrue(top < end < bottom)
                self.assertLess(max(start, end), min(values['save_top'], values['review_top']))


if __name__ == '__main__':
    unittest.main()
