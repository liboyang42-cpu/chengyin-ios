import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_gates', TOOLS / 'ci_gates.py')
module = importlib.util.module_from_spec(spec)
with mock.patch.object(sys, 'path', [str(TOOLS)] + sys.path):
    spec.loader.exec_module(module)


class NativeCIGateTests(unittest.TestCase):
    sha = 'a' * 40
    identity = {'xcode': 'Xcode fixture\nBuild version fixture', 'developer': '/fixture/Xcode'}

    def setUp(self):
        self.value = module.encode({'version': 1, 'commit': self.sha, 'head': self.sha,
                                    'toolchain': self.identity})
        self.needs = {name: {'result': 'success', 'outputs': {}}
                      for name in module.REQUIRED_JOBS}
        for name in ['native', 'device-build', 'us-build', 'app-unit-tests']:
            self.needs[name]['outputs']['build_fingerprint'] = self.value
        self.needs['ui-tests']['outputs'] = dict(module.ui_completion(index, self.value, self.sha)
                                                 for index in range(module.SHARD_COUNT))

    def test_fingerprint_records_matching_github_sha_head_and_existing_toolchain(self):
        with mock.patch.object(module.subprocess, 'check_output', return_value=self.sha + '\n') as git:
            with mock.patch.object(module, 'toolchain', return_value=self.identity) as tools:
                self.assertEqual(module.fingerprint(self.sha), self.value)
                git.assert_called_once_with(['git', 'rev-parse', 'HEAD'], text=True)
                tools.assert_called_once_with()

    def test_invalid_sha_or_different_checked_out_head_fails_before_toolchain(self):
        for bad in ['', 'a' * 39, 'b' * 41, 'A' * 40, None, 'a' * 40 + '\n']:
            with self.subTest(commit=bad), self.assertRaises(ValueError):
                module.validate_commit(bad)
        with mock.patch.object(module.subprocess, 'check_output', return_value='b' * 40):
            with mock.patch.object(module, 'toolchain') as tools:
                with self.assertRaises(ValueError): module.fingerprint(self.sha)
                tools.assert_not_called()

    def test_gate_accepts_only_exact_builder_toolchain(self):
        with mock.patch.object(module, 'fingerprint', return_value=self.value):
            self.assertEqual(module.verify_build(self.value, self.sha), self.value)
        with mock.patch.object(module, 'fingerprint', return_value=self.value.replace('fixture', 'other')):
            with self.assertRaises(ValueError): module.verify_build(self.value, self.sha)

    def test_missing_malformed_or_wrong_sha_fingerprint_fails_closed(self):
        malformed = [None, '', 'null', '{}', '[]', 'invalid json']
        for key, bad in [('version', True), ('version', 2), ('commit', 'b' * 40),
                         ('head', 'b' * 40), ('toolchain', {}),
                         ('toolchain', {'xcode': '', 'developer': '/fixture'}),
                         ('toolchain', {'xcode': 'Xcode', 'developer': None})]:
            data = json.loads(self.value); data[key] = bad
            malformed.append(json.dumps(data))
        for key in ['head', 'commit', 'toolchain']:
            data = json.loads(self.value); del data[key]; malformed.append(json.dumps(data))
        for value in malformed:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.validated_fingerprint(value, self.sha)

    def test_aggregate_accepts_all_success_and_all_configured_exact_build_shards(self):
        module.aggregate(self.needs, self.sha)

    def test_every_required_job_rejects_failure_cancelled_skipped_and_missing_result(self):
        for name in module.REQUIRED_JOBS:
            for result in ['failure', 'cancelled', 'skipped', '', None]:
                needs = copy.deepcopy(self.needs); needs[name]['result'] = result
                with self.subTest(job=name, result=result), self.assertRaises(ValueError):
                    module.aggregate(needs, self.sha)
            needs = copy.deepcopy(self.needs); del needs[name]['result']
            with self.subTest(job=name), self.assertRaises(ValueError):
                module.aggregate(needs, self.sha)

    def test_missing_unexpected_or_malformed_jobs_fail_closed(self):
        for name in module.REQUIRED_JOBS:
            needs = copy.deepcopy(self.needs); del needs[name]
            with self.subTest(missing=name), self.assertRaises(ValueError): module.aggregate(needs, self.sha)
            needs = copy.deepcopy(self.needs); needs[name] = None
            with self.subTest(malformed=name), self.assertRaises(ValueError): module.aggregate(needs, self.sha)
            needs = copy.deepcopy(self.needs); del needs[name]['outputs']
            with self.subTest(outputs=name), self.assertRaises(ValueError): module.aggregate(needs, self.sha)
        needs = copy.deepcopy(self.needs); needs['extra'] = {'result': 'success', 'outputs': {}}
        with self.assertRaises(ValueError): module.aggregate(needs, self.sha)
        with self.assertRaises(ValueError): module.aggregate([], self.sha)

    def test_each_consumer_requires_exact_matching_fingerprint_output(self):
        for name in ['native', 'device-build', 'us-build', 'app-unit-tests']:
            for value in ['', self.value.replace('fixture', 'other'), self.value.replace(self.sha, 'b' * 40)]:
                needs = copy.deepcopy(self.needs); needs[name]['outputs']['build_fingerprint'] = value
                with self.subTest(job=name, value=value), self.assertRaises(ValueError):
                    module.aggregate(needs, self.sha)

    def test_successful_matrix_result_cannot_hide_any_missing_or_stale_shard(self):
        for index in range(module.SHARD_COUNT):
            for value in ['', 'b' * 64, self.sha, None]:
                needs = copy.deepcopy(self.needs); needs['ui-tests']['outputs'][f'shard_{index}'] = value
                with self.subTest(shard=index, value=value), self.assertRaises(ValueError):
                    module.aggregate(needs, self.sha)
            needs = copy.deepcopy(self.needs); del needs['ui-tests']['outputs'][f'shard_{index}']
            with self.subTest(missing=index), self.assertRaises(ValueError): module.aggregate(needs, self.sha)
        needs = copy.deepcopy(self.needs); needs['ui-tests']['outputs'][f'shard_{module.SHARD_COUNT}'] = 'a' * 64
        with self.assertRaises(ValueError): module.aggregate(needs, self.sha)

    def test_ui_completion_uses_unique_shard_keys_and_canonical_fingerprint_hash(self):
        outputs = [module.ui_completion(index, self.value, self.sha) for index in range(module.SHARD_COUNT)]
        self.assertEqual([key for key, _ in outputs], [f'shard_{index}' for index in range(module.SHARD_COUNT)])
        self.assertEqual(len({value for _, value in outputs}), 1)
        equivalent = json.dumps(json.loads(self.value), indent=2)
        self.assertEqual(module.completion_digest(equivalent, self.sha), outputs[0][1])
        for index in [-1, module.SHARD_COUNT, True, '0']:
            with self.subTest(shard=index), self.assertRaises(ValueError):
                module.ui_completion(index, self.value, self.sha)

    def test_output_is_single_line_even_with_multiline_xcode_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'outputs'
            module.write_output(path, 'build_fingerprint', self.value)
            self.assertEqual(path.read_text().splitlines(), ['build_fingerprint=' + self.value])
            for key, value in [('x\ny', 'v'), ('key', 'x\ny'), ('key', 'x\ry')]:
                with self.assertRaises(ValueError): module.write_output(path, key, value)


if __name__ == '__main__':
    unittest.main()
