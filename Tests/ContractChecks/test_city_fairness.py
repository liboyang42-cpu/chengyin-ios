"""CITY fairness read against hengyin 0a0e2b9d2ac29359d502330956b5d6867f353db8. Swift compile and XCTest are NOT_RUN."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FORMULA = "city-fairness-cohort-v1"
REASONS = {"first-outing", "second-outing", "inside-delta", "after-horizon", "before-t0", "not-effective"}
TABLES = {"city_fairness_parameter", "city_fairness_event", "unavailable"}
SCOPE = {"boardId": "board1", "regionId": "region1", "seasonId": "season1", "rulesVersion": "rules1"}
SAMPLE_SOURCE = "docs/contracts/w20-fairness-samples"
SAMPLES = {
    "report-first-page.json": "6464206d9bedc45db1a94f8a1599e587318be55b9d94d2cfc41c81e033e0ed53",
    "outing-first-page.json": "874e48bf180c1592646162ac58ee7a619080b14cc1c45d8c766ba5f9135d4961",
    "outing-next-page.json": "dffc9c21fa38502219d226dfcaf8151ed363fcd87d41ca245f22068700cc1caf",
    "report-empty-mature.json": "e4b93c713a10f0ff7e4b889196056db0bd207a195b67aa2d8444d38a63eb316b",
    "report-503.json": "1a25a980bc5c3524e494ffdc35a4f717216f6b3a517d987ac604bedc861b4669",
    "outing-503.json": "fd7cc5ab585d1fe562fe4e06734ef0181207f592eee91852bdc9036afef013fe",
}


def classify(status, body):
    """Decision table for the report. 401, 403, 422, 503, and empty never return a ratio."""
    if status == 401:
        return "unauthorized", None
    if status == 403:
        return "forbidden", None
    if status == 422:
        return "not-computable", None
    if status == 503:
        return failure_503(body), None
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


def outing_envelope(payload, code=200, msg="操作成功", candidate=True):
    return json.dumps({"code": code, "msg": msg, "data": payload, "candidate": candidate}).encode()


def outing_row(outing_id="o1", reason="first-outing", **overrides):
    row = {
        "outingId": outing_id, "t0": 1_700_000_000_000, "valid": True, "reason": reason,
        "inWindow": True, "maturity": "IMMATURE", "metricVersion": "fairness.v1", "factRevision": 4,
    }
    row.update(overrides)
    return row


def outing_payload(**overrides):
    payload = {
        "accountId": 7, "queryId": "q1", "asOf": 1_700_000_000_000, "metricVersion": "fairness.v1",
        "formulaId": FORMULA, "factRevision": 4, **SCOPE, "status": "COMPUTABLE", "maturity": "IMMATURE",
        "t0": 1_700_000_000_000, "missing": [], "outings": [outing_row()], "cursor": None,
        "nextCursor": None, "readBack": True,
    }
    payload.update(overrides)
    return payload


def failure_503(body):
    """selectRead is unavailable with missing city_fairness_read. The table name is not the errorCode."""
    try:
        envelope = json.loads(body) if body else {}
    except json.JSONDecodeError:
        return "malformed"
    data = envelope.get("data") if isinstance(envelope, dict) else None
    if not isinstance(data, dict):
        return "malformed"
    code = data.get("errorCode")
    if code not in TABLES:
        return "malformed"
    if code == "unavailable" and data.get("missing") != ["city_fairness_read"]:
        return "malformed"
    if data.get("status") is not None or data.get("matureCount") is not None or data.get("denominator") is not None:
        return "malformed"
    return "unavailable"


def classify_outing(status, body, account_id=7, query_id="q1", as_of=1_700_000_000_000, requested_cursor=None, scope=None):
    """Own-outing decision. Rows never become a ratio. Unknown reasons stay unknown."""
    if status == 401:
        return "unauthorized", None, None, False
    if status == 403:
        return "forbidden", None, None, False
    if status == 422:
        return "not-computable", None, None, False
    if status == 503:
        return failure_503(body), None, None, False
    if status in (400, 409) or status != 200 or body in (b"", None):
        return "malformed", None, None, False
    try:
        envelope = json.loads(body)
    except json.JSONDecodeError:
        return "malformed", None, None, False
    if not isinstance(envelope, dict):
        return "malformed", None, None, False
    if envelope.get("code") != status or envelope.get("candidate") is not True or envelope.get("msg") != "操作成功":
        return "malformed", None, None, False
    data = envelope.get("data")
    if not isinstance(data, dict):
        return "malformed", None, None, False
    if data.get("status") == "NOT_COMPUTABLE":
        return "not-computable", None, None, False
    if data.get("accountId") != account_id or data.get("queryId") != query_id or data.get("asOf") != as_of:
        return "discard", None, None, False
    expected_scope = SCOPE if scope is None else scope
    if any(data.get(key) != value for key, value in expected_scope.items()):
        return "discard", None, None, False
    if not same_cursor(requested_cursor, data.get("cursor")):
        return "malformed", None, None, False
    if data.get("status") != "COMPUTABLE" or data.get("formulaId") not in (None, FORMULA):
        return "malformed", None, None, False
    rows = data.get("outings")
    if not isinstance(rows, list):
        return "malformed", None, None, False
    ids = []
    reasons = []
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("outingId"), str):
            return "malformed", None, None, False
        ids.append(row["outingId"])
        reason = row.get("reason")
        reasons.append(reason if reason in REASONS else "unknown")
    if len(ids) != len(set(ids)):
        return "malformed", None, None, False
    return "rows", None, reasons, data.get("maturity") == "MATURE"


def same_cursor(requested, echoed):
    """Nil and "0" are the first page. Any later cursor must match exactly."""
    if requested == echoed:
        return True
    return requested in (None, "0") and echoed in (None, "0")


def fact_display(value):
    """A null gap is missing. A real integer, including 0, stays a count and is not a percent."""
    if value is None:
        return "missing"
    if isinstance(value, bool) or not isinstance(value, int):
        return "malformed"
    if value < 0:
        return "malformed"
    return ("count", value)


def own_report_ratio(members, account_id, mature, denominator):
    if any(row.get("actorId") != account_id for row in members):
        return None
    return f"{mature}/{denominator}"


def keep_outing_page(old, new):
    keys = ("queryId", "asOf", "metricVersion", "factRevision")
    if old is not None and any(old.get(key) != new.get(key) for key in keys):
        return old
    return new


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
        for status, kind in ((401, "unauthorized"), (403, "forbidden"), (422, "not-computable")):
            got, ratio = classify(status, poisoned)
            self.assertEqual(got, kind)
            self.assertIsNone(ratio)
        got, ratio = classify(503, poisoned)
        self.assertEqual(got, "malformed")
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

    def test_source_matches_backend_report_and_outing_fields(self):
        source = (ROOT / "Core/CityFairness.swift").read_text()
        view = (ROOT / "App/CityFairnessView.swift").read_text()
        for marker in [
            'case report = "fairness/report"', 'outing = "fairness/outing"',
            '["api", "city-game", "fairness", "report"]', '["api", "city-game", "fairness", "outing"]',
            "init(outing scope:", "init(report scope:", "func ownOutings", "func report",
            '"queryId"', '"asOf"', '"boardId"', '"regionId"', '"seasonId"', '"rulesVersion"', '"cursor"',
            'values["outingId"] == nil', "values[\"accountId\"] == nil",
            "matureCount", "denominator", "formulaId", "factRevision", "readBack", "inWindow", "row.valid",
            "city-fairness-cohort-v1", '"NO_MATURE_SAMPLE"', '"NOT_COMPUTABLE"', '"COUNTED"',
            "if status == 400", "if status == 401", "if status == 403", "if status == 409",
            "if status == 422", "if status == 503", "api == .httpStatus(422)", "case notComputable",
            '"UNAUTHORIZED"', '"scope-rejected"', '"query-conflict"',
            "city_fairness_parameter", "city_fairness_event", '"unavailable"',
            'missing(data) != ["city_fairness_read"]',
            "X-Chengyin-Candidate", "city-fairness", "envelope.code == status", "envelope.candidate", "操作成功",
            "payload.accountId == accountID", "payload.queryId == queryID", "payload.asOf == asOf",
            "sameCursor(requestedCursor, payload.cursor)",
            'cursor != "0"', "left == nil || left == \"0\"", "restartRestoreSupported = true",
            "cityFairness.query.", "UserDefaults.standard", "func clearAll()", "func clearOtherAccounts",
            "coverageGaps", "goalCompletions", "func setForeground",
            "failure == .forbidden", '"UNKNOWN"',
            "first-outing", "second-outing", "inside-delta", "after-horizon", "before-t0", "not-effective",
            "default: self = .unknown", "showsRatio", "sameSnapshot",
            "payload.matureCount == nil, payload.denominator == nil",
            'request.httpMethod = "GET"', "generation == stamp", "onUnauthorized", "func revoke()",
            "var ratioText: String { \"\\(matureCount)/\\(denominator)\" }",
        ]:
            self.assertIn(marker, source, marker)
        self.assertLess(source.index("if status == 422"), source.index("private static func screen"))
        self.assertLess(source.index("if status == 422"), source.index("private static func outingPage"))
        self.assertNotIn('fields["accountId"]', source)
        self.assertNotIn('fields["outingId"]', source)
        self.assertNotIn('case page = "fairness"', source)
        for denied in ["fatalError", "httpMethod = \"POST\"", "\"POST\"", "memberId", "CLLocation", "rendezvous", "randomMatch", "autoJoin", "%"]:
            self.assertNotIn(denied, source)
            self.assertNotIn(denied, view)
        self.assertNotIn("UserDefaults", view)
        self.assertNotIn("restartRestoreSupported = false", source)
        for marker in ['tableName: "CityFairness"', "restoreSameQuery()", "loadOutings()", "nextOutings()", "setForeground", "page.showsRatio", "page.ratioText", "page.outings", "fairness.back", "fairness.notComputable", "fairness.noMatureSample", "fairness.unknown", "fairness.coverage", "fact.missing", "String(count)"]:
            self.assertIn(marker, view)
        evidence = view.split("struct CityFairnessEvidenceView", 1)[1]
        self.assertNotIn("ratioText", evidence)
        self.assertNotIn("showsRatio", evidence)
        self.assertNotIn("loadEvidence", view)
        self.assertNotIn("clearOutings()", view)
        self.assertNotIn("AppSession", view)

    def test_outing_statuses_rows_and_snapshot(self):
        immature = outing_envelope(outing_payload(outings=[outing_row("o1", "first-outing"), outing_row("o2", "nope")]))
        kind, ratio, reasons, shows = classify_outing(200, immature)
        self.assertEqual((kind, ratio, reasons, shows), ("rows", None, ["first-outing", "unknown"], False))
        mature = outing_envelope(outing_payload(maturity="MATURE", outings=[outing_row("o1", "second-outing")]))
        self.assertEqual(classify_outing(200, mature), ("rows", None, ["second-outing"], True))
        poisoned = outing_envelope(outing_payload(matureCount=0, denominator=1, outings=[outing_row()]))
        for status, expected in ((401, "unauthorized"), (403, "forbidden"), (422, "not-computable"), (400, "malformed"), (409, "malformed")):
            self.assertEqual(classify_outing(status, poisoned)[:2], (expected, None))
        for code in ("city_fairness_parameter", "city_fairness_event"):
            body = outing_envelope({"errorCode": code, "status": None, "queryId": "q1"}, code=503, msg="unavailable")
            self.assertEqual(classify_outing(503, body)[:2], ("unavailable", None))
        select_read = {"errorCode": "unavailable", "missing": ["city_fairness_read"], "status": None, "matureCount": None, "denominator": None, "queryId": "q-self"}
        self.assertEqual(classify_outing(503, outing_envelope(select_read, code=503, msg="unavailable"))[:2], ("unavailable", None))
        self.assertEqual(classify(503, outing_envelope(select_read, code=503, msg="unavailable")), ("unavailable", None))
        self.assertEqual(classify_outing(503, outing_envelope({"errorCode": "city_fairness_read", "missing": ["city_fairness_read"], "status": None}, code=503))[0], "malformed")
        self.assertEqual(classify_outing(503, outing_envelope({"errorCode": "unavailable", "missing": [], "status": None}, code=503))[0], "malformed")
        self.assertEqual(classify_outing(503, outing_envelope({"errorCode": "unavailable", "missing": ["city_fairness_read"], "status": None, "matureCount": 0}, code=503))[0], "malformed")
        self.assertEqual(classify_outing(503, outing_envelope({"errorCode": "other"}, code=503))[:2], ("malformed", None))
        self.assertEqual(classify_outing(200, b"")[:2], ("malformed", None))
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(), candidate=False))[0], "malformed")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(), code=201))[0], "malformed")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(), msg="ok"))[0], "malformed")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(accountId=8)))[0], "discard")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(queryId="other")))[0], "discard")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(asOf=2)))[0], "discard")
        self.assertIsNone(classify_outing(200, outing_envelope(outing_payload(accountId=8)))[1])
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(outings=[outing_row("o1"), outing_row("o1")])))[0], "malformed")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(cursor="9")))[0], "malformed")
        self.assertEqual(classify_outing(200, outing_envelope(outing_payload(cursor="2")), requested_cursor="2")[0], "rows")
        self.assertIsNone(classify_outing(422, outing_envelope(outing_payload(matureCount=0, denominator=1)))[1])
        current = outing_payload(outings=[outing_row("o1")])
        changed = outing_payload(factRevision=9, outings=[outing_row("o2")])
        self.assertEqual(keep_outing_page(current, changed)["factRevision"], 4)
        self.assertEqual(keep_outing_page(current, outing_payload(metricVersion="fairness.v2"))["metricVersion"], "fairness.v1")
        self.assertEqual(keep_outing_page(current, outing_payload(queryId="other"))["queryId"], "q1")
        self.assertEqual(keep_outing_page(current, outing_payload(asOf=2))["asOf"], 1_700_000_000_000)
        self.assertEqual(keep_outing_page(current, outing_payload(nextCursor="2"))["nextCursor"], "2")
        self.assertTrue(same_cursor(None, None))
        self.assertTrue(same_cursor(None, "0"))
        self.assertTrue(same_cursor("0", None))
        self.assertTrue(same_cursor("1", "1"))
        self.assertFalse(same_cursor("1", None))
        self.assertFalse(same_cursor("2", "0"))
        self.assertFalse(same_cursor(None, "00"))
        self.assertEqual(fact_display(None), "missing")
        self.assertEqual(fact_display(0), ("count", 0))
        self.assertNotIn("%", "0")
        self.assertIsNone(own_report_ratio([{"actorId": 7}, {"actorId": 8}], 7, 0, 4))
        self.assertEqual(own_report_ratio([{"actorId": 7}], 7, 0, 4), "0/4")

    def test_published_samples_match_hengyin(self):
        fixtures = ROOT / "Tests/ContractChecks/fixtures"
        loaded = {}
        for name, digest in SAMPLES.items():
            raw = (fixtures / name).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), digest, name)
            self.assertEqual(f"{SAMPLE_SOURCE}/{name}", f"docs/contracts/w20-fairness-samples/{name}")
            loaded[name] = json.loads(raw)
        report = loaded["report-first-page.json"]
        data = report["data"]
        self.assertEqual(classify(200, json.dumps(report).encode()), ("mature", "1/1"))
        self.assertNotIn("%", "1/1")
        self.assertEqual(data["queryId"], "q-self")
        self.assertIsNone(data["cursor"])
        self.assertEqual(data["coverageGaps"], ["revenue", "gps-false-rejections", "safety-tickets", "verification-latency"])
        self.assertEqual(data["groups"][0]["goalCompletions"], 0)
        self.assertEqual(fact_display(data["groups"][0]["goalCompletions"]), ("count", 0))
        for field in ("effectiveGain", "topActorGain", "totalGain", "gpsFalseRejections", "safetyTickets", "merchantVerifications", "merchantVerificationMillis"):
            self.assertIsNone(data["groups"][0][field])
            self.assertEqual(fact_display(data["groups"][0][field]), "missing")
        self.assertEqual(own_report_ratio(data["members"], 7, 1, 1), "1/1")
        empty = loaded["report-empty-mature.json"]["data"]
        self.assertEqual(classify(200, json.dumps(loaded["report-empty-mature.json"]).encode()), ("no-mature-sample", None))
        self.assertEqual(empty["goalCompletions"] if "goalCompletions" in empty else empty["groups"][0]["goalCompletions"], 0)
        self.assertIsNone(empty["cursor"])
        scope = {key: data[key] for key in ("boardId", "regionId", "seasonId", "rulesVersion")}
        first = loaded["outing-first-page.json"]
        kind, ratio, _, _ = classify_outing(200, json.dumps(first).encode(), account_id=7, query_id="q-self", as_of=12000, requested_cursor=None, scope=scope)
        self.assertEqual((kind, ratio), ("rows", None))
        self.assertIsNone(first["data"]["cursor"])
        self.assertEqual(first["data"]["nextCursor"], "1")
        self.assertTrue(same_cursor(None, first["data"]["cursor"]))
        nxt = loaded["outing-next-page.json"]
        self.assertEqual(classify_outing(200, json.dumps(nxt).encode(), account_id=7, query_id="q-self", as_of=12000, requested_cursor="1", scope=scope)[0], "rows")
        self.assertEqual(nxt["data"]["cursor"], "1")
        self.assertTrue(same_cursor("1", nxt["data"]["cursor"]))
        self.assertFalse(same_cursor("1", None))
        for name in ("report-503.json", "outing-503.json"):
            sample = loaded[name]
            raw = json.dumps(sample).encode()
            self.assertEqual(sample["msg"], "unavailable")
            self.assertEqual(sample["data"]["errorCode"], "unavailable")
            self.assertEqual(sample["data"]["missing"], ["city_fairness_read"])
            self.assertIsNone(sample["data"]["status"])
            self.assertEqual(sample["data"]["queryId"], "q-self")
            self.assertIsNone(classify(503, raw)[1])
            self.assertEqual(failure_503(raw), "unavailable")
            self.assertNotIn("%", json.dumps(sample["data"]))

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
