"""Raw state acceptance and fail-closed history checks; never Swift execution."""
import hashlib
import json
from itertools import product
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from tools.tests import creator_shelf_state_history as state
from tools.tests import creator_shelf_refresh_history as refresh

ROOT = Path(__file__).resolve().parents[2]
CATALOG = 'Resources/Localizable.xcstrings'
CURRENT_SHA = {'App/TemplateAuthoringMineView.swift': '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f',
 'Core/TemplateAuthoringShelf.swift': 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a',
 'Resources/Localizable.xcstrings': '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift': '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py': 'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8',
 'Tests/ContractChecks/test_template_shelf_state_projection.py': '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift': '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': 'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87'}
LABELS = {'templateShelfState.market.feedback': {'en': 'Marketplace feedback',
                                        'zh-Hans': '广场反馈'},
 'templateShelfState.market.listed': {'en': 'Listed in marketplace',
                                      'zh-Hans': '广场已上架'},
 'templateShelfState.market.notSubmitted': {'en': 'Not submitted to '
                                                  'marketplace',
                                            'zh-Hans': '未提交广场'},
 'templateShelfState.market.rejected': {'en': 'Marketplace resubmission '
                                              'required',
                                        'zh-Hans': '广场需重新提交'},
 'templateShelfState.market.reviewing': {'en': 'Marketplace review pending',
                                         'zh-Hans': '广场审核中'},
 'templateShelfState.market.title': {'en': 'Template marketplace',
                                     'zh-Hans': '模板广场'},
 'templateShelfState.market.unknown': {'en': 'Marketplace status unknown',
                                       'zh-Hans': '广场状态待确认'},
 'templateShelfState.market.unlisted': {'en': 'Unlisted from marketplace',
                                        'zh-Hans': '广场已下架'},
 'templateShelfState.personal.approved': {'en': 'Personal review approved',
                                          'zh-Hans': '个人审核通过'},
 'templateShelfState.personal.draft': {'en': 'Draft', 'zh-Hans': '草稿'},
 'templateShelfState.personal.rejected': {'en': 'Personal review rejected',
                                          'zh-Hans': '个人审核未通过'},
 'templateShelfState.personal.reviewing': {'en': 'Under personal review',
                                           'zh-Hans': '个人审核中'},
 'templateShelfState.personal.title': {'en': 'Personal review',
                                       'zh-Hans': '个人审核'},
 'templateShelfState.personal.unknown': {'en': 'Personal review status unknown',
                                         'zh-Hans': '状态待确认'}}
LEGACY_SHA = {'tools/tests/creator_shelf_refresh_history.py': 'a0ccdaf793079c5dd59b5931d8d734f1d16856bbba7f8251125f1bc32b3c5c25',
 'tools/tests/test_creator_pending_synthetic_storage_history.py': '608cef3c34c5b8590f93de52e787d9ac1e08aa1d6b0aa03e478f89ca31c1d85d',
 'tools/tests/test_creator_shelf_refresh_history.py': 'be30636bb1fde4a4c2d3f03078da7f80b49ab971fded3ededb5f6b80a93619e9'}
