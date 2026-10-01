import importlib.util
import pathlib
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('ui_shard',pathlib.Path(__file__).resolve().parents[1]/'run_ui_shard.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class UIShardingTests(unittest.TestCase):
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
