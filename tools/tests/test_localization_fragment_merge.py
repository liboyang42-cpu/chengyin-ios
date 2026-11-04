"""Exercise the real fragment merger against new temporary catalogs only."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools import merge_localization_fragments as merger


class LocalizationFragmentMergeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='localization-merge-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.catalog = self.root / 'Localizable.xcstrings'
        self.original = {'sourceLanguage': 'en', 'version': '1.0',
                         'strings': {'existing': self.entry('Reviewed', '已审阅')}}
        self.catalog.write_text(json.dumps(self.original, ensure_ascii=False) + '\n', encoding='utf-8')
        self.original_bytes = self.catalog.read_bytes()
        patch = mock.patch.object(merger, 'CATALOG', self.catalog)
        patch.start()
        self.addCleanup(patch.stop)

    @staticmethod
    def entry(en='English', zh='中文'):
        return {'localizations': {
            'en': {'stringUnit': {'state': 'translated', 'value': en}},
            'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}},
        }}

    def fragment(self, raw, name='fragment.json'):
        path = self.root / name
        if isinstance(raw, bytes):
            path.write_bytes(raw)
        else:
            path.write_text(raw if isinstance(raw, str) else json.dumps(raw, ensure_ascii=False), encoding='utf-8')
        return path

    def merge(self, paths):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            merger.merge(paths)
        return json.loads(output.getvalue())

    def rejects_without_write(self, paths, message):
        with self.assertRaisesRegex(SystemExit, message):
            self.merge(paths)
        self.assertEqual(self.catalog.read_bytes(), self.original_bytes)

    def test_union_preserves_reviewed_copy_and_catalog_metadata(self):
        addition = self.entry('New', '新增')
        path = self.fragment({'strings': {'new': addition}})
        self.assertEqual(self.merge([path]), {'status': 'MERGED', 'added': 1})
        merged = json.loads(self.catalog.read_text(encoding='utf-8'))
        self.assertEqual(merged, dict(self.original, strings=dict(self.original['strings'], new=addition)))

    def test_identical_entry_and_empty_input_leave_original_bytes_untouched(self):
        path = self.fragment({'strings': self.original['strings']})
        for paths in [[], [path], [self.fragment({'strings': {}}, 'empty.json')]]:
            with self.subTest(paths=paths):
                self.assertEqual(self.merge(paths), {'status': 'MERGED', 'added': 0})
                self.assertEqual(self.catalog.read_bytes(), self.original_bytes)

    def test_identical_key_across_fragments_is_added_once(self):
        one = self.fragment({'strings': {'new': self.entry()}}, 'one.json')
        two = self.fragment({'strings': {'new': self.entry()}}, 'two.json')
        self.assertEqual(self.merge([one, two]), {'status': 'MERGED', 'added': 1})

    def test_conflicting_fragment_rolls_back_all_pending_additions(self):
        one = self.fragment({'strings': {'new': self.entry()}}, 'one.json')
        two = self.fragment({'strings': {'existing': self.entry('Changed')}}, 'two.json')
        self.rejects_without_write([one, two], 'differs from the existing catalog entry')

    def test_duplicate_fragment_key_cannot_silently_select_last_translation(self):
        first, second = json.dumps(self.entry('First')), json.dumps(self.entry('Second'))
        path = self.fragment('{"strings":{"collision":' + first + ',"collision":' + second + '}}')
        self.rejects_without_write([path], "duplicate JSON key: 'collision'")

    def test_duplicate_identical_fragment_key_is_still_ambiguous(self):
        entry = json.dumps(self.entry())
        path = self.fragment('{"strings":{"same":' + entry + ',"same":' + entry + '}}')
        self.rejects_without_write([path], "duplicate JSON key: 'same'")

    def test_duplicate_top_level_strings_object_is_rejected(self):
        path = self.fragment('{"strings":{"existing":{}},"strings":{}}')
        self.rejects_without_write([path], "duplicate JSON key: 'strings'")

    def test_duplicate_language_or_string_unit_field_is_rejected(self):
        sources = [
            '{"strings":{"new":{"localizations":{"en":{},"en":{},"zh-Hans":{}}}}}',
            '{"strings":{"new":{"localizations":{"en":{"stringUnit":{"value":"A","value":"B"}},"zh-Hans":{}}}}}',
        ]
        for raw in sources:
            with self.subTest(raw=raw):
                self.rejects_without_write([self.fragment(raw)], 'duplicate JSON key')

    def test_existing_catalog_duplicate_is_rejected_without_rewriting_it(self):
        entry = json.dumps(self.entry())
        self.catalog.write_text('{"strings":{"existing":' + entry + ',"existing":' + entry + '}}', encoding='utf-8')
        self.original_bytes = self.catalog.read_bytes()
        path = self.fragment({'strings': {'new': self.entry()}})
        self.rejects_without_write([path], "duplicate JSON key: 'existing'")

    def test_malformed_utf8_json_or_missing_input_cannot_write_catalog(self):
        for index, raw in enumerate([b'\xff', '{"strings":', 'null', '[]', '{"strings":[]}']):
            with self.subTest(raw=raw):
                self.rejects_without_write([self.fragment(raw, f'bad-{index}.json')], 'invalid catalog|strings object')
        self.rejects_without_write([self.root / 'missing.json'], 'invalid catalog')

    def test_nan_and_infinity_are_not_accepted_as_json(self):
        for value in ['NaN', 'Infinity', '-Infinity']:
            with self.subTest(value=value):
                path = self.fragment('{"strings":{},"metadata":' + value + '}')
                self.rejects_without_write([path], 'non-JSON numeric constant')

    def test_invalid_entry_or_language_shapes_fail_before_any_write(self):
        for entry in [None, [], 'text', {}, {'localizations': []}, {'localizations': {'en': {}}},
                      {'localizations': {'en': {}, 'zh-Hans': {}, 'fr': {}}},
                      {'localizations': {'en': 'text', 'zh-Hans': {}}}]:
            with self.subTest(entry=entry):
                path = self.fragment({'strings': {'new': entry}})
                self.rejects_without_write([path], 'must be an object|exactly en and zh-Hans|must be objects')

    def test_valid_plural_localizations_are_preserved_without_flattening(self):
        entry = {'localizations': {language: {'variations': {'plural': {
            'one': {'stringUnit': {'state': 'translated', 'value': 'One'}},
            'other': {'stringUnit': {'state': 'translated', 'value': 'Many'}},
        }}} for language in ['en', 'zh-Hans']}}
        self.assertEqual(self.merge([self.fragment({'strings': {'plural': entry}})])['added'], 1)
        self.assertEqual(json.loads(self.catalog.read_text())['strings']['plural'], entry)

    def test_later_duplicate_input_cannot_partially_commit_earlier_fragment(self):
        valid = self.fragment({'strings': {'new': self.entry()}}, 'valid.json')
        invalid = self.fragment('{"strings":{},"strings":{}}', 'invalid.json')
        self.rejects_without_write([valid, invalid], 'duplicate JSON key')


if __name__ == '__main__':
    unittest.main()