LEGACY_DELTAS = {'tools/tests/creator_shelf_refresh_history.py': ((6505,
                                                   b'def historical_pre_shelf_refresh_mine_bytes('
                                                   b'*, root=ROOT):\n    root = Path(root)\n    fro'
                                                   b'm tools.tests.creator_shelf_state_history im'
                                                   b'port historical_pre_shelf_state_sources\n    '
                                                   b'sources = historical_pre_shelf_state_sources'
                                                   b'(root=root)\n    identities = {name: _digest('
                                                   b'raw) for name, raw in sources.items()}\n    o'
                                                   b'riginal = all(identities[name] == pair[0] fo'
                                                   b'r name, pair in SOURCE_SHA256.items())\n',
                                                   b'def historical_pre_shelf_refresh_mine_bytes('
                                                   b'*, root=ROOT):\n    root = Path(root)\n    sou'
                                                   b'rces = {}\n    for name in SOURCE_SHA256:\n   '
                                                   b'     try:\n            sources[name] = (root '
                                                   b'/ name).read_bytes()\n        except OSError '
                                                   b"as error:\n            raise ValueError('Miss"
                                                   b'ing or unreadable shelf refresh history inpu'
                                                   b"t: ' + name) from error\n    identities = {na"
                                                   b'me: _digest(raw) for name, raw in sources.it'
                                                   b'ems()}\n    original = all(identities[name] ='
                                                   b'= pair[0] for name, pair in SOURCE_SHA256.it'
                                                   b'ems())\n'),),
 'tools/tests/test_creator_pending_synthetic_storage_history.py': ((11913,
                                                                    b"            if row['path'] ="
                                                                    b"= 'App/TemplateAuthoringMine"
                                                                    b"View.swift':\n               "
                                                                    b' from tools.tests.creator_sh'
                                                                    b'elf_refresh_history import S'
                                                                    b'OURCE_SHA256\n               '
                                                                    b' from tools.tests.creator_sh'
                                                                    b'elf_state_history import STA'
                                                                    b'TE_EXTRA_INPUTS\n            '
                                                                    b'    for name in (*SOURCE_SHA'
                                                                    b'256, *STATE_EXTRA_INPUTS):\n '
                                                                    b'                   path = se'
                                                                    b'lf.root / name\n             '
                                                                    b'       path.parent.mkdir(par'
                                                                    b'ents=True, exist_ok=True)\n',
                                                                    b"            if row['path'] ="
                                                                    b"= 'App/TemplateAuthoringMine"
                                                                    b"View.swift':\n               "
                                                                    b' from tools.tests.creator_sh'
                                                                    b'elf_refresh_history import S'
                                                                    b'OURCE_SHA256\n               '
                                                                    b' for name in SOURCE_SHA256:\n'
                                                                    b'                    path = s'
                                                                    b'elf.root / name\n            '
                                                                    b'        path.parent.mkdir(pa'
                                                                    b'rents=True, exist_ok=Tru'
                                                                    b'e)\n'),),
 'tools/tests/test_creator_shelf_refresh_history.py': ((51403,
                                                        b'        self.addCleanup(self.directory.c'
                                                        b'leanup)\n        self.root = Path(self.di'
                                                        b'rectory.name)\n        from tools.tests.c'
                                                        b'reator_shelf_state_history import histor'
                                                        b'ical_pre_shelf_state_sources\n        sel'
                                                        b'f.post = historical_pre_shelf_state_sour'
                                                        b'ces(root=ROOT)\n        self.pre = {}'
                                                        b'\n        for name, raw in self.post.item'
                                                        b's():\n',
                                                        b'        self.addCleanup(self.directory.c'
                                                        b'leanup)\n        self.root = Path(self.di'
                                                        b'rectory.name)\n        self.post = {name:'
                                                        b' (ROOT / name).read_bytes() for name in '
                                                        b'history.SOURCE_SHA256}\n        self.pre '
                                                        b'= {}\n        for name, raw in self.post.'
                                                        b'items():\n'),
                                                       (57942,
                                                        b'        self.assertEqual(digest(restored'
                                                        b'), STORAGE_OLD_SHA256)\n        raw = (RO'
                                                        b"OT / 'tools/tests/test_creator_pending_s"
                                                        b"ynthetic_storage_history.py').read_bytes"
                                                        b"()\n        raw = raw.replace(b'for name "
                                                        b'in (*SOURCE_SHA256, *STATE_EXTRA_INPUTS)'
                                                        b":', b'for name in SOURCE_SHA256:', 1)\n  "
                                                        b"      raw = raw.replace(b'              "
                                                        b'  from tools.tests.creator_shelf_state_h'
                                                        b"istory import STATE_EXTRA_INPUTS\\n', b''"
                                                        b', 1)\n        self.assertEqual(raw.count('
                                                        b'NEW_STORAGE_TEST_REGION), 1)\n        res'
                                                        b'tored = raw.replace(NEW_STORAGE_TEST_REG'
                                                        b'ION, OLD_STORAGE_TEST_REGION, 1)\n',
                                                        b'        self.assertEqual(digest(restored'
                                                        b'), STORAGE_OLD_SHA256)\n        raw = (RO'
                                                        b"OT / 'tools/tests/test_creator_pending_s"
                                                        b"ynthetic_storage_history.py').read_bytes"
                                                        b'()\n        self.assertEqual(raw.count(NE'
                                                        b'W_STORAGE_TEST_REGION), 1)\n        resto'
                                                        b'red = raw.replace(NEW_STORAGE_TEST_REGIO'
                                                        b'N, OLD_STORAGE_TEST_REGION, 1)\n'))}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def assert_current_raw(root):
    for name, expected in CURRENT_SHA.items():
        if digest((root / name).read_bytes()) != expected:
            raise ValueError('Changed raw state input: ' + name)
    data = json.loads((root / CATALOG).read_bytes())
    keys = {key for key in data['strings'] if key.startswith('templateShelfState.')}
    if keys != set(LABELS):
        raise ValueError('Unexpected state catalog keys')
    for key, labels in LABELS.items():
        expected = {'extractionState': 'manual', 'localizations': {
            locale: {'stringUnit': {'state': 'translated', 'value': value}}
            for locale, value in labels.items()}}
        if data['strings'][key] != expected:
            raise ValueError('Changed bilingual catalog entry')


class CreatorShelfStateHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.current = {name: (ROOT / name).read_bytes() for name in state.SOURCE_SHA256}
        self.legacy = dict(self.current)
        for name in state.INVERSE_DELTAS:
            self.legacy[name] = state.restore_state_bytes(name, self.current[name])
        for name in state.STATE_EXTRA_INPUTS[1:]:
            del self.legacy[name]
        self.install(self.current)

    def install(self, sources):
        for name in state.SOURCE_SHA256:
            path = self.root / name
            if name not in sources:
                if path.exists(): path.unlink()
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(sources[name])

    def project(self):
        return refresh.historical_pre_shelf_refresh_mine_bytes(root=self.root)

    def rejects(self, sources):
        self.install(sources)
        with self.assertRaises(ValueError): self.project()

    def test_raw_current_acceptance_independent_of_all_inverses(self):
        assert_current_raw(ROOT)
        with patch.object(state, 'restore_state_bytes', side_effect=AssertionError('inverse forbidden')):
            with patch.object(state, 'historical_pre_shelf_state_sources', side_effect=AssertionError('inverse forbidden')):
                with patch.object(refresh, '_restore_mine_bytes', side_effect=AssertionError('inverse forbidden')):
                    assert_current_raw(ROOT)

    def test_complete_current_and_legacy_groups_restore_original_mine(self):
        from tools.tests.test_creator_shelf_refresh_history import TEST_INVERSE_DELTAS
        prior = dict(self.legacy)
        for name, deltas in TEST_INVERSE_DELTAS.items():
            raw = prior[name]
            for offset, after, before in reversed(deltas):
                self.assertEqual(raw.count(after), 1)
                self.assertEqual(raw[offset:offset+len(after)], after)
                raw = raw[:offset]+before+raw[offset+len(after):]
            self.assertEqual(digest(raw), refresh.SOURCE_SHA256[name][0])
            prior[name] = raw
        for sources in (self.current, self.legacy, prior,
                        {name:self.legacy[name] for name in state.REFRESH_INPUTS}):
            self.install(sources)
            self.assertEqual(digest(self.project()), refresh.SOURCE_SHA256[refresh.MINE_SOURCE][0])
            self.assertEqual(digest(self.project()), refresh.SOURCE_SHA256[refresh.MINE_SOURCE][0])
            for name, raw in sources.items(): self.assertEqual((self.root/name).read_bytes(),raw)
        self.assertEqual(len(self.current[CATALOG])-len(self.legacy[CATALOG]),5730)
        for name in state.INVERSE_DELTAS:
            self.assertEqual(digest(self.legacy[name]),state.SOURCE_SHA256[name][0])

    def test_all_state_mixtures_rejected(self):
        names=(state.REFRESH_INPUTS[0],state.REFRESH_INPUTS[1],*state.STATE_EXTRA_INPUTS)
        for bits in product((False,True),repeat=5):
            if all(bits) or not any(bits): continue
            sources=dict(self.legacy)
            for name,current in zip(names,bits):
                if current: sources[name]=self.current[name]
                elif name not in self.legacy: sources.pop(name,None)
            self.rejects(sources)

    def test_each_current_input_missing_or_raw_mutated_rejected(self):
        for name,raw in self.current.items():
            sources=dict(self.current);del sources[name];self.rejects(sources)
            for changed in (raw+b'\n',raw[:-1],b'\xef\xbb\xbf'+raw,raw.replace(b'\n',b'\r\n'),bytes([raw[0]^1])+raw[1:]):
                with self.subTest(name=name):self.rejects({**self.current,name:changed})

    def test_legacy_catalog_and_test_collisions_rejected(self):
        raw=self.legacy[CATALOG]
        for changed in (raw+b'\n',raw[:-1],b'\xef\xbb\xbf'+raw,raw.replace(b'\n',b'\r\n'),bytes([raw[0]^1])+raw[1:]):
            self.rejects({**self.legacy,CATALOG:changed})
        for name in state.STATE_EXTRA_INPUTS[1:]:
            for raw in (b'',b'unknown',self.current[name]):self.rejects({**self.legacy,name:raw})
        for names in (state.STATE_EXTRA_INPUTS, state.STATE_EXTRA_INPUTS[1:]):
            sources=dict(self.current)
            for name in names:del sources[name]
            self.rejects(sources)

    def test_catalog_semantically_equivalent_or_unknown_changes_rejected(self):
        for sources in (self.current,self.legacy):
            data=json.loads(sources[CATALOG]);compact=json.dumps(data,ensure_ascii=False).encode()
            self.rejects({**sources,CATALOG:compact})
            data['strings']['unexpected.new.key']={}
            self.rejects({**sources,CATALOG:json.dumps(data,ensure_ascii=False,indent=2).encode()})
            reordered=json.dumps(dict(reversed(list(data.items()))),ensure_ascii=False).encode()
            self.rejects({**sources,CATALOG:reordered})

    def test_all_finite_hunks_missing_repeated_moved_rejected(self):
        for name,deltas in state.INVERSE_DELTAS.items():
            raw=self.current[name]
            for offset,after,before in deltas:
                missing=raw[:offset]+raw[offset+len(after):]
                for changed in (missing,raw[:offset]+after+raw[offset:],after+missing):
                    self.rejects({**self.current,name:changed})

    def test_inverse_tables_cannot_hide_moved_or_changed_regions(self):
        for name,deltas in state.INVERSE_DELTAS.items():
            offset,after,before=deltas[0]
            for bad in (((offset+1,after,before),)+deltas[1:],deltas+(deltas[-1],),((offset,after,before+b'x'),)+deltas[1:]):
                with patch.dict(state.INVERSE_DELTAS,{name:bad}):
                    with self.assertRaises(ValueError):state.restore_state_bytes(name,self.current[name])

    def test_every_call_revalidates_all_raw_inputs(self):
        self.project()
        for name,raw in self.current.items():
            self.rejects({**self.current,name:raw+b'\n'})
            self.install(self.current);self.project()

    def test_three_legacy_modules_restore_byte_exactly(self):
        for name,deltas in LEGACY_DELTAS.items():
            raw=(ROOT/name).read_bytes()
            for offset,after,before in reversed(deltas):
                self.assertEqual(raw.count(after),1)
                self.assertEqual(raw[offset:offset+len(after)],after)
                raw=raw[:offset]+before+raw[offset+len(after):]
            self.assertEqual(digest(raw),LEGACY_SHA[name])

    def test_current_central_contract_and_all_support_inputs_fail_closed(self):
        from tools import run138_current_source_projection as projection
        from tools import run138_editor_readiness as planning
        projection.validate_feature_batch_sources(ROOT)
        contract=planning.contract(ROOT)
        from Tests.ContractChecks import test_profile_read_failure_remote_admission as admission
        current_contract=contract
        contract=admission._club_directory_contract(json.loads(json.dumps(contract)),ROOT)
        self.assertEqual(len(contract['feature_batch_support_sha256']),502)
        contract=current_contract
        original=Path.read_bytes
        # Read actual inputs once; mutations are isolated read substitutions,
        # never copies of the repository or historical acceptance expectations.
        sources={str(ROOT/name):(ROOT/name).read_bytes() for name in
                 (*contract['feature_batch_sources'],*contract['feature_batch_support_sha256'],
                  'tools/run138_editor_readiness_contract.json')}
        def read(path):
            key=str(path)
            return sources[key] if key in sources else original(path)
        with patch.object(Path,'read_bytes',read):
            # The unchanged contract was authenticated above. Reuse only that
            # immutable mapping while exercising all raw support-byte guards.
            with patch.object(planning,'contract',return_value=contract):
                for name in contract['feature_batch_support_sha256']:
                    key=str(ROOT/name);raw=sources[key]
                    try:
                        sources[key]=raw+b'\n'
                        with self.subTest(name=name):
                            with self.assertRaises(ValueError):projection.validate_feature_batch_sources(ROOT)
                    finally:sources[key]=raw
            key=str(ROOT/'tools/run138_editor_readiness_contract.json');raw=sources[key]
            for changed in (raw+b'\n',raw.replace(b'"feature_batch_support_sha256"',b'"feature_batch_support_sha257"',1),
                            raw.replace(state.SOURCE_SHA256[CATALOG][1].encode(),state.SOURCE_SHA256[CATALOG][0].encode(),1)):
                sources[key]=changed
                with self.assertRaises(ValueError):projection.validate_feature_batch_sources(ROOT)
            sources[key]=raw
            old=raw.replace(state.SOURCE_SHA256[CATALOG][1].encode(),state.SOURCE_SHA256[CATALOG][0].encode(),1)
            sources[key]=old
            with patch.object(planning,'CONTRACT_SHA256',digest(old)):
                with self.assertRaisesRegex(ValueError,'Current feature-batch input changed: Resources/Localizable'):
                    projection.validate_feature_batch_sources(ROOT)
            sources[key]=raw
            with patch.object(planning,'CONTRACT_SHA256','0'*64):
                with self.assertRaises(ValueError):projection.validate_feature_batch_sources(ROOT)
        projection.validate_feature_batch_sources(ROOT)

    def test_central_changes_are_only_two_contract_values_and_runner_pin(self):
        name='tools/run138_editor_readiness_contract.json';raw=(ROOT/name).read_bytes()
        current_raw=raw
        from Tests.ContractChecks import test_profile_read_failure_remote_admission as admission
        admission._combined_profile_contract(raw,ROOT)
        raw=(json.dumps(admission._merchant_business_compile_contract(json.loads(raw),ROOT),indent=2,ensure_ascii=False)+'\n').encode()
        current=state.SOURCE_SHA256[CATALOG][1].encode();old=state.SOURCE_SHA256[CATALOG][0].encode()
        module='Tests/ContractChecks/test_profile_read_failure_remote_admission.py'
        module_sha=admission.MERCHANT_BUSINESS_PRE_ADMISSION_SHA256.encode()
        self.assertEqual(raw.count(current),1)
        self.assertEqual(raw.count(module_sha),1)
        legacy=raw.replace(current,old,1).replace(module_sha,b'd1d7ad397a76f668f47bcc4243c23a397d560e90220b01bd99dd91a85bfe3163',1)
        self.assertEqual(len(raw),len(legacy))
        self.assertEqual(digest(legacy),'519006c2f95083423c186d289b8b2a1b6ef9c6327b5fd461718548b8e0fc40ce')
        script=(ROOT/'tools/run138_editor_readiness.py').read_bytes()
        script=script.replace(digest(current_raw).encode(),digest(raw).encode(),1)
        self.assertEqual(script.count(digest(raw).encode()),1)
        previous=script.replace(digest(raw).encode(),digest(legacy).encode(),1)
        self.assertEqual(len(script),len(previous))
        self.assertEqual(digest(previous),'ab69d29bd7f410619ebd5b7a051bfe98ef239e4532a8466d5607f36ac24f3b08')
        for lineno in (174,243,4028):
            self.assertEqual(raw.splitlines()[lineno-1],legacy.splitlines()[lineno-1])

