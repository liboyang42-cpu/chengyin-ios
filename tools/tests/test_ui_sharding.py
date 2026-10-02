import importlib.util
import pathlib
import re
import json
import tempfile
import unittest
from unittest import mock

spec=importlib.util.spec_from_file_location('ui_shard',pathlib.Path(__file__).resolve().parents[1]/'run_ui_shard.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class UIShardingTests(unittest.TestCase):
    def test_workflow_count_matches_exhaustive_default(self):
        workflow=(module.ROOT/'.github/workflows/native-ios.yml').read_text()
        matrix=re.search(r'shard:\s*\[([0-9,\s]+)\]',workflow)
        self.assertIsNotNone(matrix)
        indices=[int(item.strip()) for item in matrix.group(1).split(',')]
        self.assertEqual(indices,list(range(module.DEFAULT_SHARD_COUNT)))
        counts=re.findall(r'run_ui_shard\.py[^\n]*--count\s+(\d+)',workflow)
        self.assertEqual(counts,[str(module.DEFAULT_SHARD_COUNT)])
        weights=module.discover(module.ROOT/'Tests/AppUITests')
        groups=module.partition(module.measured_weights(module.ROOT/'Tests/AppUITests',module.ROOT/'tools/ui_duration_weights.json'),module.DEFAULT_SHARD_COUNT)
        flattened=sum(groups,[])
        self.assertEqual(len(flattened),len(set(flattened)))
        self.assertEqual(set(flattened),set(weights))
        self.assertEqual(sum(weights[name] for name in flattened),sum(weights.values()))
    def test_partition_covers_every_class_once(self):
        weights={'A':11,'B':7,'C':4,'D':3,'E':3,'F':4,'G':2}
        groups=module.partition(weights,2)
        flat=sum(groups,[])
        self.assertEqual(set(flat),set(weights));self.assertEqual(len(flat),len(set(flat)))
        self.assertEqual(groups,module.partition(dict(reversed(list(weights.items()))),2))
    def test_invalid_shards_fail(self):
        for count in [0,-1,3]:
            with self.assertRaises(ValueError):module.partition({'A':1,'B':2},count)
    def test_discovers_methods_and_rejects_ambiguous_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'Example.swift'
            path.write_text('final class Example: XCTestCase { func testA() {} func testB() {} }')
            self.assertEqual(module.discover(directory),{'Example':2})
            path.write_text('class A: XCTestCase {func testA(){}} class B: XCTestCase {func testB(){}}')
            with self.assertRaises(ValueError):module.discover(directory)
    def test_empty_inventory_is_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):module.discover(directory)
    def test_prebuilt_mode_keeps_all_selected_classes_without_rebuild(self):
        with tempfile.TemporaryDirectory() as directory:
            run=pathlib.Path(directory)/'fixture.xctestrun';run.touch()
            args=['run_ui_shard.py','--shard','0','--count','6','--simulator','synthetic',
                  '--result-bundle',str(pathlib.Path(directory)/'result'),'--xctestrun',str(run)]
            process=mock.Mock();process.wait.return_value=0
            with mock.patch('sys.argv',args),mock.patch.object(module.subprocess,'Popen',return_value=process) as start:
                self.assertEqual(module.main(),0)
            command=start.call_args.args[0]
            self.assertIn('test-without-building',command);self.assertIn('-xctestrun',command)
            self.assertNotIn('-project',command);self.assertNotIn('-derivedDataPath',command)
            groups=module.partition(module.measured_weights(module.ROOT/'Tests/AppUITests',module.ROOT/'tools/ui_duration_weights.json'),6)
            self.assertEqual([v for v in command if v.startswith('-only-testing:')],
                             [f'-only-testing:QuestifyUITests/{name}' for name in groups[0]])
    def test_deadline_never_turns_partial_execution_into_success(self):
        with tempfile.TemporaryDirectory() as directory:
            run=pathlib.Path(directory)/'fixture.xctestrun';run.touch()
            args=['run_ui_shard.py','--shard','0','--simulator','synthetic','--result-bundle','fixture',
                  '--xctestrun',str(run),'--deadline-seconds','1']
            process=mock.Mock();process.wait.side_effect=[module.subprocess.TimeoutExpired('xcodebuild',1),0]
            with mock.patch('sys.argv',args),mock.patch.object(module.subprocess,'Popen',return_value=process):
                self.assertEqual(module.main(),124)
            process.send_signal.assert_called_once_with(module.signal.SIGINT)

    def test_timing_balances_expensive_classes_without_dropping_new_methods(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            for name in ['A','B','C','D']:
                (root/(name+'.swift')).write_text('class '+name+': XCTestCase { func testOne() {} }')
            profile=root/'profile.json'
            profile.write_text(json.dumps({'version':1,'unobserved_method_seconds':30,'method_seconds':{'A.testOne':100,'B.testOne':100,'C.testOne':1,'Removed.testOld':900}}))
            costs=module.measured_weights(root,profile)
            self.assertEqual(costs,{'A':100,'B':100,'C':1,'D':30})
            groups=module.partition(costs,2)
            self.assertNotIn('B',groups[0] if 'A' in groups[0] else groups[1])
            self.assertEqual(set(sum(groups,[])),set(module.discover(root)))
    def test_invalid_or_nonfinite_timing_profile_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);(root/'A.swift').write_text('class A: XCTestCase {func testOne(){}}')
            profile=root/'profile.json'
            for value in [0,-1,True,float('nan'),float('inf'),'3']:
                profile.write_text(json.dumps({'version':1,'unobserved_method_seconds':30,'method_seconds':{'A.testOne':value}}))
                with self.assertRaises(ValueError):module.measured_weights(root,profile)
            profile.write_text(json.dumps({'version':2,'unobserved_method_seconds':30,'method_seconds':{}}))
            with self.assertRaises(ValueError):module.measured_weights(root,profile)
    def test_missing_profile_is_not_silent_case_count_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);(root/'A.swift').write_text('class A: XCTestCase {func testOne(){}}')
            with self.assertRaises(FileNotFoundError):module.measured_weights(root,root/'missing.json')

    def test_checked_in_profile_contains_actual_varied_observations(self):
        data=json.loads((module.ROOT/'tools/ui_duration_weights.json').read_text())
        self.assertGreaterEqual(len(data['method_seconds']),100)
        self.assertGreater(len(set(data['method_seconds'].values())),1)
        weights=module.discover(module.ROOT/'Tests/AppUITests')
        costs=module.measured_weights(module.ROOT/'Tests/AppUITests',module.ROOT/'tools/ui_duration_weights.json')
        groups=module.partition(costs,module.DEFAULT_SHARD_COUNT)
        self.assertEqual(sum(weights[name] for group in groups for name in group),sum(weights.values()))
