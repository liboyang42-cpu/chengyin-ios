"""CITY fairness read aligned to hengyin B4-1 c371bdd. Swift compile and XCTest are NOT_RUN."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FORMULA = "city-fairness-cohort-v1"


def classify(status, body):
    """Decision table for the report. 401, 403, 422, 503, and empty never return a ratio."""
    if status == 401:
        return "unauthorized", None
    if status == 403:
        return "forbidden", None
    if status == 422:
        return "not-computable", None
    if status == 503:
        return "unavailable", None
    if status in (400, 409) or not 200 <= status < 300 or body in (b"", None):
        return "malformed", None
    try:
        envelope = json.loads(body)
    except json.JSONDecodeError:
        return "malformed", None
    if not isinstance(envelope, dict):
        return "malformed", None
    code = envelope.get("code")
    if code in (401, 403, 422, 503):
        return {401: "unauthorized", 403: "forbidden", 422: "not-computable", 503: "unavailable"}[code], None
    data = envelope.get("data")
    if code != 200 or not isinstance(data, dict):
        return "malformed", None
    if data.get("status") == "NOT_COMPUTABLE":
        return "not-computable", None
    if data.get("status") != "COMPUTABLE" or data.get("formulaId") != FORMULA:
        return "malformed", None
    mature, denominator = data.get("matureCount"), data.get("denominator")
    if mature is None and denominator is None:
        if data.get("maturity") == "NO_MATURE_SAMPLE":
            return "no-mature-sample", None
        return "malformed", None
    if data.get("maturity") != "COUNTED":
        return "malformed", None
    if not isinstance(mature, int) or isinstance(mature, bool) or not isinstance(denominator, int) or isinstance(denominator, bool):
        return "malformed", None
    if denominator <= 0 or mature < 0 or mature > denominator:
        return "malformed", None
    return "mature", f"{mature}/{denominator}"


def envelope(payload, code=200):
    return json.dumps({"code": code, "data": payload}).encode()


def counted(**overrides):
    payload = {
        "status": "COMPUTABLE", "maturity": "COUNTED", "formulaId": FORMULA,
        "boardId": "board1", "regionId": "region1", "seasonId": "season1", "rulesVersion": "rules1",
        "matureCount": 2, "denominator": 5, "asOf": 1_700_000_000_000, "metricVersion": "fairness.v1",
        "factRevision": 4, "missing": [], "outingClasses": [], "nextCursor": None,
    }
    payload.update(overrides)
    return payload


class CityFairnessContracts(unittest.TestCase):
    def test_error_statuses_are_not_a_ratio(self):
        poisoned = envelope(counted(matureCount=0, denominator=4))
        for status, kind in ((401, "unauthorized"), (403, "forbidden"), (422, "not-computable"), (503, "unavailable")):
            got, ratio = classify(status, poisoned)
            self.assertEqual(got, kind)
            self.assertIsNone(ratio)
        self.assertEqual(classify(200, b""), ("malformed", None))
        self.assertEqual(classify(200, envelope(counted(matureCount=0, denominator=1), code=422)), ("not-computable", None))
        self.assertIsNone(classify(422, envelope(counted(matureCount=0, denominator=1)))[1])

    def test_null_counts_are_no_mature_sample_and_zero_numerator_stays_a_ratio(self):
        gap = counted(maturity="NO_MATURE_SAMPLE", matureCount=None, denominator=None, outingClasses=None)
        self.assertEqual(classify(200, envelope(gap)), ("no-mature-sample", None))
        kind, ratio = classify(200, envelope(counted(matureCount=0, denominator=4)))
        self.assertEqual((kind, ratio), ("mature", "0/4"))
        self.assertNotIn("%", ratio)
        self.assertEqual(classify(200, envelope(counted(denominator=0))), ("malformed", None))
        self.assertEqual(classify(200, envelope(counted(status="NOT_COMPUTABLE", matureCount=0, denominator=1))), ("not-computable", None))

    def test_source_matches_backend_report_fields(self):
        source = (ROOT / "Core/CityFairness.swift").read_text()
        view = (ROOT / "App/CityFairnessView.swift").read_text()
        for marker in [
            'case report = "fairness/report"', 'outing = "fairness/outing"',
            '["api", "city-game", "fairness", "report"]', '["api", "city-game", "fairness", "outing"]',
            '"queryId"', '"asOf"', '"boardId"', '"regionId"', '"seasonId"', '"rulesVersion"', '"cursor"', '"outingId"',
            "values[\"accountId\"] == nil", "matureCount", "denominator", "formulaId", "factRevision",
            "city-fairness-cohort-v1", '"NO_MATURE_SAMPLE"', '"NOT_COMPUTABLE"', '"COUNTED"',
            "if status == 422", "api == .httpStatus(422)", "case notComputable",
            "payload.matureCount == nil, payload.denominator == nil",
            'request.httpMethod = "GET"', "generation == stamp", "onUnauthorized", "func revoke()",
            "var ratioText: String { \"\\(matureCount)/\\(denominator)\" }",
        ]:
            self.assertIn(marker, source)
        self.assertLess(source.index("if status == 422"), source.index("private static func screen"))
        self.assertNotIn('fields["accountId"]', source)
        self.assertNotIn('case page = "fairness"', source)
        for denied in ["fatalError", "httpMethod = \"POST\"", "\"POST\"", "memberId", "UserDefaults", "CLLocation", "rendezvous", "randomMatch", "autoJoin", "%"]:
            self.assertNotIn(denied, source)
            self.assertNotIn(denied, view)
        for marker in ['tableName: "CityFairness"', "restoreSameQuery()", "loadEvidence(outingID)", "clearEvidence()", "page.ratioText", "fairness.back", "fairness.notComputable", "fairness.noMatureSample"]:
            self.assertIn(marker, view)
        self.assertNotIn("AppSession", view)

    def test_committed_host_files_are_untouched(self):
        for relative in [
            "App/AppSession.swift", "App/AppCompositionRoot.swift", "App/QuestifyApp.swift", "App/AccountView.swift",
            "App/CityPlayerView.swift", "App/RoamBrowserView.swift", "Questify.xcodeproj/project.pbxproj",
        ]:
            self.assertNotIn("CityFairness", (ROOT / relative).read_text())

    def test_catalog_is_bilingual_and_covers_literal_keys(self):
        catalog = json.loads((ROOT / "Resources/CityFairness.xcstrings").read_text())
        view = (ROOT / "App/CityFairnessView.swift").read_text()
        used = set(re.findall(r'Text\("([^"]+)", tableName: "CityFairness"\)', view))
        self.assertEqual(used | {"fairness.entry"}, set(catalog["strings"]))
        for key, entry in catalog["strings"].items():
            self.assertEqual(set(entry["localizations"]), {"en", "zh-Hans"})
            for lang in ("en", "zh-Hans"):
                value = entry["localizations"][lang]["stringUnit"]["value"]
                self.assertTrue(value.strip())
                self.assertNotIn("%", value)


if __name__ == "__main__":
    unittest.main()
