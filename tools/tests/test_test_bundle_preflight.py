"""The fast builder releases runtime jobs without weakening required CI gates."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TestBundlePreflightTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        self.jobs = dict(re.findall(r'^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)',
                                   self.workflow.split('jobs:\n', 1)[1], re.M | re.S))
        self.native = self.jobs['native']

    def test_preflight_uses_concrete_available_destination_and_both_schemes(self):
        self.assertIn('BUILD_TEST_SIMULATOR_ID=', self.native)
        self.assertIn("d.get('isAvailable')", self.native)
        self.assertIn('for scheme in Questify QuestifyAppUnitTests; do', self.native)
        self.assertIn('CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build-for-testing', self.native)
        self.assertIn('platform=iOS Simulator,id=$BUILD_TEST_SIMULATOR_ID', self.native)

    def test_test_bundles_keep_app_and_nested_framework_architectures_aligned(self):
        loop = self.native.split('for scheme in Questify QuestifyAppUnitTests; do', 1)[1].split('done', 1)[0]
        self.assertIn('ONLY_ACTIVE_ARCH=NO build-for-testing', loop)
        self.assertNotIn('EXCLUDED_ARCHS', loop)
        self.assertNotIn('ARCHS=', loop)
        self.assertIn('-derivedDataPath "$RUNNER_TEMP/questify-simulator"', loop)

    def test_builder_keeps_all_shared_gates_and_uploads_after_both_bundles(self):
        checks = ['ci_gates.py fingerprint', 'unittest discover -s tools/tests',
                  'unittest discover -s Tests/ContractChecks', 'tools/check_scaffold.py',
                  'plutil -lint', 'git diff --exit-code -- Questify.xcodeproj',
                  'run: swift test', 'Compile iOS simulator app (unsigned)',
                  'check_built_profile.py --market CN', 'check_gltf_linked.py',
                  'Compile UI and app-unit test bundles', 'test_products.py pack',
                  'Share test products within this workflow run']
        positions = [self.native.index(check) for check in checks]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn('Compile iOS device app', self.native)
        self.assertNotIn('Compile US regional profile', self.native)
        self.assertNotIn('continue-on-error', self.workflow)
        self.assertNotIn('-skip-testing', self.workflow)

    def test_runtime_and_device_jobs_depend_only_on_verified_builder(self):
        for name in ['device-build', 'us-build', 'app-unit-tests', 'ui-tests']:
            with self.subTest(job=name):
                job = self.jobs[name]
                self.assertEqual(re.findall(r'^    needs: (.+)$', job, re.M), ['native'])
                self.assertIn('EXPECTED_BUILD_FINGERPRINT: ${{ needs.native.outputs.build_fingerprint }}', job)
                self.assertIn('ci_gates.py verify-build --github-output "$GITHUB_OUTPUT"', job)
                work = ('xcodebuild -project' if name.endswith('-build')
                        else 'uses: actions/download-artifact@')
                self.assertLess(job.index('ci_gates.py verify-build'), job.index(work))
        self.assertNotIn('    needs:', self.native)
        self.assertNotIn('    needs:', self.jobs['secrets'])

    def test_device_and_us_gates_preserve_unsigned_builds_and_profile_link_checks(self):
        device, us = self.jobs['device-build'], self.jobs['us-build']
        for job, derived in [(device, 'questify-device'), (us, 'questify-us-device')]:
            self.assertIn('-configuration Release -sdk iphoneos', job)
            self.assertIn("-destination 'generic/platform=iOS'", job)
            self.assertIn(f'-derivedDataPath "$RUNNER_TEMP/{derived}"', job)
            self.assertIn('CODE_SIGNING_ALLOWED=NO build', job)
            self.assertNotIn('test_products.py restore', job)
        # A second, Debug AppUnit build compiles the device-only acceptance bodies.
        self.assertIn('-scheme QuestifyAppUnitTests', device)
        self.assertIn('-configuration Debug -sdk iphoneos', device)
        self.assertIn('CODE_SIGNING_ALLOWED=NO build-for-testing', device)
        self.assertIn('report_protected_storage_coverage.py', device)
        self.assertNotIn('test-without-building', device)
        self.assertNotIn('-xcconfig', device)
        self.assertNotIn('-xcconfig', us)
        self.assertIn('QUESTIFY_MARKET=US QUESTIFY_API_BASE_URL= CODE_SIGNING_ALLOWED=NO build', us)
        self.assertIn('check_built_profile.py --market US', us)
        self.assertIn('check_gltf_linked.py --app "$RUNNER_TEMP/questify-us-device/', us)

    def test_us_profile_overrides_only_app_defined_regional_variables(self):
        profile = (ROOT / 'Config/UnitedStates.xcconfig').read_text()
        base = (ROOT / 'Config/Base.xcconfig').read_text()
        self.assertIn('QUESTIFY_MARKET = US', profile)
        self.assertIn('QUESTIFY_API_BASE_URL =\n', profile)
        self.assertIn('INFOPLIST_KEY_QuestifyMarket = $(QUESTIFY_MARKET)', base)
        self.assertIn('INFOPLIST_KEY_QuestifyAPIBaseURL = $(QUESTIFY_API_BASE_URL)', base)
        us = self.jobs['us-build']
        for setting in ['INFOPLIST_FILE=', 'PRODUCT_BUNDLE_IDENTIFIER=', 'GENERATE_INFOPLIST_FILE=']:
            self.assertNotIn(setting, us)

    def test_runtime_app_unit_and_all_ui_shards_are_still_required(self):
        self.assertIn('-only-testing:QuestifyAppUnitTests test-without-building', self.jobs['app-unit-tests'])
        ui = self.jobs['ui-tests']
        self.assertIn('--xctestrun "$UI_XCTESTRUN"', ui)
        self.assertEqual(self.workflow.count('name: test-products-${{ github.sha }}'), 3)
        self.assertIn('shard: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34]', ui)
        self.assertIn('fail-fast: false', ui)
        self.assertIn('python3 tools/run_ui_shard.py --shard ${{ matrix.shard }} --count 35', ui)
        self.assertIn('timeout-minutes: 37', ui)
        self.assertIn('--deadline-seconds 1800', ui)
        self.assertEqual(37 * 60 - 1800, 7 * 60)  # setup/export reserve stays seven minutes
        self.assertIn('timeout-minutes: 20', self.jobs['app-unit-tests'])
        for name in ['app-unit-tests', 'ui-tests']:
            self.assertIn('test_products.py restore', self.jobs[name])
            self.assertIn('--commit "$GITHUB_SHA"', self.jobs[name])

    def test_each_successful_ui_shard_emits_unique_exact_build_completion_last(self):
        ui = self.jobs['ui-tests']
        outputs = re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}$', ui, re.M)
        self.assertEqual(outputs, [(str(index), str(index)) for index in range(35)])
        completion = ui.split('      - name: Record successful exact-build UI shard completion\n', 1)[1]
        self.assertIn('id: completion', completion)
        self.assertIn('ci_gates.py complete-ui --shard ${{ matrix.shard }}', completion)
        self.assertNotIn('if:', completion)  # default success(), never always()
        self.assertNotIn('      - ', completion)  # must be the final step
        self.assertLess(ui.index('Retain synthetic UI screenshots'), ui.index('id: completion'))

    def test_aggregate_always_requires_every_direct_job_and_checks_shard_outputs(self):
        self.assertEqual(set(self.jobs), {'native', 'device-build', 'us-build', 'secrets',
                                         'app-unit-tests', 'ui-tests', 'required-native-gates'})
        gate = self.jobs['required-native-gates']
        self.assertIn('    if: ${{ always() }}', gate)
        self.assertIn('    needs: [native, device-build, us-build, secrets, app-unit-tests, ui-tests]', gate)
        self.assertIn('NEEDS_JSON: ${{ toJSON(needs) }}', gate)
        self.assertIn('run: python3 tools/ci_gates.py aggregate', gate)
        self.assertNotIn('if:', gate.split('    steps:\n', 1)[1])

    def test_legacy_native_required_check_name_belongs_only_to_complete_aggregate(self):
        names = {name: re.findall(r'^    name: (.+)$', job, re.M)
                 for name, job in self.jobs.items()}
        self.assertEqual(names['native'], ['native-products'])
        self.assertEqual(names['required-native-gates'], ['native'])
        self.assertEqual([job for job, values in names.items() if values == ['native']],
                         ['required-native-gates'])

    def test_permissions_pinned_actions_and_bounded_standard_runners(self):
        self.assertEqual(re.findall(r'^permissions:\n((?:  [^\n]+\n)+)', self.workflow, re.M),
                         ['  contents: read\n'])
        self.assertEqual(self.workflow.count('permissions:'), 1)
        for action in re.findall(r'uses: (\S+)', self.workflow):
            self.assertRegex(action, r'^[\w/-]+@[0-9a-f]{40}$')
        ceilings = {'native': 25, 'device-build': 20, 'us-build': 10, 'secrets': 10,
                    'app-unit-tests': 20, 'ui-tests': 37, 'required-native-gates': 2}
        for name, minutes in ceilings.items():
            self.assertIn(f'    timeout-minutes: {minutes}\n', self.jobs[name])
            runner = 'ubuntu-24.04' if name in ['secrets', 'required-native-gates'] else 'macos-26'
            self.assertIn(f'    runs-on: {runner}\n', self.jobs[name])
        self.assertEqual(self.workflow.count('persist-credentials: false'), len(self.jobs))


if __name__ == '__main__':
    unittest.main()
