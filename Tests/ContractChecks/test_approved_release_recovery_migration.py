"""Verify an existing two-launch test was reorganized, not weakened or counted as new coverage."""
from pathlib import Path
import hashlib,importlib.util,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class ReleaseRecoveryMigrationContracts(unittest.TestCase):
 def setUp(self):self.meta=json.loads((ROOT/'Tests/AppUITests/ApprovedReleaseRecoveryMigration.json').read_text())
 def body(self,row):
  s=(ROOT/row['file']).read_text();method=row['method'].split('.')[1]
  return re.search(r'    func '+method+r'\(\) throws \{\n(.*)\n    \}\n\}',s,re.S)[1]
 def test_original_combined_body_reconstructs_byte_for_byte(self):
  first,second=[self.body(row) for row in self.meta['new_methods']]
  first=first.replace('        let app = launch(','        var app = launch(',1).replace('        let probe = try inspect(app);','        var probe = try inspect(app);',1)
  self.assertTrue(first.endswith('        app.terminate();'));first=first.removesuffix('        app.terminate();')
  second=second.replace('        let app = launch(["--project-release-receipt-write-failure"]); submitAndRead(in: app)','        app.terminate(); app = launch(["--project-release-receipt-write-failure"]); submitAndRead(in: app)',1).replace('        let probe = try inspect(app);','        probe = try inspect(app);',1)
  self.assertEqual(hashlib.sha256((first+second).encode()).hexdigest(),self.meta['old_body_sha256'])
 def test_helpers_and_new_method_bodies_match_recorded_exact_hashes(self):
  for row in self.meta['new_methods']:
   source=(ROOT/row['file']).read_text();helper=source[source.index('    private var app:'):source.index('    // Historical combined')]
   self.assertEqual(hashlib.sha256(helper.encode()).hexdigest(),self.meta['helper_bytes_sha256'])
   self.assertEqual(hashlib.sha256(self.body(row).encode()).hexdigest(),row['body_sha256'])
   self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),row['file_sha256'])
 def test_each_new_case_is_discovered_once_and_old_combined_method_is_absent(self):
  spec=importlib.util.spec_from_file_location('release_migration_runner',ROOT/'tools/run_ui_shard.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  counts=module.discover(ROOT/'Tests/AppUITests')
  old=self.meta['old_method'].split('.')[1]
  self.assertFalse(any(re.search(r'\bfunc\s+'+old+r'\s*\(',p.read_text()) for p in (ROOT/'Tests/AppUITests').glob('*.swift')))
  for row in self.meta['new_methods']:
   cls,method=row['method'].split('.');self.assertEqual(counts[cls],1)
   self.assertEqual(sum(len(re.findall(r'\bfunc\s+'+method+r'\s*\(',p.read_text())) for p in (ROOT/'Tests/AppUITests').glob('*.swift')),1)
 def test_complete_budget_increases_without_changing_runner_limits_or_coverage(self):
  self.assertEqual(self.meta['old_complete_unmeasured_seconds'],1200)
  self.assertEqual([x['complete_unmeasured_seconds'] for x in self.meta['new_methods']],[900,900])
  self.assertEqual(self.meta['new_coverage_count'],0);self.assertEqual(self.meta['discovered_method_delta'],1)
  for row in self.meta['new_methods']:
   source=(ROOT/row['file']).read_text();self.assertIn('UNMEASURED complete method estimate: 900 seconds.',source)
   self.assertLessEqual(row['complete_unmeasured_seconds']+300,1800)
if __name__=='__main__':unittest.main()
