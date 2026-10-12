import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
sharding = module('static_shard_checks', ROOT / 'tools/static_shard_checks.py')
base = module('static_base_checks', ROOT / 'tools/run_static_checks.py')

class StaticShardChecksTests(unittest.TestCase):
    def setUp(self):
        self.identity = {'commit':'a'*40,'head':'a'*40,'tree':'b'*40,'run_id':'1','run_attempt':'1','source_sha256':'c'*64}
        self.discoveries = {'tools':['test_a.One.test_a','test_a.One.test_b','test_b.Two.test_c'],
                            'contracts':['test_c.Three.test_a','test_d.Four.test_b']}
        self.plan = sharding.make_plan(self.identity, self.discoveries, 3)
        self.shards = []
        for index in range(3):
            reports = {}
            for name in sharding.SUITE_NAMES:
                ids = self.plan['suites'][name]['assignments'][index]
                if not ids: reports[name] = None; continue
                report = {'suite':name,'discovery':base.SUITES[name],'discovery_errors':[],
                          'discovered_ids':ids.copy(),'executed_ids':ids.copy(),'tests_run':len(ids),'skipped':[],
                          'process_id':index+10,'duration_seconds':1.0,'discovered_count':len(ids),
                          'executed_count':len(ids),'skip_count':0}
                for key in base.OUTCOMES: report[key] = ids.copy() if key == 'successes' else []
                report['outcome_counts'] = {key:len(report[key]) for key in base.OUTCOMES}
                reports[name] = report
            self.shards.append({'version':1,'identity':copy.deepcopy(self.identity),'plan_sha256':sharding.sha(self.plan),
                                'index':index,'reports':reports,'log_sha256':{n:'d'*64 for n in sharding.SUITE_NAMES}})
    def validate(self, shards=None, plan=None):
        return sharding.aggregate_suite(plan or self.plan, self.shards if shards is None else shards,
                                        'tools', self.identity, base.validate_report, ROOT, 12345)
    def test_dynamic_historical_module_ids_selected_from_full_discovery(self):
        class Historical(unittest.TestCase):
            def test_one(self): pass
        Historical.__module__ = 'not_an_importable_historical_alias'
        test = Historical('test_one')
        selected = base.select_discovered_suite(unittest.TestSuite([test]), [test.id()])
        self.assertEqual(list(base.flatten(selected)), [test])
    def test_missing_and_duplicate_discovered_ids_rejected(self):
        class Fixture(unittest.TestCase):
            def test_one(self): pass
        test = Fixture('test_one')
        with self.assertRaises(ValueError):
            base.select_discovered_suite(unittest.TestSuite([test]), ['absent.Test.test_one'])
        with self.assertRaises(ValueError):
            base.select_discovered_suite(unittest.TestSuite([test, test]), [test.id()])
    def test_complete_union_keeps_original_validator_and_exact_methods(self):
        report = self.validate(); self.assertEqual(report['discovered_ids'],self.discoveries['tools'])
        self.assertEqual(report['tests_run'],3); base.validate_report(report,'tools',ROOT)
    def test_class_methods_remain_together(self):
        rows = sharding.assignment(self.discoveries['tools'],3)
        self.assertTrue(any(row == self.discoveries['tools'][:2] for row in rows))
    def test_round_robin_is_deterministic(self):
        self.assertEqual(self.plan,sharding.make_plan(self.identity,self.discoveries,3))
    def test_missing_shard_rejected(self):
        with self.assertRaises(ValueError): self.validate(self.shards[:-1])
    def test_duplicate_shard_rejected(self):
        with self.assertRaises(ValueError): self.validate([self.shards[0],self.shards[0],self.shards[2]])
    def test_cross_source_run_attempt_rejected(self):
        for key in self.identity:
            shards = copy.deepcopy(self.shards); shards[0]['identity'][key] += '1'
            with self.subTest(key=key), self.assertRaises(ValueError): self.validate(shards)
    def test_wrong_plan_digest_rejected(self):
        shards=copy.deepcopy(self.shards);shards[0]['plan_sha256']='0'*64
        with self.assertRaises(ValueError):self.validate(shards)
    def test_test_omission_or_duplicate_rejected(self):
        for change in ['remove','duplicate']:
            shards=copy.deepcopy(self.shards);row=shards[0]['reports']['tools']['discovered_ids']
            row.pop() if change=='remove' else row.append(row[0])
            with self.subTest(change=change),self.assertRaises(ValueError):self.validate(shards)
    def test_fabricated_empty_shard_rejected(self):
        shards=copy.deepcopy(self.shards);shards[2]['reports']['tools']=copy.deepcopy(shards[0]['reports']['tools'])
        with self.assertRaises(ValueError):self.validate(shards)
    def test_moved_class_assignment_rejected(self):
        plan=copy.deepcopy(self.plan); plan['suites']['tools']['assignments'][2]=plan['suites']['tools']['assignments'][0];plan['suites']['tools']['assignments'][0]=[]
        with self.assertRaises(ValueError):self.validate(plan=plan)
    def test_fresh_discovery_difference_rejected(self):
        discoveries=copy.deepcopy(self.discoveries);discoveries['tools'].append('test_e.New.test_new')
        with self.assertRaises(ValueError):sharding.validate_plan(self.plan,self.identity,discoveries)
    def test_full_suite_is_not_replaced_by_subset(self):
        discoveries=copy.deepcopy(self.discoveries);discoveries.pop('contracts')
        with self.assertRaises(ValueError):sharding.make_plan(self.identity,discoveries)
    def test_failure_error_and_unexpected_success_rejected(self):
        for key in ['failures','errors','unexpected_successes']:
            shards=copy.deepcopy(self.shards);r=shards[0]['reports']['tools'];r[key]=[r['successes'].pop()];r['outcome_counts']={k:len(r[k]) for k in base.OUTCOMES}
            with self.subTest(key=key),self.assertRaises(ValueError):self.validate(shards)
    def test_incomplete_execution_rejected(self):
        shards=copy.deepcopy(self.shards);shards[0]['reports']['tools']['executed_ids'].pop()
        with self.assertRaises(ValueError):self.validate(shards)
    def test_unapproved_skip_rejected(self):
        shards=copy.deepcopy(self.shards);r=shards[0]['reports']['tools'];identifier=r['successes'].pop()
        r['skipped']=[{'id':identifier,'reason':'too slow','affected_ids':[identifier]}];r['skip_count']=1;r['outcome_counts']={k:len(r[k]) for k in base.OUTCOMES}
        with self.assertRaises(ValueError):self.validate(shards)
    def test_invalid_index_and_bool_count_rejected(self):
        for count in [True,0,33]:
            with self.subTest(count=count),self.assertRaises(ValueError):sharding.make_plan(self.identity,self.discoveries,count)
        shards=copy.deepcopy(self.shards);shards[0]['index']=True
        with self.assertRaises(ValueError):self.validate(shards)
    def test_missing_log_binding_rejected(self):
        shards=copy.deepcopy(self.shards);shards[0]['log_sha256']['tools']=''
        with self.assertRaises(ValueError):self.validate(shards)
    def test_duplicate_full_inventory_rejected(self):
        discoveries=copy.deepcopy(self.discoveries);discoveries['tools'].append(discoveries['tools'][0])
        with self.assertRaises(ValueError):sharding.make_plan(self.identity,discoveries)


