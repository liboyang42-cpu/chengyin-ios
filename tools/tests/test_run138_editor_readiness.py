"""Current readiness cost/inverse proofs, never Apple measurements or a CI bypass."""
from contextlib import contextmanager
from copy import deepcopy
from pathlib import Path
import hashlib
import json
import shutil
import tempfile
import unittest
from unittest.mock import patch

from tools import run138_editor_readiness as layer

ROOT = layer.ROOT
UI = ROOT / 'Tests/AppUITests'
PROFILE = ROOT / 'tools/ui_duration_weights.json'


@contextmanager
def copied_inputs():
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        shutil.copytree(UI, root / 'Tests/AppUITests')
        paths = {'tools/run138_editor_readiness_contract.json', layer.SOURCE_CONTRACT,
                 'tools/ui_duration_weights.json'}
        paths.update(layer.required_followon_files())
        paths.add('tools/ci138_followon_handshake_contract.json')
        paths.update(layer.source_contract()['files'])
        paths.update(layer.source_contract()['protected_sha256'])
        paths.update(layer.contract()['protected_planning_sha256'])
        paths.update(layer.entry_projection().entry_contract()['files'])
        paths.update({'tools/run138_ci_entry_contract.json', 'tools/run138_current_source_projection.py', 'tools/run138_ui52_driver_inverse.py', layer.ui52_layer().CONTRACT_PATH})
        for relative in paths:
            source, target = ROOT / relative, root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        yield root