# CREATOR_FIXED45_PORT_BEGIN
PORT_TEST_PREIMAGE_SHA256 = '9015d703ad6723248aafe5ecf2b858c8eeecce82020aa98fe5387f01a6e6aabe'
PORT_TEST_INVERSE_DELTAS = ((20370,
  b'        projection.validate_feature_batch_sources(ROOT)\n        contract=planning.contract(R'
  b"OOT)\n        self.assertEqual(len(contract['feature_batch_support_sha256']),502)\n        ori"
  b'ginal=Path.read_bytes\n        # Read actual inputs once; mutations are isolated read substit'
  b'utions,\n',
  b'        projection.validate_feature_batch_sources(ROOT)\n        contract=planning.contract(R'
  b"OOT)\n        self.assertEqual(len(contract['feature_batch_support_sha256']),498)\n        ori"
  b'ginal=Path.read_bytes\n        # Read actual inputs once; mutations are isolated read substit'
  b'utions,\n'),
 (22870,
  b'        projection.validate_feature_batch_sources(ROOT)\n\n    def test_central_changes_are_on'
  b"ly_two_contract_values_and_runner_pin(self):\n        name='tools/run138_editor_readiness_con"
  b"tract.json';raw=(ROOT/name).read_bytes()\n        current=state.SOURCE_SHA256[CATALOG][1].enc"
  b"ode();old=state.SOURCE_SHA256[CATALOG][0].encode()\n        module='Tests/ContractChecks/test"
  b"_profile_read_failure_remote_admission.py'\n        module_sha=digest((ROOT/module).read_byte"
  b's()).encode()\n        self.assertEqual(raw.count(current),1)\n        self.assertEqual(raw.co'
  b"unt(module_sha),1)\n        legacy=raw.replace(current,old,1).replace(module_sha,b'd1d7ad397a"
  b"76f668f47bcc4243c23a397d560e90220b01bd99dd91a85bfe3163',1)\n        self.assertEqual(len(raw)"
  b",len(legacy))\n        self.assertEqual(digest(legacy),'519006c2f95083423c186d289b8b2a1b6ef9c"
  b"6327b5fd461718548b8e0fc40ce')\n        script=(ROOT/'tools/run138_editor_readiness.py').read_"
  b'bytes()\n        self.assertEqual(script.count(digest(raw).encode()),1)\n        previous=scri'
  b'pt.replace(digest(raw).encode(),digest(legacy).encode(),1)\n        self.assertEqual(len(scri'
  b"pt),len(previous))\n        self.assertEqual(digest(previous),'ab69d29bd7f410619ebd5b7a051bfe"
  b"98ef239e4532a8466d5607f36ac24f3b08')\n        for lineno in (174,243,4028):\n            self."
  b'assertEqual(raw.splitlines()[lineno-1],legacy.splitlines()[lineno-1])\n',
  b'        projection.validate_feature_batch_sources(ROOT)\n\n    def test_central_changes_are_on'
  b"ly_two_exact_equal_length_substitutions(self):\n        name='tools/run138_editor_readiness_c"
  b"ontract.json';raw=(ROOT/name).read_bytes()\n        current=state.SOURCE_SHA256[CATALOG][1].e"
  b'ncode();old=state.SOURCE_SHA256[CATALOG][0].encode()\n        self.assertEqual(raw.count(curr'
  b'ent),1)\n        legacy=raw.replace(current,old,1)\n        self.assertEqual(len(raw),len(lega'
  b"cy))\n        self.assertEqual(digest(raw),'e2d8d7db380c268271f522f1189c3f988299ff723af53b400"
  b"51bee69b5f03881')\n        self.assertEqual(digest(legacy),'11cc2e20ce328dcba2fcfbcb4425bf581"
  b"908038c71d4f4c7eee15c1bbab1b2b6')\n        script=(ROOT/'tools/run138_editor_readiness.py').r"
  b'ead_bytes()\n        self.assertEqual(script.count(digest(raw).encode()),1)\n        previous='
  b'script.replace(digest(raw).encode(),digest(legacy).encode(),1)\n        self.assertEqual(len('
  b"script),len(previous))\n        self.assertEqual(digest(previous),'cafa9858b24a18f3827ce56787"
  b"01b1e32cf533e66d51dc43788b15a74d60a79f')\n        for lineno in (174,243,4028):\n            s"
  b'elf.assertEqual(raw.splitlines()[lineno-1],legacy.splitlines()[lineno-1])\n'))