# Synthetic authenticated-context fixtures only. Real current repository
# discoveries are checked separately; these never substitute for native tests.
def synthetic_historical_identity_fixture():
    from contextlib import contextmanager
    import hashlib, sys, tempfile, types
    from unittest import mock
    @contextmanager
    def fixture():
        with tempfile.TemporaryDirectory(prefix='static-current-') as current, tempfile.TemporaryDirectory(prefix='static-historical-') as historical:
            root=Path(current); target=Path(historical); relative='tools/tests/history.py'
            helper=root/'tools/club_customer_directory_admission.py';helper.parent.mkdir(parents=True);helper.write_text('# Synthetic admission fixture only\n')
            source=b'import unittest\nclass ArchivedTests(unittest.TestCase):\n def test_original(self): self.assertTrue(True)\n'
            path=target/relative;path.parent.mkdir(parents=True);path.write_bytes(source);digest=hashlib.sha256(source).hexdigest()
            namespace='_club_e2b_'+hashlib.sha256(str(target).encode()).hexdigest()[:24];name=namespace+'.tools.tests.history';module=types.ModuleType(name);module.__file__=str(path);exec(compile(source,str(path),'exec'),module.__dict__)
            checks=[]
            def verify():
                checks.append('verified')
                if path.read_bytes()!=source:raise ValueError('Changed exact synthetic historical source')
            context=types.SimpleNamespace(root=target,file_sha256={relative:digest},_club_e2b_guarded=True,verify=verify)
            admission=types.ModuleType('tools.club_customer_directory_admission');admission.__file__=str(helper);admission._CLUB_CURRENT_ROOT=root;admission._club_context_cache=context;admission._CLUB_E2B_SHA256={relative:digest}
            package=types.ModuleType('tools');package.__path__=[];package.club_customer_directory_admission=admission
            with mock.patch.dict(sys.modules,{'tools':package,'tools.club_customer_directory_admission':admission,name:module}):
                yield root,module,module.ArchivedTests('test_original'),context,admission,checks
    return fixture()