class Run138EditorReadinessPlanningTests(unittest.TestCase):
    def test_current_source_and_all_736_methods_are_bound_before_projection(self):
        c = layer.validate_current(UI, PROFILE)
        self.assertEqual((c['method_count'], c['class_count_before'], c['class_count_after']), (736, 162, 163))
        old = layer.previous_directory(UI, PROFILE)
        keys, classes = layer.inventory(old)
        self.assertEqual((len(keys), len(classes)), (736, 162))
        self.assertIn('ProjectEditFlowTests.testLocalEditReviewAndCancelledConfirmation', keys)
        self.assertNotIn(layer.REVIEW, keys)
        for name, expected in c['previous_ui_sources'].items():
            self.assertEqual(layer.digest((old / name).read_bytes()), expected)
        self.assertFalse((old / 'ProjectEditReviewReadinessFlowTests.swift').exists())

    def test_copied_helpers_and_original_review_assertions_are_exact(self):
        old = layer.original_source('Tests/AppUITests/ProjectEditFlowTests.swift', (UI / 'ProjectEditFlowTests.swift').read_bytes()).decode()
        new = (UI / 'ProjectEditReviewReadinessFlowTests.swift').read_text()
        start = '    func testLocalEditReviewAndCancelledConfirmation() {'
        before = old.split(start, 1)[1].split('    func testUnconfigured', 1)[0]
        after = new.split(start, 1)[1].rsplit('}\n', 1)[0]
        added = '        XCTAssertTrue(revealFixtureElement(app.staticTexts["Reviewed fixture name"], in: app, requiresHittable: false), app.debugDescription)\n'
        self.assertEqual(after.count(added), 1)
        self.assertEqual(after.replace(added, '', 1), before)
        self.assertIn('continueAfterFailure = false', new)
        self.assertIn('attachFailureScreenshot(self, app: app); app.terminate()', new)

    def test_each_added_query_and_gesture_slot_is_charged_without_old_floor_discounts(self):
        c = layer.contract()
        self.assertEqual(c['method_costs'][layer.REVIEW]['unrounded_added_seconds'], 33)
        for key in [layer.WHITELIST, layer.CHINESE, layer.CURRENT_REVIEW, layer.RELEASE_RECOVERY, layer.COVER_RECOVERY]:
            self.assertEqual(c['method_costs'][key]['unrounded_added_seconds'], 37)
        for key, expected in [(layer.REVIEW, 190), (layer.WHITELIST, 190), (layer.CHINESE, 948), (layer.CURRENT_REVIEW, 946), (layer.RELEASE_RECOVERY, 944), (layer.COVER_RECOVERY, 942)]:
            row = c['method_costs'][key]
            self.assertFalse(row['measured'])
            self.assertEqual((row['maximum_gestures'], row['maximum_viewport_evaluations']), (10, 11))
            self.assertEqual(row['candidate_complete_method_seconds'], expected)
            self.assertEqual(row['added_seconds'], 40)
        self.assertEqual(c['preserved_historical_exceptions'], {layer.CHINESE: 908, layer.CURRENT_REVIEW: 906, layer.RELEASE_RECOVERY: 904, layer.COVER_RECOVERY: 902})
        self.assertEqual(c['new_over900_exceptions'], {layer.CHINESE: 948, layer.CURRENT_REVIEW: 946, 'ProjectStoryImageFlowTests.testChosenStoryImageAppliesOnlyAfterUploadAndRestoresIntoExactPreparedOrder': 905, layer.RELEASE_RECOVERY: 944, layer.COVER_RECOVERY: 942, 'ApprovedTopicFrozenCoverPublicationFlowTests.testApprovedCoverConfirmationAndUnknownPublicationRestoreOriginalManifest': 940, 'ProjectStoryAudioRecoveryFlowTests.testChineseMaximumTextUnknownUploadChecksSameRequestWithoutSecondUpload': 980})

    def test_current_plan_keeps_all_old_costs_and_fits_79_unchanged_deadlines(self):
        report = layer.report()
        self.assertEqual(report['candidate_class_seconds'], {
            'ProjectEditFlowTests': 1330,
            'ProjectEditReviewReadinessFlowTests': 190,
            'ApprovedTopicSelectedCoverChineseFlowTests': 948,
            'ApprovedTopicReviewCurrentChineseFlowTests': 946,
            'MerchantMarketingUITests': 438.399,
            'ProjectStoryImageFlowTests': 905,
            'ApprovedReleaseRecoveryFlowTests': 944,
            'OwnedTopicCoverRecoveryFlowTests': 942,
            'ProjectStoryAudioRecoveryFlowTests': 980,
            'OwnedCouponCodeJourneyUITests': 380,
            'ApprovedTopicFrozenCoverPublicationFlowTests': 940,
            'SquareWorkspaceFlowTests': 249.197,
        })
        self.assertEqual(report['added_total_seconds'], 523.948)
        self.assertEqual((report['method_count'], report['class_count'], report['shard_count']), (736, 163, 79))
        self.assertAlmostEqual(report['maximum_shard_seconds'], 1465.141)
        self.assertEqual(report['startup_reserve_seconds'], 300)
        self.assertEqual(report['deadline_seconds'], 1800)
        self.assertLessEqual(report['maximum_with_startup_reserve_seconds'], 1800)
        self.assertTrue(report['active_ci_runner_modified'])
        self.assertFalse(report['apple_executed'])
        names = [name for group in report['shards'] for name in group['classes']]
        self.assertEqual(len(names), len(set(names)))

    def test_unknown_source_missing_class_and_mutated_helpers_cannot_project(self):
        cases = {
            'Tests/AppUITests/ProjectEditFlowTests.swift': ('for attempt in 0...10', 'for attempt in 0...11'),
            'Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift': ('0..<12', '0..<13'),
            'Tests/AppUITests/ApprovedTopicSelectedCoverChineseFlowTests.swift': ('dynamicTypeSize: "accessibility5"', 'dynamicTypeSize: "large"'),
            'Tests/AppUITests/FailureScreenshot.swift': ('maximumSwipes: Int = 10', 'maximumSwipes: Int = 11'),
            'App/ProjectEditFixtureSupport.swift': ('.dynamicTypeSize(.large)', '.dynamicTypeSize(.small)'),
        }
        for relative, (old, new) in cases.items():
            with self.subTest(path=relative), copied_inputs() as root:
                file = root / relative
                self.assertIn(old, file.read_text())
                file.write_text(file.read_text().replace(old, new, 1))
                with self.assertRaises(ValueError):
                    layer.previous_directory(root / 'Tests/AppUITests', root / 'tools/ui_duration_weights.json', root)
        with copied_inputs() as root:
            (root / 'Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift').unlink()
            with self.assertRaises(ValueError):
                layer.previous_directory(root / 'Tests/AppUITests', root / 'tools/ui_duration_weights.json', root)

    def test_ui56_direction_only_inverse_adds_no_work_or_weakened_assertions(self):
        relative = 'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift'
        live = (ROOT / relative).read_bytes()
        current = layer.followons().source_before_followons(relative, live)
        previous = layer.original_source(relative, live)
        old = b'tap("projectStoryMedia.gap." + anchor, app, top: true)'
        new = b'tap("projectStoryMedia.gap." + anchor, app)'
        self.assertEqual(current.count(new), 1)
        self.assertEqual(current.replace(new, old, 1), previous)
        self.assertIn(b'top: Bool = false', current)
        self.assertIn(b'towardTop: top, maximumSwipes: 10', current)
        self.assertEqual(layer.contract()['direction_only_helper']['added_seconds'], 0)
        c = deepcopy(layer.contract()); c['direction_only_helper']['added_seconds'] = 1
        with patch.object(layer, 'contract', return_value=c), self.assertRaises(ValueError):
            layer.validate_current(UI, PROFILE)

    def test_changed_profile_deadline_and_broader_exception_are_rejected(self):
        with copied_inputs() as root:
            profile = root / 'tools/ui_duration_weights.json'
            profile.write_bytes(profile.read_bytes() + b'\n')
            with self.assertRaises(ValueError):
                layer.validate_current(root / 'Tests/AppUITests', profile, root)
        for mutate in [lambda c: c.update(deadline_seconds=1801),
                       lambda c: c.update(startup_reserve_seconds=299),
                       lambda c: c['new_over900_exceptions'].update(Unrelated=948),
                       lambda c: c['method_costs'][layer.CHINESE].update(added_seconds=0),
                       lambda c: c['method_costs'][layer.CHINESE].update(measured=True),
                       lambda c: c['method_costs'][layer.REVIEW].update(maximum_gestures=11)]:
            c = deepcopy(layer.contract()); mutate(c)
            with patch.object(layer, 'contract', return_value=c), self.assertRaises(ValueError):
                layer.validate_current(UI, PROFILE)

    def test_changed_contract_and_arbitrary_preimage_never_pass(self):
        with copied_inputs() as root:
            contract = root / 'tools/run138_editor_readiness_contract.json'
            contract.write_bytes(contract.read_bytes() + b'\n')
            with self.assertRaises(ValueError):
                layer.validate_current(root / 'Tests/AppUITests', root / 'tools/ui_duration_weights.json', root)
        for relative, row in layer.source_contract()['files'].items():
            raw = (ROOT / relative).read_bytes()
            for changed in [raw + b'\n', b'', raw.replace(b'projectEdit', b'changedEdit', 1) if b'projectEdit' in raw else raw + b' ']:
                with self.subTest(path=relative), self.assertRaises(ValueError):
                    layer.original_source(relative, changed)


if __name__ == '__main__':
    unittest.main()
