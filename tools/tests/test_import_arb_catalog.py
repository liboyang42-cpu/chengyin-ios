import importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('importer',pathlib.Path(__file__).parents[1]/'import_arb_catalog.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ImportTests(unittest.TestCase):
    def test_literal_pair_remains_review_candidate(self):
        catalog,review=module.convert({'ok':'OK'},{'ok':'确定'},['ok'])
        self.assertFalse(review)
        unit=catalog['strings']['ok']['localizations']['en']['stringUnit']
        self.assertEqual(unit,{'state':'needs_review','value':'OK'})
    def test_icu_is_never_flattened(self):
        catalog,review=module.convert({'count':'{n, plural, one{one} other{many}}'},{'count':'{n}个'},['count'])
        self.assertFalse(catalog['strings']);self.assertEqual(len(review),1)
    def test_metadata_placeholders_and_percent_are_queued(self):
        catalog,review=module.convert({'a':'name','@a':{'placeholders':{'user':{}}},'b':'100%'},{'a':'姓名','b':'100%'},['a','b'])
        self.assertFalse(catalog['strings']);self.assertEqual(len(review),2)
    def test_missing_locale_is_queued(self):
        catalog,review=module.convert({'a':'Name'},{},['a'])
        self.assertFalse(catalog['strings']);self.assertEqual(review[0]['reason'],'missing-or-empty-locale')
    def test_metadata_keys_are_rejected(self):
        with self.assertRaises(ValueError): module.convert({}, {}, ['@@locale'])
    def test_duplicate_keys_are_deduplicated(self):
        catalog,_=module.convert({'a':'A'},{'a':'甲'},['a','a'])
        self.assertEqual(len(catalog['strings']),1)

import json
import os
import subprocess
import sys
import tempfile
from unittest import mock

class ImportSafetyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='arb-import-')
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.en = self.root / 'en.arb'
        self.zh = self.root / 'zh.arb'
        self.keys = self.root / 'keys.json'
        self.output = self.root / 'candidate.xcstrings'
        self.review = self.root / 'review.json'
        self.en.write_text('{"ok":"OK"}', encoding='utf-8')
        self.zh.write_text('{"ok":"确定"}', encoding='utf-8')
        self.keys.write_text('["ok"]', encoding='utf-8')

    def cli(self):
        return subprocess.run([sys.executable, '-B', str(pathlib.Path(module.__file__)),
            '--en', str(self.en), '--zh', str(self.zh), '--keys', str(self.keys),
            '--output', str(self.output), '--review-output', str(self.review)],
            text=True, capture_output=True)

    def test_duplicate_arb_key_rejected_before_outputs(self):
        self.en.write_text('{"ok":"first","ok":"second"}', encoding='utf-8')
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate JSON key', result.stderr)
        self.assertFalse(self.output.exists())
        self.assertFalse(self.review.exists())

    def test_nested_duplicate_metadata_rejected(self):
        self.en.write_text('{"ok":"OK","@ok":{"placeholders":{},"placeholders":{}}}', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            module.read_arb(self.en)

    def test_non_json_constants_rejected(self):
        for token in ['NaN', 'Infinity', '-Infinity']:
            with self.subTest(token=token):
                self.en.write_text('{"ok":"OK","metadata":' + token + '}', encoding='utf-8')
                with self.assertRaisesRegex(ValueError, 'non-JSON'):
                    module.read_arb(self.en)

    def test_bad_key_types_are_domain_errors_before_sorting_or_hashing(self):
        for keys in [['ok', 1], ['ok', {}], ['ok', []], ['ok', None], ['ok', True], ['ok', ' ']]:
            with self.subTest(keys=keys):
                with self.assertRaisesRegex(ValueError, 'non-metadata string keys'):
                    module.convert({'ok':'OK'}, {'ok':'确定'}, keys)

    def test_malformed_selected_metadata_cannot_be_flattened(self):
        for metadata in [None, [], 'text', {'placeholders': []}, {'placeholders': 'name'}]:
            with self.subTest(metadata=metadata):
                with self.assertRaisesRegex(ValueError, 'metadata|placeholders'):
                    module.convert({'ok':'OK','@ok':metadata}, {'ok':'确定'}, ['ok'])

    def test_valid_cli_keeps_inputs_and_emits_complete_pair(self):
        before = [p.read_bytes() for p in [self.en, self.zh, self.keys]]
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.output.read_text())['strings']['ok']['localizations']['zh-Hans']['stringUnit']['state'], 'needs_review')
        self.assertEqual(json.loads(self.review.read_text()), [])
        self.assertEqual([p.read_bytes() for p in [self.en, self.zh, self.keys]], before)
        self.assertIn('no app resource changed', result.stdout)

    def test_existing_second_output_never_changes_first_or_existing_file(self):
        self.review.write_bytes(b'owned by another task')
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.review.read_bytes(), b'owned by another task')

    def test_late_second_creation_failure_rolls_back_first_candidate(self):
        real_link = os.link
        def fail_second(source, destination, *args, **kwargs):
            if pathlib.Path(destination) == self.review:
                raise PermissionError('injected second publication failure')
            return real_link(source, destination, *args, **kwargs)
        with mock.patch.object(module.os, 'link', side_effect=fail_second):
            with self.assertRaises(PermissionError):
                module.write_candidates([(self.output, {'strings': {}}), (self.review, [])])
        self.assertFalse(self.output.exists())
        self.assertFalse(self.review.exists())
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['en.arb','keys.json','zh.arb'])

    def test_competing_second_output_is_preserved_and_first_is_rolled_back(self):
        real_link = os.link
        def race(source, destination, *args, **kwargs):
            if pathlib.Path(destination) == self.review:
                self.review.write_bytes(b'concurrent writer')
            return real_link(source, destination, *args, **kwargs)
        with mock.patch.object(module.os, 'link', side_effect=race):
            with self.assertRaises(FileExistsError):
                module.write_candidates([(self.output, {}), (self.review, [])])
        self.assertFalse(self.output.exists())
        self.assertEqual(self.review.read_bytes(), b'concurrent writer')

    def test_replacement_of_first_output_is_not_deleted_during_rollback(self):
        real_link = os.link
        def race(source, destination, *args, **kwargs):
            if pathlib.Path(destination) == self.review:
                self.output.unlink()
                self.output.write_bytes(b'replacement owner')
                raise PermissionError('second publication failed')
            return real_link(source, destination, *args, **kwargs)
        with mock.patch.object(module.os, 'link', side_effect=race):
            with self.assertRaises(PermissionError):
                module.write_candidates([(self.output, {}), (self.review, [])])
        self.assertEqual(self.output.read_bytes(), b'replacement owner')

    def test_serialization_error_never_creates_either_output(self):
        with self.assertRaises(ValueError):
            module.write_candidates([(self.output, {}), (self.review, float('nan'))])
        self.assertFalse(self.output.exists())
        self.assertFalse(self.review.exists())

    def test_staging_write_failure_leaves_no_candidate_or_temporary(self):
        with mock.patch.object(module.os, 'fsync', side_effect=OSError('injected disk error')):
            with self.assertRaises(OSError):
                module.write_candidates([(self.output, {}), (self.review, [])])
        self.assertFalse(self.output.exists())
        self.assertFalse(self.review.exists())
        self.assertFalse(list(self.root.glob('.arb-candidate-*')))

    def test_invalid_unicode_serialization_does_not_leave_a_partial_pair(self):
        with self.assertRaises(UnicodeError):
            module.write_candidates([(self.output, {}), (self.review, {'value': '\ud800'})])
        self.assertFalse(self.output.exists())
        self.assertFalse(self.review.exists())

    def test_duplicate_output_paths_are_rejected_without_writes(self):
        with self.assertRaisesRegex(ValueError, 'distinct'):
            module.write_candidates([(self.output, {}), (self.output, [])])
        self.assertFalse(self.output.exists())

    def test_malformed_input_and_key_selection_leave_no_outputs(self):
        for raw in ['null', '{}', '["ok", null]', '["ok", {}]']:
            with self.subTest(raw=raw):
                self.keys.write_text(raw, encoding='utf-8')
                self.assertNotEqual(self.cli().returncode, 0)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.review.exists())
        self.keys.write_text('["ok"]', encoding='utf-8')
        self.zh.write_bytes(b'\xff')
        self.assertNotEqual(self.cli().returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse(self.review.exists())

    def test_cli_cannot_replace_input_or_follow_existing_symlink(self):
        self.output = self.en
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.en.read_text(), '{"ok":"OK"}')
        self.output = self.root / 'candidate.xcstrings'
        self.output.symlink_to(self.root / 'missing-target')
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.output.is_symlink())
        self.assertFalse((self.root / 'missing-target').exists())
        self.assertFalse(self.review.exists())

if __name__ == '__main__':
    unittest.main()
