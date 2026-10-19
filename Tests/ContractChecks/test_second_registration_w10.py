"""Native source contracts only; not Swift compilation, UI, or live-service evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class SecondRegistrationW10Checks(unittest.TestCase):
    def test_core_has_no_transport_or_metric_derivation(self):
        core = read("Core/SecondRegistrationMetrics.swift")
        for forbidden in ["HTTPTransport", "URLRequest", "URLSession", "httpMethod", "UserDefaults", "FileManager"]:
            self.assertNotIn(forbidden, core)
        # Maturity and N/D come from the report; the client never derives them from dates.
        self.assertIn("public let mature: Bool", core)
        self.assertNotIn("Calendar", core)
        self.assertIn("case days7 = 7, days28 = 28, days56 = 56", core)

    def test_zero_denominator_and_immature_rules(self):
        core = read("Core/SecondRegistrationMetrics.swift")
        self.assertIn("if d == 0 { self = (cell.numerator ?? 0) == 0 ? .noMatureSample : .unavailable; return }", core)
        self.assertIn("guard cell.mature else", core)
        self.assertIn("guard let n = cell.numerator, n >= 0, n <= d else { self = .unavailable; return }", core)

    def test_client_event_envelope_fields(self):
        core = read("Core/SecondRegistrationMetrics.swift")
        for field in ['"event_id"', '"idempotency_key"', '"occurred_at"', "schemaVersion", "source", '"is_test"', '"client_version"', "trace"]:
            self.assertIn(field, core)
        self.assertNotIn("received_at", core)
        self.assertNotIn("accountID", core)

    def test_fixture_is_debug_only_and_marked_test(self):
        view = read("App/SecondRegistrationStatsView.swift")
        debug = view.split("#if DEBUG", 1)
        self.assertEqual(len(debug), 2)
        self.assertIn("SecondRegistrationFixtures", debug[1])
        self.assertNotIn("SecondRegistrationFixtures", debug[0])
        self.assertIn('"isTest":true', debug[1])
        app = read("App/QuestifyApp.swift")
        self.assertIn('SecondRegistrationFixtureHost(scenario: fixtureArgument("--second-registration-fixture") ?? "mature")', app)

    def test_localization_keys_exist_in_both_languages(self):
        view = read("App/SecondRegistrationStatsView.swift")
        catalog = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        keys = set(re.findall(r'"(secondRegistration\.[A-Za-z0-9.]+)"', view))
        keys -= {"secondRegistration.content", "secondRegistration.footer", "secondRegistration.window.", "secondRegistration.transition."}
        keys |= {"secondRegistration.rate %@ %lld %lld", "secondRegistration.observedOnly %lld", "secondRegistration.window %lld"}
        keys |= {f"secondRegistration.transition.{a}.{b}" for a in ("free", "paid") for b in ("free", "paid")}
        for key in sorted(keys):
            if key in {"secondRegistration.rate", "secondRegistration.observedOnly", "secondRegistration.window"}:
                continue
            self.assertIn(key, catalog, key)
            for language in ("en", "zh-Hans"):
                self.assertTrue(catalog[key]["localizations"][language]["stringUnit"]["value"].strip(), (key, language))


if __name__ == "__main__":
    unittest.main()
