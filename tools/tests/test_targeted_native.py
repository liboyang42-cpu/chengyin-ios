"""Small, synthetic diagnostic controls; no Apple execution or repository copies."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('targeted_native_runner', TOOLS / 'run_targeted_native.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SELECTION = runner.read_json(TOOLS / 'targeted_native_selection.json')
SOURCE = Path(os.environ.get('TARGETED_NATIVE_SOURCE_ROOT', str(TOOLS.parent)))
UUID = '01234567-0123-0123-0123-012345678901'


def xctests(methods, target):
    return {'testNodes': [{'nodeType': 'Test Plan', 'name': 'Questify', 'children': [
        {'nodeType': 'Unit test bundle', 'name': target, 'children': [
            {'nodeType': 'Test Case', 'name': method.rsplit('/', 1)[-1] + '()',
             'nodeIdentifier': '/'.join(method.split('/')[1:]) + '()', 'result': 'Passed'} for method in methods]}]}]}


def core_transcript(methods, status='passed'):
    lines = []
    for method in methods:
        target, cls, name = method.split('/')
        identity = f"Test Case '-[{target}.{cls} {name}]' "
        lines.extend([identity + 'started.', identity + status + ' (0.001 seconds).'])
    return ('\n'.join(lines) + '\n').encode()


def summary(count):
    return {'totalTestCount': count, 'passedTests': count, 'failedTests': 0, 'skippedTests': 0,
            'expectedFailures': 0, 'devicesAndConfigurations': [{'device': {'deviceId': UUID}}]}


class SelectionAndCommands(unittest.TestCase):
    def test_actual_bound_source_and_all_29_declarations(self):
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), SOURCE), SELECTION)
        self.assertEqual([len(g['methods']) for g in SELECTION['groups']], [10, 12, 7])
        self.assertEqual(len(set(m for g in SELECTION['groups'] for m in g['methods'])), 29)

    def test_nonboolean_version_and_exact_contract(self):
        for key, value in [('version', True), ('base_commit', 'a' * 40), ('base_tree', 'b' * 40),
                           ('name', 'all-tests'), ('branch', 'main'), ('repository', 'other/repo')]:
            mutant = copy.deepcopy(SELECTION); mutant[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_changed_source_hash_and_missing_guard_rejected(self):
        for mutation in ['change', 'missing', 'extra']:
            mutant = copy.deepcopy(SELECTION)
            if mutation == 'change': mutant['source_files'][0]['sha256'] = '0' * 64
            elif mutation == 'missing': mutant['source_files'].pop()
            else: mutant['source_files'].append({'path': '../private', 'sha256': '0' * 64})
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_empty_duplicate_target_and_wildcard_selectors_rejected(self):
        for mutation in ['empty', 'duplicate', 'target', 'wildcard', 'class', 'other-source', 'new-method']:
            mutant = copy.deepcopy(SELECTION); group = mutant['groups'][1]
            if mutation == 'empty': group['methods'] = []
            elif mutation == 'duplicate': group['methods'][0] = group['methods'][1]
            elif mutation == 'target': group['target'] = 'QuestifyUITests'
            elif mutation == 'wildcard': group['methods'][0] = 'QuestifyAppUnitTests/*/*'
            elif mutation == 'class': group['methods'][0] = 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests'
            elif mutation == 'other-source': group['source'] = 'Core/TemplateAuthoringShelf.swift'
            else: group['methods'][0] += 'Other'
            group['methods'].sort()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_core_filter_is_exact_set_without_full_suite_fallback(self):
        group = SELECTION['groups'][0]; command = runner.core_command(group, '/tmp/result.xml')
        pattern = re.compile(command[command.index('--filter') + 1])
        for method in group['methods']:
            swift_id = method.replace('/', '.', 1)
            self.assertIsNotNone(pattern.fullmatch(swift_id))
            for extra in ['Extra', '/extra', '()']:
                self.assertIsNone(pattern.fullmatch(swift_id + extra))
        self.assertIsNone(pattern.fullmatch('QuestifyCoreTests.TemplateAuthoringHTTPTests/testChangedBaselinePreventsWrite'))
        self.assertEqual(command[command.index('--num-workers') + 1], '1')
        with self.assertRaises(ValueError): runner.core_command({'methods': []}, '/tmp/result.xml')

    def test_every_xcode_method_has_its_own_exact_filter(self):
        for group in SELECTION['groups'][1:]:
            command = runner.xcode_test_command(group, '/tmp/one.xctestrun', UUID, '/tmp/one.xcresult')
            self.assertEqual([s for s in command if s.startswith('-only-testing:')], ['-only-testing:' + m for m in group['methods']])
            self.assertEqual(command.count('-destination'), 1)
            self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
            self.assertEqual(command[command.index('-maximum-concurrent-test-simulator-destinations') + 1], '1')
            self.assertEqual(command[-1], 'test-without-building')
            self.assertNotIn('-allowProvisioningUpdates', command)

    def test_workflow_remains_additive_standard_and_independent(self):
        path = TOOLS.parent / '.github/workflows/native-targeted.yml'; text = path.read_text()
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        self.assertEqual(re.findall(r'^    runs-on: (.*)$', active, re.M), ['macos-26'])
        self.assertEqual(re.findall(r'^  (\w+):$', active.split('jobs:', 1)[1], re.M), ['targeted'])
        self.assertIn('branches: [migration/native-ios]', active)
        self.assertEqual(re.findall(r'^      - (.+)$', active.split('permissions:', 1)[0], re.M), list(runner.PATHS))
        self.assertIn('  workflow_dispatch:', active)
        self.assertIn('  contents: read', active)
        self.assertIn('persist-credentials: false', active)
        self.assertIn('GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch --no-tags --depth=1 https://github.com/liboyang42-cpu/chengyin-ios.git ' + runner.BASE_COMMIT, active)
        self.assertIn('timeout-minutes: 45', active)
        self.assertIn('name: native-targeted-diagnostic', active)
        for forbidden in ['needs:', 'matrix:', 'upload-artifact', 'download-artifact', 'secrets.', 'required-native-gates', 'run_static_checks.py', 'ci_gates.py aggregate']:
            self.assertNotIn(forbidden, active)
        self.assertNotIn('group: native-ios-', active)

    def test_original_gates_project_schemes_and_product_sources_are_unchanged(self):
        for row in SELECTION['source_files']:
            self.assertEqual(runner.digest(SOURCE / row['path']), row['sha256'], row['path'])
        old = (SOURCE / '.github/workflows/native-ios.yml').read_text()
        self.assertIn('needs: static-checks', old)
        self.assertIn('needs: [static-checks, native, device-build, us-build, secrets, app-unit-tests, ui-tests]', old)
        self.assertIn('name: native\n', old)
        self.assertIn('SHARD_COUNT = 79', (SOURCE / 'tools/ci_gates.py').read_text())


class Results(unittest.TestCase):
    def setUp(self):
        self.group = SELECTION['groups'][1]
        self.rows = [{'method': m, 'status': 'Passed'} for m in self.group['methods']]

    def test_xunit_reads_all_ten_real_cases(self):
        methods = SELECTION['groups'][0]['methods']
        xml = '<testsuites><testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '()" />' for m in methods) + '</testsuite></testsuites>'
        rows = runner.parse_xunit(xml.encode()); runner.validate_outcomes(rows, methods, 0)
        self.assertEqual(len(rows), 10)

    def test_core_transcript_proves_execution_beyond_swiftpm_xunit(self):
        methods = SELECTION['groups'][0]['methods']
        xml = ('<testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '" />' for m in methods) + '</testsuite>').encode()
        rows = runner.validate_core_evidence(xml, core_transcript(methods), methods, 0)
        self.assertEqual(len(rows), 10)
        # SwiftPM's successful child process xUnit looks identical for XCTSkip
        # and for a discovered method whose child process executes zero cases.
        mutants = [b'', b'Executed 0 tests, with 0 failures.\n', core_transcript(methods, 'skipped'),
                   core_transcript(methods, 'failed'), core_transcript(methods[:-1]),
                   core_transcript(methods + methods[:1]), core_transcript(methods).replace(b'started.', b'unknown.'),
                   core_transcript(methods).replace(b'QuestifyCoreTests.', b'OtherTarget.'),
                   core_transcript(methods).replace(b'started.\n', b'')]
        for transcript in mutants:
            with self.subTest(transcript=transcript[:90]), self.assertRaises(ValueError):
                runner.validate_core_evidence(xml, transcript, methods, 0)
        self.assertIn('--verbose', runner.core_command(SELECTION['groups'][0], '/tmp/result.xml'))
        self.assertIn('--skip-build', runner.core_command(SELECTION['groups'][0], '/tmp/result.xml'))

    def test_xunit_failures_skips_and_unknown_status_cannot_pass(self):
        for child in ['<failure/>', '<error/>', '<skipped/>']:
            xml = '<testsuite><testcase classname="QuestifyCoreTests.Example" name="testOne">' + child + '</testcase></testsuite>'
            rows = runner.parse_xunit(xml.encode())
            with self.assertRaises(ValueError): runner.validate_outcomes(rows, ['QuestifyCoreTests/Example/testOne'], 0)
        for xml in [b'<unknown/>', b'<testsuite><testcase classname="Wrong.Example" name="testOne"/></testsuite>', b'<testsuite><testcase classname="QuestifyCoreTests.Example" name="testOne" status="skipped"/></testsuite>']:
            with self.assertRaises(ValueError): runner.parse_xunit(xml)

    def test_modern_xcresult_exact_target_and_method_set(self):
        rows = runner.parse_xcresult(xctests(self.group['methods'], self.group['target']), self.group['target'])
        self.assertEqual(rows, self.rows)
        runner.validate_outcomes(rows, self.group['methods'], 0)
        runner.validate_summary(summary(12), 12, UUID)

    def test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema(self):
        for mutation in ['schema', 'target', 'method', 'status']:
            data = xctests(self.group['methods'], self.group['target'])
            bundle = data['testNodes'][0]['children'][0]; case = bundle['children'][0]
            if mutation == 'schema': data = {'other': data['testNodes']}
            elif mutation == 'target': bundle['name'] = 'QuestifyUITests'
            elif mutation == 'method': case['nodeIdentifier'] = 'UnknownTarget/Class/testOther'
            else: del case['result']
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])

    def test_target_url_binding_must_not_override_wrong_bundle(self):
        data = xctests(self.group['methods'], self.group['target']); case = data['testNodes'][0]['children'][0]['children'][0]
        case['nodeIdentifierURL'] = 'test://com.apple.xcode/Questify/' + self.group['methods'][0] + '()'
        self.assertEqual(runner.parse_xcresult(data, self.group['target']), self.rows)
        case['nodeIdentifierURL'] = case['nodeIdentifierURL'].replace('QuestifyAppUnitTests', 'QuestifyUITests')
        with self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])

    def test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail(self):
        mutants = [[], self.rows[:-1], self.rows + self.rows[:1], self.rows + [{'method': 'QuestifyAppUnitTests/Other/testExtra', 'status': 'Passed'}]]
        for status in ['Skipped', 'Failed', 'Expected Failure', 'Unknown', 'Cancelled']:
            rows = copy.deepcopy(self.rows); rows[0]['status'] = status; mutants.append(rows)
        for rows in mutants:
            with self.assertRaises(ValueError): runner.validate_outcomes(rows, self.group['methods'], 0)
        for code in [1, 65, 124, -2, -9]:
            with self.assertRaises(ValueError): runner.validate_outcomes(self.rows, self.group['methods'], code)

    def test_hidden_repetitions_and_xunit_summary_disagreement_fail(self):
        data = xctests(self.group['methods'], self.group['target'])
        case = data['testNodes'][0]['children'][0]['children'][0]
        case['children'] = [{'nodeType': 'Test Case', 'name': 'hidden', 'result': 'Failed'}]
        with self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])
        for attributes in ['tests="0"', 'tests="1" failures="1"', 'tests="1" skipped="1"']:
            raw = ('<testsuite ' + attributes + '><testcase classname="QuestifyCoreTests.Example" name="testOne"/></testsuite>').encode()
            with self.assertRaises(ValueError): runner.parse_xunit(raw)
        with self.assertRaises(ValueError): runner.validate_outcomes(self.rows, self.group['methods'], False)

    def test_summary_counts_actual_device_and_no_boolean_counts(self):
        for key, value in [('totalTestCount', 0), ('passedTests', 11), ('failedTests', 1), ('skippedTests', 1), ('expectedFailures', 1), ('totalTestCount', True), ('devicesAndConfigurations', [])]:
            mutant = summary(12); mutant[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_summary(mutant, 12, UUID)
        with self.assertRaises(ValueError): runner.validate_summary(summary(12), 12, 'OTHER')


class RuntimeBoundaries(unittest.TestCase):
    def test_single_installed_iphone_and_no_automatic_other_device(self):
        data = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{'name': 'iPhone 17', 'udid': UUID, 'isAvailable': True}],
                            'com.apple.CoreSimulator.SimRuntime.tvOS-26-0': [{'name': 'iPhone wrong', 'udid': UUID, 'isAvailable': True}]}}
        self.assertEqual(runner.choose_simulator(data)['udid'], UUID)
        for mutant in [{}, {'devices': {}}, {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{'name': 'iPad', 'udid': UUID, 'isAvailable': True}]}}]:
            with self.assertRaises(ValueError): runner.choose_simulator(mutant)

    def test_run_requires_hosted_mac_exact_repo_branch_and_event(self):
        environment = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_REPOSITORY': 'liboyang42-cpu/chengyin-ios', 'GITHUB_REF': 'refs/heads/migration/native-ios', 'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1'}
        with mock.patch.object(sys, 'platform', 'darwin'):
            runner.runtime_environment(environment)
            for key, value in [('RUNNER_ENVIRONMENT', 'self-hosted'), ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ID', '0'), ('GITHUB_RUN_ATTEMPT', '')]:
                mutant = dict(environment); mutant[key] = value
                with self.assertRaises(ValueError): runner.runtime_environment(mutant)
        with mock.patch.object(sys, 'platform', 'linux'), self.assertRaises(ValueError): runner.runtime_environment(environment)

    def test_process_exit_is_real_and_timeout_never_passes(self):
        code, data = runner.execute([sys.executable, '-c', 'print("small")'], SOURCE, 5, True)
        self.assertEqual((code, data.strip()), (0, b'small'))
        code, _ = runner.execute([sys.executable, '-c', 'import time; time.sleep(60)'], SOURCE, .03, True)
        self.assertEqual(code, 124)
        with self.assertRaises(ValueError): runner.execute(['not-run'], SOURCE, 0)

    def test_core_build_is_once_before_exact_execution_and_failure_stops(self):
        class StopAfterCore(Exception):
            pass
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40}
        environment = {'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_WORKFLOW_SHA': 'a' * 40}
        for code in [0, 1, 124]:
            with tempfile.TemporaryDirectory() as temporary:
                job = runner.Diagnostic(TOOLS.parent, Path(temporary), SELECTION)
                order = []
                def command(args, seconds, capture=False):
                    order.append(('build', args, seconds, capture))
                    return code, b''
                def collect(group, args, seconds, result):
                    order.append(('test', args, seconds))
                    raise StopAfterCore()
                with mock.patch.object(runner, 'runtime_environment'), mock.patch.object(runner, 'verify_scope', return_value=identity), mock.patch.dict(os.environ, environment), mock.patch.object(job, 'toolchain', return_value={}), mock.patch.object(job, 'command', side_effect=command), mock.patch.object(job, 'collect', side_effect=collect):
                    with self.assertRaises(StopAfterCore if code == 0 else ValueError): job.run()
                self.assertEqual(order[0], ('build', ['swift', 'build', '--build-tests'], 720, False))
                self.assertEqual([item[0] for item in order], ['build', 'test'] if code == 0 else ['build'])
                self.assertEqual(job.receipt['groups']['core']['build_returncode'], code)
                if code == 0:
                    self.assertEqual(order[1][1], runner.core_command(SELECTION['groups'][0], Path(temporary) / 'core.xml'))
                    self.assertEqual(order[1][2], 180)
                self.assertEqual(job.receipt['groups']['core']['actual_count'], 0)

    def test_core_capture_keeps_stderr_live_and_limits_only_evidence(self):
        process = mock.Mock(); process.returncode = 0
        process.communicate.return_value = (b'small XCTest transcript', None)
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process) as popen:
            self.assertEqual(runner.execute(['swift', 'test', '--skip-build'], SOURCE, 5, 'stdout'),
                             (0, b'small XCTest transcript'))
            self.assertEqual(popen.call_args.kwargs['stdout'], subprocess.PIPE)
            self.assertIsNone(popen.call_args.kwargs['stderr'])
        process.communicate.return_value = (b'x' * (runner.LIMIT + 1), None)
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process), self.assertRaises(ValueError):
            runner.execute(['fake'], SOURCE, 5, 'stdout')
        source = (TOOLS / 'run_targeted_native.py').read_text()
        self.assertIn("self.command(['swift', 'build', '--build-tests'], 720)", source)
        self.assertIn("self.collect(groups['core'], core_command(groups['core'], core), 180, core)", source)

    def test_every_cleanup_wait_is_bounded_even_after_kill(self):
        process = mock.Mock(); process.pid = 10
        process.communicate.side_effect = [subprocess.TimeoutExpired('fake', 1)] * 4
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process), mock.patch.object(runner.os, 'killpg') as kill:
            with self.assertRaises(RuntimeError): runner.execute(['fake'], SOURCE, 1)
            self.assertEqual([c.kwargs['timeout'] for c in process.communicate.call_args_list], [1, 20, 10, 5])
            self.assertEqual([c.args[1] for c in kill.call_args_list], [signal.SIGINT, signal.SIGTERM, signal.SIGKILL])

    def test_product_target_selection_supports_only_safe_testhost_tokens(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); host = root / 'Debug/Questify.app'; bundle = host / 'PlugIns/QuestifyAppUnitTests.xctest'; bundle.mkdir(parents=True)
            path = root / 'app.xctestrun'
            value = {'TestTargets': [{'TestBundlePath': '__TESTHOST__/PlugIns/QuestifyAppUnitTests.xctest', 'TestHostPath': '__TESTROOT__/Debug/Questify.app'}]}
            path.write_bytes(plistlib.dumps(value))
            self.assertEqual(runner.select_xctestrun(root, 'QuestifyAppUnitTests'), path.resolve())
            for target in ['QuestifyUITests', 'Other']:
                with self.assertRaises(ValueError): runner.select_xctestrun(root, target)
            value['TestTargets'][0]['TestHostPath'] = '/etc'; path.write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyAppUnitTests')

    def test_product_directory_alias_returns_canonical_safe_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); products = root / 'actual'; products.mkdir()
            (products / 'QuestifyUITests.xctest').mkdir()
            run = products / 'ui.xctestrun'
            run.write_bytes(plistlib.dumps({'tests': [{'TestBundlePath': '__TESTROOT__/QuestifyUITests.xctest'}]}))
            alias = root / 'alias'; alias.symlink_to(products, target_is_directory=True)
            self.assertEqual(runner.select_xctestrun(alias, 'QuestifyUITests'), run.resolve())
            escaped = products / 'linked.xctestrun'; escaped.symlink_to(run)
            with self.assertRaises(ValueError): runner.select_xctestrun(alias, 'QuestifyUITests')

    def test_ambiguous_products_and_extra_target_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'QuestifyUITests.xctest').mkdir()
            value = {'tests': [{'TestBundlePath': str(root / 'QuestifyUITests.xctest')}]}
            for name in ['one', 'two']: (root / (name + '.xctestrun')).write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyUITests')
            (root / 'two.xctestrun').unlink(); value['tests'].append({'TestBundlePath': '/elsewhere/Other.xctest'})
            (root / 'one.xctestrun').write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyUITests')

    def test_inventory_detects_product_mutation_and_escaping_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'binary').write_bytes(b'one')
            before = runner.products_digest(root); (root / 'binary').write_bytes(b'two')
            self.assertNotEqual(before, runner.products_digest(root))
            (root / 'escaped').symlink_to('/etc')
            with self.assertRaises(ValueError): runner.products_digest(root)

    def test_scope_requires_exact_sha_base_and_only_four_added_paths(self):
        def output(command, root):
            if command[1:3] == ['rev-parse', 'HEAD']: return 'a' * 40
            if command[1:3] == ['rev-parse', runner.BASE_COMMIT + '^{tree}']: return runner.BASE_TREE
            if command[1:3] == ['rev-parse', 'HEAD^{tree}']: return 'b' * 40
            if command[1] == 'status': return ''
            if command[1] == 'diff': return '\n'.join('A\t' + p for p in runner.PATHS)
            raise AssertionError(command)
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=output):
            self.assertEqual(runner.verify_scope(SOURCE, SELECTION)['source_tree'], 'b' * 40)
        for field in ['head', 'base', 'diff', 'dirty']:
            def mutated(command, root):
                original = output(command, root)
                if field == 'head' and command[1:3] == ['rev-parse', 'HEAD']: return 'c' * 40
                if field == 'base' and command[1:3] == ['rev-parse', runner.BASE_COMMIT + '^{tree}']: return 'c' * 40
                if field == 'diff' and command[1] == 'diff': return original + '\nM\tApp/AppSession.swift'
                if field == 'dirty' and command[1] == 'status': return ' M App/AppSession.swift'
                return original
            with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=mutated), self.assertRaises(ValueError):
                runner.verify_scope(SOURCE, SELECTION)

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'bad.json'; path.write_text('{"status":"FAIL","status":"PASS"}')
            with self.assertRaises(ValueError): runner.read_json(path)

    def test_missing_receipt_reports_not_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); destination = root / 'summary'
            runner.report(root, destination)
            self.assertIn('NOT_RUN', destination.read_text())
            self.assertNotIn('PASS', destination.read_text())


class ReceiptIdentity(unittest.TestCase):
    def receipt(self):
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40, 'workflow_sha': 'a' * 40,
                    'run_id': '123', 'run_attempt': '1', 'selection_sha256': 'c' * 64}
        r = {**identity, 'version': 1, 'status': 'PASS', 'scope': 'selected-native-diagnostic-only',
             'base_commit': runner.BASE_COMMIT, 'base_tree': runner.BASE_TREE,
             'selection': SELECTION['name'], 'expected_count': 29, 'actual_count': 29,
             'toolchain': {k: k for k in ['xcode', 'developer', 'swift', 'sdk_version', 'sdk_path']},
             'simulator': {'udid': UUID, 'name': 'iPhone 17', 'runtime': 'com.apple.CoreSimulator.SimRuntime.iOS-26-0'},
             'groups': {g['name']: {'status': 'PASS', 'expected': g['methods'], 'actual_count': len(g['methods']), 'returncode': 0,
                                   'actual': [{'method': m, 'status': 'Passed'} for m in g['methods']]} for g in SELECTION['groups']},
             'products': {}}
        r['groups']['core']['build_returncode'] = 0
        for name, config in [('ui', 'Debug/iphonesimulator/unsigned/ONLY_ACTIVE_ARCH=NO'), ('app-unit', 'Debug/iphonesimulator/isolated-entitlement-section/adhoc-host')]:
            r['products'][name] = {'configuration': config, 'files': 3, 'sha256': 'd' * 64, 'xctestrun_sha256': 'e' * 64}
        for group in SELECTION['groups']:
            for key in (['result_sha256', 'transcript_sha256'] if group['kind'] == 'swift' else ['summary_sha256', 'tests_sha256']):
                r['groups'][group['name']][key] = '9' * 64
        r['products']['app-unit']['manifest'] = {'commit': identity['source_sha'], 'purpose': 'isolated-simulator-app-unit',
            'toolchain': {k: r['toolchain'][k] for k in ['xcode', 'developer']}, 'source_archive_sha256': 'f' * 64}
        return r, identity

    def test_exact_same_run_sha_tree_configuration_and_29_results(self):
        receipt, identity = self.receipt(); runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_report_revalidates_real_exported_files_not_just_receipt_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'tools').mkdir(); output = root / 'results'; output.mkdir()
            selection_path = root / runner.PATHS[1]; runner.write_json(selection_path, SELECTION)
            receipt, identity = self.receipt(); receipt['selection_sha256'] = runner.digest(selection_path)
            methods = SELECTION['groups'][0]['methods']
            xml = '<testsuites><testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '()" />' for m in methods) + '</testsuite></testsuites>'
            (output / 'core.xml').write_text(xml); receipt['groups']['core']['result_sha256'] = runner.digest(output / 'core.xml')
            (output / 'core-stdout.txt').write_bytes(core_transcript(methods)); receipt['groups']['core']['transcript_sha256'] = runner.digest(output / 'core-stdout.txt')
            for group in SELECTION['groups'][1:]:
                for part, data in [('summary', summary(len(group['methods']))), ('tests', xctests(group['methods'], group['target']))]:
                    path = output / (group['name'] + '-' + part + '.json'); runner.write_json(path, data)
                    receipt['groups'][group['name']][part + '_sha256'] = runner.digest(path)
            runner.write_json(output / 'receipt.json', receipt)
            environment = {'GITHUB_SHA': identity['source_sha'], 'GITHUB_WORKFLOW_SHA': identity['workflow_sha'], 'GITHUB_RUN_ID': identity['run_id'], 'GITHUB_RUN_ATTEMPT': identity['run_attempt']}
            with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', return_value=identity['source_tree']), mock.patch('builtins.print'):
                runner.report(output, root / 'summary', root)
                self.assertIn('Actual methods: 29 / 29', (root / 'summary').read_text())
                transcript = output / 'core-stdout.txt'
                transcript.write_bytes(core_transcript(methods, 'skipped'))
                receipt['groups']['core']['transcript_sha256'] = runner.digest(transcript)
                runner.write_json(output / 'receipt.json', receipt)
                with self.assertRaises(ValueError): runner.report(output, None, root)
                transcript.write_bytes(core_transcript(methods))
                receipt['groups']['core']['transcript_sha256'] = runner.digest(transcript)
                runner.write_json(output / 'receipt.json', receipt)
                path = output / 'app-unit-tests.json'; changed = runner.read_json(path)
                changed['testNodes'][0]['children'][0]['children'][0]['result'] = 'Failed'; runner.write_json(path, changed)
                with self.assertRaises(ValueError): runner.report(output, None, root)
                receipt['groups']['app-unit']['tests_sha256'] = runner.digest(path); runner.write_json(output / 'receipt.json', receipt)
                with self.assertRaises(ValueError): runner.report(output, None, root)

    def test_other_run_attempt_sha_tree_selection_or_workflow_rejected(self):
        for key in ['run_id', 'run_attempt', 'source_sha', 'source_tree', 'selection_sha256', 'workflow_sha']:
            receipt, identity = self.receipt(); receipt[key] = 'different'
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected(self):
        for mode in ['config', 'toolchain', 'simulator', 'count', 'group', 'product-sha', 'archive', 'manifest-sha', 'result-sha', 'core-build']:
            receipt, identity = self.receipt()
            if mode == 'core-build': receipt['groups']['core']['build_returncode'] = 1
            elif mode == 'config': receipt['products']['ui']['configuration'] = 'Release/iphoneos'
            elif mode == 'toolchain': del receipt['toolchain']['sdk_version']
            elif mode == 'simulator': receipt['simulator']['name'] = 'iPad'
            elif mode == 'count': receipt['actual_count'] = 0
            elif mode == 'group': receipt['groups']['ui']['actual'] = []
            elif mode == 'product-sha': receipt['products']['ui']['sha256'] = ''
            elif mode == 'archive': receipt['products']['app-unit']['manifest']['source_archive_sha256'] = ''
            elif mode == 'result-sha': del receipt['groups']['core']['result_sha256']
            else: receipt['products']['app-unit']['manifest']['commit'] = 'z' * 40
            with self.subTest(mode=mode), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)


if __name__ == '__main__':
    unittest.main()