class CreatorFixed45TestPreservation(unittest.TestCase):
    def test_original_reviewed_creator_history_test_restores_complete_bytes(self):
        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()
        data=_restore_premerchant_history_test(_restore_preclub_history_test(data))
        first=b'\n# CREATOR_FIXED45_PORT_BEGIN\n';last=b'# CREATOR_FIXED45_PORT_END\n'
        self.assertEqual(data.count(first),1);self.assertEqual(data.count(last),1)
        start=data.index(first);end=data.index(last,start)+len(last)
        data=data[:start]+data[end:]
        for offset,after,before in reversed(PORT_TEST_INVERSE_DELTAS):
            self.assertEqual(data.count(after),1)
            self.assertEqual(data[offset:offset+len(after)],after)
            data=data[:offset]+before+data[offset+len(after):]
        self.assertEqual(digest(data),PORT_TEST_PREIMAGE_SHA256)
# CREATOR_FIXED45_PORT_END

# MERCHANT_COMPILE_HISTORY_BEGIN
MERCHANT_HISTORY_PREIMAGE_SHA256 = 'a2df11a0d7d1469fac4904f40e3ac4464f013a8776373969a9b5e5703ad8ac10'
MERCHANT_HISTORY_INVERSE_HUNKS = [("        name='tools/run138_editor_readiness_contract.json';raw=(ROOT/name).read_bytes()\n"
  '        current_raw=raw\n'
  '        from Tests.ContractChecks import test_profile_read_failure_remote_admission as '
  'admission\n'
  '        admission._combined_profile_contract(raw,ROOT)\n'
  '        '
  "raw=(json.dumps(admission._merchant_business_compile_contract(json.loads(raw),ROOT),indent=2,ensure_ascii=False)+'\\n').encode()\n",
  "        name='tools/run138_editor_readiness_contract.json';raw=(ROOT/name).read_bytes()\n"),
 ('        module_sha=admission.MERCHANT_BUSINESS_PRE_ADMISSION_SHA256.encode()\n',
  '        module_sha=digest((ROOT/module).read_bytes()).encode()\n'),
 ("        script=(ROOT/'tools/run138_editor_readiness.py').read_bytes()\n"
  '        script=script.replace(digest(current_raw).encode(),digest(raw).encode(),1)\n',
  "        script=(ROOT/'tools/run138_editor_readiness.py').read_bytes()\n"),
 ("        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()\n"
  '        data=_restore_premerchant_history_test(data)\n',
  "        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()\n")]

def _restore_premerchant_history_test(data):
    first=b'\n# MERCHANT_COMPILE_HISTORY_BEGIN\n';last=b'# MERCHANT_COMPILE_HISTORY_END\n'
    if data.count(first)!=1 or data.count(last)!=1:raise ValueError('Unknown merchant history extension')
    start=data.index(first);end=data.index(last,start)+len(last);data=data[:start]+data[end:]
    for after,before in reversed(MERCHANT_HISTORY_INVERSE_HUNKS):
        if data.count(after.encode())!=1:raise ValueError('Unknown merchant history input adaptation')
        data=data.replace(after.encode(),before.encode(),1)
    if digest(data)!=MERCHANT_HISTORY_PREIMAGE_SHA256:raise ValueError('Complete creator13 history test not restored')
    return data
# MERCHANT_COMPILE_HISTORY_END



# CLUB_HISTORY_INPUT_BEGIN
def _restore_preclub_history_test(data):
    from tools import club_customer_directory_admission as club
    return club.restore_creator_history_test(data)
# CLUB_HISTORY_INPUT_END
if __name__ == '__main__':
    unittest.main()