class StaticHistoricalTransportIdentityTests(unittest.TestCase):
    def test_original_instance_and_random_id_are_not_rewritten(self):
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            original=test.id();module_name=type(test).__module__
            rows=base.discovery_identities([test],root);stable=rows[0]['transport_id']
            selected=base.select_discovered_suite(unittest.TestSuite([test]),[stable],root)
            self.assertIs(list(base.flatten(selected))[0],test)
            self.assertEqual(test.id(),original);self.assertEqual(type(test).__module__,module_name)
            self.assertEqual(rows[0]['observed_id'],original);self.assertNotEqual(stable,original)
            self.assertIn(context.file_sha256['tools/tests/history.py'],stable);self.assertGreaterEqual(len(checks),4)

    def test_two_independent_interpreters_with_different_temp_roots_match(self):
        import json,subprocess,sys
        script="""import importlib.util,json
from pathlib import Path
p=Path(__import__('sys').argv[1]);spec=importlib.util.spec_from_file_location('identity_fixture_module',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with m.synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
 row=m.base.discovery_identities([test],root)[0];print(json.dumps(row))
"""
        values=[json.loads(subprocess.check_output([sys.executable,'-B','-c',script,str(Path(__file__).resolve())])) for _ in range(2)]
        self.assertNotEqual(values[0]['observed_id'],values[1]['observed_id'])
        self.assertEqual(values[0]['transport_id'],values[1]['transport_id'])
        self.assertEqual(values[0]['historical_source_sha256'],values[1]['historical_source_sha256'])

    def test_unknown_context_namespace_module_file_and_class_fail_closed(self):
        from unittest import mock
        for kind in ['missing-context','namespace','module-file','class','different-source-map']:
            with self.subTest(kind=kind),synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
                if kind=='missing-context':admission._club_context_cache=None
                elif kind=='namespace':type(test).__module__='_club_e2b_'+'0'*24+'.tools.tests.history'
                elif kind=='module-file':module.__file__=str(Path(module.__file__).parent/'other.py')
                elif kind=='class':module.ArchivedTests=type('ArchivedTests',(unittest.TestCase,),{})
                else:admission._CLUB_E2B_SHA256={}
                with self.assertRaises(ValueError):base.discovery_identities([test],root)

    def test_mutated_historical_bytes_cannot_keep_a_stable_identity(self):
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            base.discovery_identities([test],root);Path(module.__file__).write_bytes(b'changed')
            with self.assertRaises(ValueError):base.discovery_identities([test],root)

    def test_duplicate_and_forged_transport_id_rejected(self):
        from unittest import mock
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            with self.assertRaises(ValueError):base.discovery_identities([test,test],root)
            stable=base.discovery_identities([test],root)[0]['transport_id']
            with mock.patch.object(test,'id',return_value=stable):
                with self.assertRaises(ValueError):base.discovery_identities([test],root)
            with self.assertRaises(ValueError):base.select_discovered_suite(unittest.TestSuite([test]),[stable,stable],root)

    def test_real_unittest_execution_keeps_raw_logs_and_original_report_schema(self):
        from contextlib import redirect_stderr
        import io
        from unittest import mock
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            raw=test.id();stable=base.discovery_identities([test],root)[0]['transport_id'];logs=io.StringIO()
            with mock.patch.object(base,'discover_original_suite',return_value=unittest.TestSuite([test])),redirect_stderr(logs):
                report=base.suite_report('tools',root,[stable])
            base.validate_report(report,'tools',root)
            self.assertEqual(report['discovered_ids'],[stable]);self.assertEqual(report['successes'],[stable]);self.assertEqual(report['tests_run'],1)
            self.assertIn('START '+raw,logs.getvalue());self.assertIn('STATIC_TEST_IDENTITY ',logs.getvalue())
            self.assertIn(raw,logs.getvalue());self.assertIn(stable,logs.getvalue());self.assertEqual(test.id(),raw)


    def raw_execution(self, root, test):
        from contextlib import redirect_stderr
        import io
        from unittest import mock
        stable = base.discovery_identities([test], root)[0]['transport_id']
        evidence, logs = {}, io.StringIO()
        with mock.patch.object(base, 'discover_original_suite', return_value=unittest.TestSuite([test])), redirect_stderr(logs):
            report = base.suite_report('tools', root, [stable], evidence=evidence)
        return report, evidence, logs.getvalue().encode()

    def test_original_raw_report_is_preserved_and_exactly_projects(self):
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            original = test.id()
            report, evidence, log = self.raw_execution(root, test)
            self.assertEqual(evidence['raw_report']['discovered_ids'], [original])
            self.assertEqual(evidence['raw_report']['executed_ids'], [original])
            self.assertEqual(evidence['raw_report']['successes'], [original])
            self.assertEqual(evidence['raw_report']['duration_seconds'], report['duration_seconds'])
            self.assertEqual(evidence['raw_report']['process_id'], report['process_id'])
            self.assertEqual(base.validate_identity_report(report, evidence, root), evidence)
            self.assertEqual(base.validate_log_identity_report(log, report, root), evidence)
            self.assertEqual(test.id(), original)

    def test_raw_report_and_mapping_tampering_fail_closed(self):
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            report, evidence, log = self.raw_execution(root, test)
            for change in ['missing-map','duplicate-map','source-hash','method','raw-success','raw-duration','raw-id','extra-key','transport-id']:
                payload = copy.deepcopy(evidence)
                if change == 'missing-map': payload['identities'].clear()
                elif change == 'duplicate-map': payload['identities'].append(payload['identities'][0])
                elif change == 'source-hash': payload['identities'][0]['historical_source_sha256'] = '0'*64
                elif change == 'method': payload['identities'][0]['transport_id'] += '_other'
                elif change == 'raw-success': payload['raw_report']['successes'].clear()
                elif change == 'raw-duration': payload['raw_report']['duration_seconds'] += 1
                elif change == 'raw-id': payload['raw_report']['discovered_ids'][0] += '_other'
                elif change == 'extra-key': payload['identities'][0]['extra'] = True
                else: payload['identities'][0]['observed_id'] = payload['identities'][0]['transport_id']
                with self.subTest(change=change), self.assertRaises(ValueError):
                    base.validate_identity_report(report, payload, root)

    def test_hash_bound_raw_log_requires_exactly_one_unique_json_record(self):
        with synthetic_historical_identity_fixture() as (root,module,test,context,admission,checks):
            report, evidence, log = self.raw_execution(root, test)
            record = b'STATIC_RAW_REPORT '+base.encode(evidence).encode()+b'\n'
            for broken in [b'', log+record, record.replace(b'{',b'{"identities":[],',1), record.replace(b'raw_report',b'other_report',1)]:
                with self.subTest(log=broken[:40]), self.assertRaises(ValueError):
                    base.validate_log_identity_report(broken, report, root)

if __name__=='__main__':unittest.main()
