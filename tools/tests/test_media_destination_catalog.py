import contextlib
import io
import json
from pathlib import Path
import runpy
import unittest
from unittest import mock
ROOT = Path(__file__).resolve().parents[2]
class MediaDestinationCatalogChecks(unittest.TestCase):
    def run_checker(self, transform=None):
        original = Path.read_text
        def read(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if transform and path == ROOT / 'Resources/Localizable.xcstrings':
                data = json.loads(text); transform(data['strings']); return json.dumps(data)
            return text
        with mock.patch.object(Path, 'read_text', read), contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(ROOT / 'tools/check_media_destinations.py'), run_name='__main__')
    def test_cross_fragment_copy_key_is_present_and_bilingual(self):
        self.run_checker()
    def test_missing_cross_fragment_key_still_fails(self):
        with self.assertRaises(AssertionError):
            self.run_checker(lambda strings: strings.pop('withdrawal.support.copyWeChat'))
    def test_blank_required_locale_still_fails(self):
        def blank(strings):
            strings['withdrawal.support.copyWeChat']['localizations']['zh-Hans']['stringUnit']['value'] = ' '
        with self.assertRaises(AssertionError): self.run_checker(blank)
