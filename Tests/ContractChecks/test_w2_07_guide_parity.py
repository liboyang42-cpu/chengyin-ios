"""w2-07: source guards for the mini-program play-guide (infomation) parity copy."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class W207GuideParity(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/SocialGuideViews.swift').read_text()
        self.parity = (ROOT / 'App/SocialGuideXcxParity.swift').read_text()
        self.catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        self.rows = json.loads((ROOT / 'docs/parity/w2-07-localizations.json').read_text())

    def zh(self, key):
        return self.catalog[key]['localizations']['zh-Hans']['stringUnit']['value']

    def test_source_copy_is_in_catalog(self):
        for row in self.rows:
            for lang in ('en', 'zh-Hans'):
                self.assertEqual(self.catalog[row['key']]['localizations'][lang]['stringUnit']['value'], row[lang], row['key'])
        self.assertEqual(self.zh('social.guide.title'), '城瘾玩法')
        self.assertEqual(self.zh('social.guideXcx.go'), '去看看')
        self.assertEqual(self.zh('social.guideXcx.docs'), '玩法文档')
        self.assertEqual(self.zh('social.guideXcx.docsEmpty'), '暂无玩法说明')

    def test_existing_read_path_and_identifiers_are_kept(self):
        self.assertIn('SocialReadScreen(reader: reader, requestKey: "information-list"', self.view)
        self.assertIn('.accessibilityIdentifier("social.information.\\(row.id)")', self.view)
        self.assertIn('.accessibilityIdentifier("social.guide.\\(mode.rawValue)")', self.parity)
        self.assertIn('SocialGuideTemplateSection(reader: templateReader)', self.view)
        for mode in ('classic', 'free', 'roam'):
            for suffix in ('Tag', 'Detail'):
                self.assertIn(f'"social.guideXcx.{mode}{suffix}"', self.parity)

    def test_detail_shows_source_create_time(self):
        self.assertIn('SocialText.nonempty(row.createTime)', self.view)
        self.assertIn('createTime = v["createTime"].text', (ROOT / 'Core/SocialAccountContracts.swift').read_text())

    def test_localization_tool_is_idempotent(self):
        import subprocess, sys
        out = subprocess.run([sys.executable, '-B', str(ROOT / 'tools/build_w2_07_localizations.py'), '--check'], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)


if __name__ == '__main__':
    unittest.main()
