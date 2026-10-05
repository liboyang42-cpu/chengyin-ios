"""P057 full-method planning, exact historical evidence and lossless class split.

These source/tool assertions are not Swift or Apple runtime execution.
"""
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest
from tools.tests.run108_runtime_budget_history import historical_profile, historical_costs, HISTORICAL_SHARD_COUNT
from tools.tests.club_story_budget_history import before_club_story, METHOD, CLASSES

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('club_story_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)
EXPECTED = {'ClubStoryFlowTests.testGroupedStopsHaveHoursAddressAndChapterMetadata': 120, 'ClubStoryFlowTests.testChapterSwitchAndExpansionResetKeepEachPlayInItsOwnChapter': 240, 'ClubStoryNavigationFlowTests.testTemplateDetailUsesPersonalIDAndBackSupportsRepeatedSelection': 180, 'ClubStoryNavigationFlowTests.testSourceRefreshDropsOpenTemplateAndOldCards': 180, 'ClubStoryNavigationFlowTests.testDelayedDetailCannotReappearAfterSourceRefresh': 210, 'ClubStoryNavigationFlowTests.testAccountAndReaderReplacementDismissOldDestination': 330, 'ClubStoryFlowTests.testUnavailableAndInvalidSourcesDoNotOfferTemplateNavigation': 210, 'ClubStoryFlowTests.testDuplicateChapterIDsKeepDisplaySelectableButAllRoutesDisabled': 150, 'ClubStoryFlowTests.testChineseRoutePlayAndEmptyChapterAreLocalized': 150, 'ClubGovernanceFlowTests.testClubStoryUsesOwnRouteAndProtectedAnswer': 210}
METHOD_HASHES = {'ClubStoryFlowTests.testGroupedStopsHaveHoursAddressAndChapterMetadata': '3f25d6eef1564be2b3da1cffc23bf6da0fb67e1e13854568f87fe72d8db5f435', 'ClubStoryFlowTests.testChapterSwitchAndExpansionResetKeepEachPlayInItsOwnChapter': '91ee9b3f46e2a3974b1c629917e02689199234e2655ee34884a1ea7ac5a6d772', 'ClubStoryNavigationFlowTests.testTemplateDetailUsesPersonalIDAndBackSupportsRepeatedSelection': '695e12a3450d9e646dc4d50026d7f6819899d299f7ffba85913d0ebbecfca289', 'ClubStoryNavigationFlowTests.testSourceRefreshDropsOpenTemplateAndOldCards': '4fff667be1f493dd7ab47b2fc1444b70fff461821b22ec75d3527f4a1117f7fd', 'ClubStoryNavigationFlowTests.testDelayedDetailCannotReappearAfterSourceRefresh': '64cc86c36edad84c6f649a4d8e501049e396ad702d0c57fe85451fd86a71924e', 'ClubStoryNavigationFlowTests.testAccountAndReaderReplacementDismissOldDestination': '9a77bd5b0acf81d7fdb2523831ba77bf10187c6a5a958c2d727ebb995b5beabf', 'ClubStoryFlowTests.testUnavailableAndInvalidSourcesDoNotOfferTemplateNavigation': '4606110f18aa9aed92017d1d047cd3f065c539bd57591485951b412e9379ee8a', 'ClubStoryFlowTests.testDuplicateChapterIDsKeepDisplaySelectableButAllRoutesDisabled': 'e564a697f090563fc2c95d3e19ab478f86e9452e1e897fa0f8e04f33b5b58310', 'ClubStoryFlowTests.testChineseRoutePlayAndEmptyChapterAreLocalized': '97e3ad2a6eeb07255da84fc365ee29ac806d2b3b2d00de0c2b855f143fa2f2fc'}
PRIOR_PROFILE_SHA256 = '5a727e5988c99ad9d5320cc7b277742ec2c48e156b4e8dd45cbd9ffa7c127b6e'


class ClubStoryBudgetTests(unittest.TestCase):
    def profile(self):
        return historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))

    def test_ten_full_method_allowances_are_explicit_unmeasured_with_source_counts(self):
        profile = self.profile()
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] in {'THIRTEENTH-P057-integration-only', 'THIRTEENTH-P057-expanded-existing'}]
        self.assertEqual(len(records), 10)
        self.assertEqual({record['method']: record['seconds'] for record in records}, EXPECTED)
        for record in records:
            method = record['method']
            self.assertIs(record['measured'], False)
            self.assertNotIn(method, profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][method], record['seconds'])
            counts = record['counts']
            margin = 30 if method == METHOD else 15
            formula = (30 * counts['launches'] + 8 * counts['termination_calls_including_teardown']
                       + 24 * counts['reveal_calls_max10_gestures_each']
                       + 4 * counts['taps_including_helper_taps_and_back']
                       + 5 * counts['explicit_5_second_waits']
                       + 2 * counts['other_assertion_queries'] + margin)
            self.assertEqual(formula, record['formula_seconds'])
            self.assertEqual(record['explicit_timeout_seconds'], 5 * counts['explicit_5_second_waits'])
            self.assertEqual(record['seconds'], ((formula + 29) // 30) * 30)
            self.assertIn('unmeasured', record['basis'])
            case, name = method.split('.')
            self.assertIn('func ' + name + '()', (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text())
        replan = profile['planning_budget']['club_story_replan']
        self.assertEqual(set(replan['new_methods']), set(EXPECTED) - {METHOD})
        self.assertEqual((replan['new_method_count'], replan['new_estimated_method_seconds']), (9, 1770))
        self.assertEqual(replan['expanded_methods'], [METHOD])
        self.assertEqual(replan['net_declared_method_seconds_added'], 1952.268)

    def test_superseded_observation_and_all_other_profile_values_are_preserved_exactly(self):
        profile = self.profile()
        records = [record for record in profile['superseded_method_observations'] if record['method'] == METHOD]
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['seconds'], 27.732)
        self.assertIs(records[0]['measured'], True)
        self.assertEqual(records[0]['previous_test_file_blob'], '8cb1f73f86dec72f67e19ef1655ddfd9e549a305')
        self.assertIn('superseded provenance', records[0]['reason'])
        prior = before_club_story(profile)
        serialized = json.dumps(prior, sort_keys=True, separators=(',', ':')).encode()
        self.assertEqual(hashlib.sha256(serialized).hexdigest(), PRIOR_PROFILE_SHA256)
        for key in prior['planning_budget']:
            self.assertEqual(prior['planning_budget'][key], profile['planning_budget'][key])

    def test_mechanical_split_preserves_all_nine_exact_method_bodies_and_helpers(self):
        discovered = {}; helpers = []
        for case in sorted(CLASSES):
            source = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
            matches = list(re.finditer(r'^    func (test\w+)\(', source, re.M))
            self.assertEqual(len(matches), 5 if case == 'ClubStoryFlowTests' else 4)
            helpers.append(source[source.index('    private var app:'):matches[0].start()])
            for match in matches:
                # Test bodies retain their original four-space closing brace.
                end = source.index('\n    }', match.start()) + len('\n    }')
                method = case + '.' + match.group(1)
                self.assertNotIn(method, discovered)
                discovered[method] = hashlib.sha256(source[match.start():end].encode()).hexdigest()
        self.assertEqual(discovered, METHOD_HASHES)
        self.assertEqual(helpers[0], helpers[1])
        self.assertEqual(hashlib.sha256(helpers[0].encode()).hexdigest(),
                         '709c59e275d758008250d95015e9d81129bee64383e9332c4cc48e94112babf4')

    def test_complete_current_inventory_fits_minimum_twenty_three_shards_without_relaxed_limits(self):
        profile = self.profile(); budget = profile['planning_budget']; current = budget['club_story_replan']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        self.assertEqual(profile['unobserved_method_seconds'], 60)
        self.assertEqual((current['previous_shard_count'], current['shard_count']), (22, 23))
        self.assertEqual(HISTORICAL_SHARD_COUNT, 23)
        self.assertEqual(current['previous_shard_count'], budget['template_metadata_selectors_replan']['shard_count'])
        self.assertEqual((current['baseline_method_count'], current['baseline_total_method_seconds']), (645, 31304.282))
        counts = SHARD.discover(ROOT / 'Tests/AppUITests')
        floats = historical_costs(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        precise = {}; inventory = set()
        for path in sorted((ROOT / 'Tests/AppUITests').glob('*.swift')):
            source = path.read_text(); names = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not names:
                continue
            cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
            self.assertEqual(len(cases), 1); case = cases[0]
            self.assertNotIn(case, precise)
            methods = [case + '.' + name for name in names]
            self.assertEqual(len(methods), len(set(methods)))
            inventory.update(methods)
            precise[case] = sum(Decimal(str(profile['method_seconds'].get(method,
                profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds'])))) for method in methods)
        self.assertEqual((sum(counts.values()), len(counts), len(inventory)), (654, 98, 654))
        self.assertEqual((current['method_count'], current['class_count']), (654, 98))
        self.assertEqual(sum(precise.values()), Decimal('33256.550'))
        self.assertEqual(Decimal(str(current['total_method_seconds'])), sum(precise.values()))
        self.assertEqual({case: precise[case] for case in CLASSES},
                         {'ClubStoryFlowTests': Decimal(870), 'ClubStoryNavigationFlowTests': Decimal(900)})
        self.assertGreater(sum(precise.values()), 22 * (1800 - 300))
        for count, expected in [(22, '1829.991'), (23, '1772.217')]:
            groups = SHARD.partition(precise, count)
            self.assertEqual(groups, SHARD.partition(floats, count))
            flattened = [case for group in groups for case in group]
            self.assertEqual(len(flattened), len(set(flattened)))
            self.assertEqual(set(flattened), set(counts))
            self.assertEqual(sum(counts[case] for case in flattened), 654)
            maximum = max(sum(precise[case] for case in group) + 300 for group in groups)
            self.assertEqual(maximum, Decimal(expected))
            if count == 22:
                self.assertGreater(maximum, 1800)
            else:
                self.assertLessEqual(maximum, 1800)
        self.assertEqual(float(maximum), current['maximum_projected_seconds_with_reserve'])
        self.assertEqual(Decimal(1800) - maximum, Decimal(str(current['forecast_headroom_seconds'])))

    def test_central_catalog_contains_every_exact_bilingual_fragment_value(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())
        fragment = json.loads((ROOT / 'Resources/ClubStoryLocalizations.fragment.json').read_text())
        self.assertEqual(catalog['sourceLanguage'], fragment['sourceLanguage'])
        self.assertEqual(len(fragment['strings']), 29)
        for key, value in fragment['strings'].items():
            self.assertEqual(catalog['strings'][key], value)
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
