"""Native source contracts only; not Swift compilation, UI, or live-service evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class OfficialPrivateFactsChecks(unittest.TestCase):
    def test_shared_rows_decode_source_facts(self):
        model = read("Core/OfficialEventContracts.swift")
        self.assertIn("windowFacts = try? OfficialInboxWindowFacts(from: decoder)", model)
        self.assertIn("facts = try? OfficialPublishedBroadcastFacts(from: decoder)", model)

    def test_views_render_localized_facts(self):
        views = read("App/OfficialPrivateViews.swift")
        self.assertIn("OfficialPrivateFactsText.window(facts.window)", views)
        self.assertIn("OfficialPrivateFactsText.broadcastLine(facts)", views)
        text = read("App/OfficialPrivateFactsText.swift")
        self.assertNotIn("sourceText", text)
        self.assertNotIn("sourceLine", text)

    def test_keys_exist_in_both_languages(self):
        text = read("App/OfficialPrivateFactsText.swift")
        catalog = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        keys = set(re.findall(r'"(official\.w206\.[A-Za-z.]+)"', text))
        keys |= {"official.w206.window.range %@ %@", "official.w206.window.time %lld %lld %@", "official.w206.broadcast.line %@ %@ %@"}
        for key in sorted(keys):
            self.assertIn(key, catalog, key)
            for language in ("en", "zh-Hans"):
                self.assertTrue(catalog[key]["localizations"][language]["stringUnit"]["value"].strip(), (key, language))


if __name__ == "__main__":
    unittest.main()
