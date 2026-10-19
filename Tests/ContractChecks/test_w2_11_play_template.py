"""Source guards for w2-11 (play / template parity and the W03 recovery contract).

They do not compile Swift or run XCTest; they pin the safety properties that a
reviewer would otherwise have to re-derive from the Swift sources.
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def code(path):
    return "\n".join(line for line in read(path).splitlines() if not line.lstrip().startswith("//"))


class W211PlayTemplateGuards(unittest.TestCase):
    def test_template_extras_never_decode_answers_and_preview_sends_nothing(self):
        extras = code("Core/DiscoveryPlayTemplateExtras.swift")
        self.assertNotIn("questionAnswer", extras)
        for forbidden in ("URLRequest", "transport", "api/"):
            self.assertNotIn(forbidden, extras)
        sections = code("App/DiscoveryTemplateDetailParitySections.swift")
        for forbidden in ("reader.", "Task {", "await "):
            self.assertNotIn(forbidden, sections)

    def test_detail_keeps_single_info_read(self):
        service = read("Core/DiscoveryService.swift")
        body = service.split("func playTemplateRead", 1)[1].split("private func post", 1)[0]
        self.assertEqual(body.count('post("api/template/info"'), 1)
        view = read("App/DiscoveryTemplateDetailView.swift")
        self.assertIn("reader.discoveryPlayTemplateRead(id: requested.id)", view)
        self.assertNotIn("reader.discoveryPlayTemplate(id:", view.split("/// Uses only the server", 1)[0])

    def test_run_recovery_is_offline_disabled_and_journals_identifiers_only(self):
        text = code("Core/RunAuthorityRecovery.swift")
        for forbidden in ("URLRequest", "URLSession", "HTTPTransport", "api/", "https://"):
            self.assertNotIn(forbidden, text)
        self.assertIn("guard capabilities.allows(.runAuthority), service != nil else { phase = .disabled; return }", text)
        record = text.split("public struct RunIntentJournalRecord", 1)[1].split("public init", 1)[0]
        stored = set(re.findall(r"public let ([^:]+):", record))
        self.assertEqual(stored, {"runId, nodeId, requestId, kind", "expectedStateVersion", "bodySHA256"})
        confirm = text.split("public func confirm()", 1)[1].split("public func retrySameIntent", 1)[0]
        self.assertLess(confirm.index("journal.write"), confirm.index("dispatch("))

    def test_localizations_are_bilingual(self):
        pairs = json.loads(read("docs/w2-11-localizations.json"))
        catalog = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        for key, (en, zh) in pairs.items():
            self.assertTrue(en and zh, key)
            self.assertEqual(catalog[key]["localizations"]["en"]["stringUnit"]["value"], en)
            self.assertEqual(catalog[key]["localizations"]["zh-Hans"]["stringUnit"]["value"], zh)


if __name__ == "__main__":
    unittest.main()
