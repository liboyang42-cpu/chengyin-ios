"""CITY fairness read contract. Swift compile, XCTest, and the app are NOT_RUN."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
ID = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9_-]{0,95}\Z")
VERSION = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")
CURSOR = re.compile(r"\A[A-Za-z0-9._~-]{1,2048}\Z")
STAMP_MAX = 253_402_300_799_000


def valid_text(value, limit):
    return isinstance(value, str) and value.strip() != "" and len(value) <= limit and not any(ord(ch) < 32 for ch in value)


def classify(status, body, region="region1"):
    """Mirror of CityFairnessWire.page. Errors return no ratio."""
    if status == 401:
        return "unauthorized", None
    if status == 403:
        return "forbidden", None
    if status == 503:
        return "unavailable", None
    if not 200 <= status < 300 or body in (b"", None):
        return "malformed", None
    try:
        envelope = json.loads(body)
    except json.JSONDecodeError:
        return "malformed", None
    if not isinstance(envelope, dict):
        return "malformed", None
    code = envelope.get("code")
    if code == 401:
        return "unauthorized", None
    if code == 403:
        return "forbidden", None
    if code == 503:
        return "unavailable", None
    data = envelope.get("data")
    if code != 200 or not isinstance(data, dict):
        return "malformed", None
    if data.get("contract") != "CITY_FAIRNESS_READ_V1" or data.get("scope") != "CITY" or data.get("regionId") != region:
        return "malformed", None
    name = data.get("status")
    numerator, denominator = data.get("numerator"), data.get("denominator")
    if name in ("MISSING_CONFIG", "NO_MATURE_SAMPLE", "UNKNOWN"):
        if numerator is not None or denominator is not None:
            return "malformed", None
        reason = data.get("missingReason")
        if name == "UNKNOWN":
            if reason is None:
                return "unknown", None
            return ("unknown", None) if valid_text(reason, 160) else ("malformed", None)
        if not valid_text(reason, 160):
            return "malformed", None
        if name == "NO_MATURE_SAMPLE":
            if not optional_count(data.get("sampleCount")) or not optional_stamp(data.get("asOf")) or not optional_version(data.get("metricVersion")):
                return "malformed", None
        return ("missing" if name == "MISSING_CONFIG" else "gap"), None
    if name != "MATURE":
        return "unknown-failure", None
    if not isinstance(numerator, int) or not isinstance(denominator, int) or isinstance(numerator, bool) or isinstance(denominator, bool):
        return "malformed", None
    if denominator <= 0 or numerator < 0 or numerator > 1_000_000 or denominator > 1_000_000:
        return "malformed", None
    if not required_count(data.get("sampleCount")) or data.get("asOf") is None or not optional_stamp(data.get("asOf")) or not optional_version(data.get("metricVersion")):
        return "malformed", None
    outings = data.get("outings")
    if not isinstance(outings, list) or len(outings) > 50:
        return "malformed", None
    seen = set()
    for row in outings:
        if not isinstance(row, dict) or not ID.fullmatch(row.get("outingId", "")) or not valid_text(row.get("title", ""), 160):
            return "malformed", None
        if row["outingId"] in seen:
            return "malformed", None
        seen.add(row["outingId"])
    cursor = data.get("nextCursor")
    if cursor is not None and not CURSOR.fullmatch(cursor):
        return "malformed", None
    return "mature", f"{numerator}/{denominator}"


def optional_count(value):
    if value is None:
        return True
    return required_count(value)


def required_count(value):
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 1_000_000


def optional_stamp(value):
    if value is None:
        return True
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= STAMP_MAX


def optional_version(value):
    if value is None:
        return True
    return isinstance(value, str) and VERSION.fullmatch(value) is not None


def merge(previous, incoming):
    """Continuation must repeat N/D, sample count, and metric version or the prior page stays."""
    same = (incoming["numerator"], incoming["denominator"], incoming["sampleCount"], incoming["metricVersion"]) == (
        previous["numerator"], previous["denominator"], previous["sampleCount"], previous["metricVersion"])
    if not same:
        return previous
    seen = {row["outingId"] for row in previous["outings"]}
    added = [row for row in incoming["outings"] if row["outingId"] not in seen and not seen.add(row["outingId"])]
    merged = dict(previous)
    merged["outings"] = previous["outings"] + added
    merged["asOf"] = incoming["asOf"]
    merged["nextCursor"] = incoming["nextCursor"]
    return merged


def envelope(payload, code=200):
    return json.dumps({"code": code, "data": payload}).encode()


def mature(**overrides):
    payload = {
        "contract": "CITY_FAIRNESS_READ_V1", "scope": "CITY", "status": "MATURE", "regionId": "region1",
        "numerator": 2, "denominator": 5, "sampleCount": 9, "asOf": 1_700_000_000_000, "metricVersion": "fairness.v1",
        "outings": [{"outingId": "outing1", "title": "North loop"}], "nextCursor": None,
    }
    payload.update(overrides)
    return payload


class CityFairnessContracts(unittest.TestCase):
    def test_blocked_statuses_are_not_a_ratio(self):
        ratio_body = envelope(mature(numerator=0, denominator=4))
        for status, kind in ((401, "unauthorized"), (403, "forbidden"), (503, "unavailable")):
            got, ratio = classify(status, ratio_body)
            self.assertEqual(got, kind)
            self.assertIsNone(ratio)
        for body in (b"", b"{}", b"[]", b"not-json"):
            self.assertEqual(classify(200, body), ("malformed", None))
        self.assertEqual(classify(200, envelope(mature(), code=403)), ("forbidden", None))
        self.assertEqual(classify(200, envelope(mature(), code=503)), ("unavailable", None))
        self.assertEqual(classify(200, envelope(mature(), code=401)), ("unauthorized", None))
        self.assertIsNone(classify(500, ratio_body)[1])

    def test_missing_gap_and_unknown_have_no_ratio(self):
        missing = mature(status="MISSING_CONFIG", missingReason="no board", numerator=None, denominator=None, sampleCount=None, asOf=None, metricVersion=None, outings=None)
        gap = mature(status="NO_MATURE_SAMPLE", missingReason="too new", numerator=None, denominator=None, outings=None, sampleCount=3)
        unknown = mature(status="UNKNOWN", missingReason=None, numerator=None, denominator=None, sampleCount=None, asOf=None, metricVersion=None, outings=None)
        self.assertEqual(classify(200, envelope(missing))[0], "missing")
        self.assertIsNone(classify(200, envelope(missing))[1])
        self.assertEqual(classify(200, envelope(gap)), ("gap", None))
        self.assertEqual(classify(200, envelope(unknown)), ("unknown", None))
        poisoned = mature(status="NO_MATURE_SAMPLE", missingReason="too new", numerator=0, denominator=1)
        self.assertEqual(classify(200, envelope(poisoned)), ("malformed", None))
        self.assertEqual(classify(200, envelope(mature(status="LATER"))), ("unknown-failure", None))

    def test_mature_ratio_is_numerator_over_denominator(self):
        kind, ratio = classify(200, envelope(mature(numerator=0, denominator=4)))
        self.assertEqual((kind, ratio), ("mature", "0/4"))
        self.assertNotIn("%", ratio)
        self.assertEqual(classify(200, envelope(mature(denominator=0))), ("malformed", None))
        self.assertEqual(classify(200, envelope(mature(numerator=None))), ("malformed", None))
        self.assertEqual(classify(200, envelope(mature(outings=[]))), ("mature", "2/5"))

    def test_continuation_mismatch_keeps_the_previous_page(self):
        previous = {"numerator": 2, "denominator": 5, "sampleCount": 9, "metricVersion": "fairness.v1", "asOf": 1, "nextCursor": "page2",
                    "outings": [{"outingId": "outing1", "title": "North loop"}]}
        changed = dict(previous, numerator=0, outings=[{"outingId": "outing2", "title": "East"}], nextCursor=None)
        self.assertEqual(merge(previous, changed)["numerator"], 2)
        self.assertEqual(merge(previous, changed)["outings"], previous["outings"])
        added = dict(previous, outings=[{"outingId": "outing1", "title": "North loop"}, {"outingId": "outing2", "title": "East"}], nextCursor=None, asOf=2)
        merged = merge(previous, added)
        self.assertEqual([row["outingId"] for row in merged["outings"]], ["outing1", "outing2"])
        self.assertEqual(merged["asOf"], 2)
        self.assertIsNone(merged["nextCursor"])

    def test_source_rejects_errors_before_a_ratio_and_does_not_write(self):
        source = (ROOT / "Core/CityFairness.swift").read_text()
        view = (ROOT / "App/CityFairnessView.swift").read_text()
        self.assertLess(source.index("if status == 401"), source.index("JSONDecoder().decode"))
        self.assertLess(source.index("if status == 403"), source.index("JSONDecoder().decode"))
        self.assertLess(source.index("if status == 503"), source.index("JSONDecoder().decode"))
        for marker in [
            'request.httpMethod = "GET"', 'request.httpMethod == "GET"', "denominator > 0",
            "CITY_FAIRNESS_READ_V1", "case unknown(String?)", "generation == stamp", "evidenceGeneration == stamp",
            "incoming.numerator == current.numerator", "onUnauthorized", "func revoke()", "86_400",
            "api == .httpStatus(403)", "api == .httpStatus(503)", 'screen: CityFairnessScreen = .blocked',
            "var ratioText: String { \"\\(numerator)/\\(denominator)\" }",
        ]:
            self.assertIn(marker, source)
        for denied in ["fatalError", "httpMethod = \"POST\"", "\"POST\"", "memberId", "UserDefaults", "CLLocation", "rendezvous", "randomMatch", "autoJoin", "%"]:
            self.assertNotIn(denied, source)
            self.assertNotIn(denied, view)
        for marker in ['tableName: "CityFairness"', "restoreSameQuery()", "loadEvidence(outingID)", "clearEvidence()", "page.ratioText", "fairness.back"]:
            self.assertIn(marker, view)
        self.assertNotIn("AppSession", view)
        self.assertNotIn("makeCityFairnessReader", view)

    def test_committed_host_files_are_untouched(self):
        for relative in [
            "App/AppSession.swift", "App/AppCompositionRoot.swift", "App/QuestifyApp.swift", "App/AccountView.swift",
            "App/CityPlayerView.swift", "App/RoamBrowserView.swift", "Questify.xcodeproj/project.pbxproj",
        ]:
            self.assertNotIn("CityFairness", (ROOT / relative).read_text())

    def test_catalog_is_bilingual_and_covers_literal_keys(self):
        catalog = json.loads((ROOT / "Resources/CityFairness.xcstrings").read_text())
        self.assertEqual(catalog["sourceLanguage"], "en")
        view = (ROOT / "App/CityFairnessView.swift").read_text()
        used = set(re.findall(r'Text\("([^"]+)", tableName: "CityFairness"\)', view))
        self.assertGreaterEqual(len(used), 16)
        self.assertEqual(used | {"fairness.entry"}, set(catalog["strings"]))
        for key, entry in catalog["strings"].items():
            self.assertEqual(set(entry["localizations"]), {"en", "zh-Hans"})
            for lang in ("en", "zh-Hans"):
                value = entry["localizations"][lang]["stringUnit"]["value"]
                self.assertTrue(value.strip())
                self.assertNotIn("%", value)
            self.assertNotIn("%", key)


if __name__ == "__main__":
    unittest.main()
