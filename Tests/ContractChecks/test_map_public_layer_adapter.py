"""Wire contract for the iOS public-layer adapter.

The source table is parsed from Core/MapPublicLayerAdapter.swift. The page
machine mirrors that file's FAILED cursor, UNAVAILABLE status, numeric
dedupe, and optional visibility/state/action fields. It does not compile Swift.
"""
import re
import unittest
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "Core" / "MapPublicLayerAdapter.swift"
CONTRACTS = ROOT / "Core" / "MapLayerSourceContracts.swift"
DIGIT = re.compile(r"^[1-9][0-9]*$")
STAMP = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$")
WIRE_STATES = {
    "roam_poi": {"unfound", "found", "pending_redeem"},
    "store": {"open", "closed"},
    "activity": {"notStarted", "running", "completed"},
    "theme": {"recruiting", "selfPlay", "sessions", "open", "closed"},
    "story_node": {"open", "unlocked", "completed"},
}


def source():
    return ADAPTER.read_text(encoding="utf-8")


def client_types(text):
    body = text[text.index("func clientType"):text.index("public static func open")]
    found = {}
    for wire, mapped in re.findall(r'case "([a-z0-9_]+)": return (\.[A-Za-z]+|nil)', body):
        found[wire] = None if mapped == "nil" else mapped[1:]
    return found


def marker_states(text):
    body = text[text.index("func markerState"):text.index("func stateAllowed")]
    found = {}
    for wire, mapped in re.findall(r'case "([A-Za-z_]+)": return \.([A-Za-z]+)', body):
        found[wire] = mapped
    return found


def known_sources(text):
    raw = text[text.index("knownSources = ["):text.index("]", text.index("knownSources = ["))]
    return re.findall(r'"([a-z0-9_]+)"', raw)


def canonical(raw, latitude):
    text = raw.strip()
    if not re.fullmatch(r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?", text):
        raise ValueError("coordinate")
    negative = text.startswith("-")
    body = text[1:] if negative else text
    whole, _, frac = body.partition(".")
    frac = frac.rstrip("0")
    plain = whole if not frac else whole + "." + frac
    significant = plain.replace(".", "").lstrip("0")
    precision = 1 if not significant else len(significant)
    if len(frac) > 8 or precision > 12:
        raise ValueError("coordinate")
    value = Decimal(plain)
    bound = Decimal(90 if latitude else 180)
    if value < -bound or value > bound:
        raise ValueError("coordinate")
    if negative and plain != "0":
        return "-" + plain, -value
    return plain, value


def open_query(viewer, datum, min_lat, max_lat, min_lng, max_lng, layers, limit, sources):
    if viewer <= 0:
        raise ValueError("viewer")
    if datum != "GCJ-02":
        raise ValueError("datum")
    if not 1 <= limit <= 50:
        raise ValueError("limit")
    south, south_v = canonical(min_lat, True)
    north, north_v = canonical(max_lat, True)
    west, west_v = canonical(min_lng, False)
    east, east_v = canonical(max_lng, False)
    if south_v > north_v or west_v > east_v:
        raise ValueError("bbox")
    if (north_v - south_v) * (east_v - west_v) > 1:
        raise ValueError("area")
    if not 1 <= len(layers) <= 5 or len(set(layers)) != len(layers):
        raise ValueError("layers")
    for layer in layers:
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,31}", layer) or layer not in sources:
            raise ValueError("layers")
    fingerprint = "\n".join([datum, south, north, west, east, str(limit), ",".join(layers)])
    return {
        "viewer": viewer,
        "fingerprint": fingerprint,
        "limit": limit,
        "layers": list(layers),
        "minLat": south,
        "maxLat": north,
        "minLng": west,
        "maxLng": east,
        "token": 0,
        "cursor": None,
        "complete": False,
        "pages": [{"source": layer, "status": "idle", "reason": None, "read": None, "items": []} for layer in layers],
    }


def request(session):
    session = dict(session)
    session["pages"] = [dict(page, items=list(page["items"])) for page in session["pages"]]
    session["token"] = session["token"] + 1
    fields = [
        '"datum":"GCJ-02"',
        f'"minLat":{session["minLat"]}',
        f'"maxLat":{session["maxLat"]}',
        f'"minLng":{session["minLng"]}',
        f'"maxLng":{session["maxLng"]}',
        f'"limit":{session["limit"]}',
        '"layers":[' + ",".join(f'"{layer}"' for layer in session["layers"]) + "]",
    ]
    if session["cursor"] is not None:
        fields.append('"cursor":"' + session["cursor"] + '"')
    issued = {
        "attempt": session["token"],
        "viewer": session["viewer"],
        "fingerprint": session["fingerprint"],
        "cursor": session["cursor"],
        "body": "{" + ",".join(fields) + "}",
    }
    return session, issued


def version_above(incoming, current):
    incoming_digits = DIGIT.fullmatch(incoming) is not None
    current_digits = DIGIT.fullmatch(current) is not None
    if incoming_digits and current_digits:
        if len(incoming) != len(current):
            return len(incoming) > len(current)
        return incoming >= current
    return incoming >= current


def prefer(current, incoming):
    new = incoming["visibilityVersion"]
    old = current["visibilityVersion"]
    if new is None:
        return current
    if old is None:
        return incoming
    return incoming if version_above(new, old) else current


def version_allowed(version, source):
    if source == "roam_poi":
        return DIGIT.fullmatch(version or "") is not None
    if source in ("store", "activity", "theme", "story_node"):
        return STAMP.fullmatch(version or "") is not None
    return False


def parent_domain_allowed(item):
    source = item["source"]
    if source == "theme":
        topic_id = item.get("topicID")
        node_id = item.get("nodeID")
        if topic_id is not None and topic_id != item["sourceID"]:
            return False
        if node_id is not None and node_id <= 0:
            return False
        return True
    if source == "story_node":
        topic_id = item.get("topicID")
        chapter_id = item.get("chapterID")
        node_id = item.get("nodeID")
        if not isinstance(topic_id, int) or topic_id <= 0:
            return False
        if not isinstance(chapter_id, int) or chapter_id <= 0:
            return False
        if node_id is not None and node_id != item["sourceID"]:
            return False
        return True
    return True


def state_allowed(state, source):
    return state in WIRE_STATES.get(source, ()) and state != "available"


def dedupe(items):
    by_id = {}
    for item in items:
        current = by_id.get(item["sourceID"])
        by_id[item["sourceID"]] = item if current is None else prefer(current, item)
    return [by_id[key] for key in sorted(by_id)]


def accept(session, issued, payload, mapping):
    if issued["attempt"] != session["token"] or issued["viewer"] != session["viewer"] or issued["fingerprint"] != session["fingerprint"]:
        return "stale", session
    if payload.get("datum") != "GCJ-02":
        return "rejected", session
    if "aggregatedQueryEnabled" in payload and payload.get("aggregatedQueryEnabled") is not False:
        return "rejected", session
    layers = payload.get("layers")
    if not isinstance(layers, list) or len(layers) != len(session["layers"]):
        return "rejected", session
    pages = [dict(page, items=list(page["items"])) for page in session["pages"]]
    failed = False
    for index, layer in enumerate(layers):
        if not isinstance(layer, dict) or layer.get("sourceType") != session["layers"][index] or not isinstance(layer.get("status"), str):
            return "rejected", session
        raw_items = layer.get("items")
        if not isinstance(raw_items, list):
            return "rejected", session
        status = layer["status"]
        if status in ("FAILED", "UNAVAILABLE"):
            if raw_items:
                return "rejected", session
            if status == "FAILED":
                failed = True
            pages[index]["status"] = "failed" if status == "FAILED" else "unavailable"
            pages[index]["reason"] = layer.get("reason")
            pages[index]["read"] = (layer.get("capabilities") or {}).get("read")
            continue
        if status != "OK":
            return "rejected", session
        parsed = []
        blocked = None
        for raw in raw_items:
            if not isinstance(raw, dict) or raw.get("sourceType") != session["layers"][index]:
                return "rejected", session
            source_id = raw.get("sourceId")
            if not isinstance(source_id, int) or isinstance(source_id, bool) or source_id <= 0:
                return "rejected", session
            if not isinstance(raw.get("name"), str):
                return "rejected", session
            topic_id = raw.get("topicId")
            if topic_id is not None and (not isinstance(topic_id, int) or isinstance(topic_id, bool) or topic_id <= 0):
                return "rejected", session
            chapter_id = raw.get("chapterId")
            if chapter_id is not None and (not isinstance(chapter_id, int) or isinstance(chapter_id, bool) or chapter_id <= 0):
                return "rejected", session
            node_id = raw.get("nodeId")
            if node_id is not None and (not isinstance(node_id, int) or isinstance(node_id, bool) or node_id <= 0):
                return "rejected", session
            version = raw["visibilityVersion"] if "visibilityVersion" in raw else None
            if isinstance(version, str):
                version = version.strip() or None
            elif isinstance(version, int) and not isinstance(version, bool):
                version = str(version)
            else:
                version = None
            state = raw.get("visualState")
            actions = raw["actions"] if "actions" in raw else None
            item_row = {
                "source": session["layers"][index],
                "sourceID": source_id,
                "name": raw["name"],
                "latitude": str(raw.get("latitude")),
                "longitude": str(raw.get("longitude")),
                "visibilityVersion": version,
                "visualState": state,
                "actions": actions,
                "topicID": topic_id,
                "chapterID": chapter_id,
                "nodeID": node_id,
                "topicName": raw.get("topicName"),
                "chapterTitle": raw.get("chapterTitle"),
            }
            if blocked is None:
                if not version_allowed(version, session["layers"][index]):
                    blocked = "VISIBILITY_VERSION_ABSENT"
                elif not state_allowed(state, session["layers"][index]):
                    blocked = "VISUAL_STATE_ABSENT"
                elif actions is not None and "register" in actions:
                    blocked = "ACTION_REJECTED"
                elif not parent_domain_allowed(item_row):
                    blocked = "STORY_NODE_PARENT_ABSENT" if session["layers"][index] == "story_node" else "THEME_TOPIC_ID_MISMATCH"
            parsed.append(item_row)
        if blocked:
            failed = True
            pages[index]["status"] = "failed"
            pages[index]["reason"] = blocked
            pages[index]["read"] = (layer.get("capabilities") or {}).get("read")
            continue
        pages[index]["status"] = "ok"
        pages[index]["reason"] = layer.get("reason")
        pages[index]["read"] = (layer.get("capabilities") or {}).get("read")
        pages[index]["items"] = dedupe(pages[index]["items"] + parsed)
    applied = dict(session)
    applied["pages"] = pages
    if failed:
        applied["cursor"] = issued["cursor"]
        applied["complete"] = False
    elif isinstance(payload.get("nextCursor"), str) and payload["nextCursor"]:
        applied["cursor"] = payload["nextCursor"]
        applied["complete"] = False
    elif "nextCursor" not in payload or payload.get("nextCursor") is None:
        applied["cursor"] = None
        applied["complete"] = True
    else:
        return "rejected", session
    applied["mapping"] = mapping
    return "applied", applied


def ordering_int(version):
    if DIGIT.fullmatch(version or ""):
        return int(version)
    if STAMP.fullmatch(version or ""):
        return int(re.sub(r"\D", "", version))
    return None


def exposed(item):
    names = item.get("actions") or []
    if item["source"] == "store" and "navigate" in names and "register" not in names:
        return {"navigate"}
    return set()


def ready(session, markers):
    mapping = session["mapping"]
    rows = []
    for index, page in enumerate(session["pages"]):
        if page["status"] not in ("ok", "failed"):
            continue
        for item in page["items"]:
            client = mapping.get(item["source"])
            version = ordering_int(item.get("visibilityVersion"))
            state = markers.get(item.get("visualState"))
            if client is None or version is None or state is None:
                continue
            if not version_allowed(item.get("visibilityVersion"), item["source"]):
                continue
            if not state_allowed(item.get("visualState"), item["source"]):
                continue
            if not parent_domain_allowed(item):
                continue
            rows.append({
                "type": client,
                "id": str(item["sourceID"]),
                "version": version,
                "wireVersion": item["visibilityVersion"],
                "state": state,
                "wireState": item["visualState"],
                "actions": exposed(item),
                "sort": f"{index:02d}:{item['sourceID']:020d}",
                "layerRead": page["read"],
            })
    return sorted(rows, key=lambda row: (row["sort"], row["type"], row["id"]))


def sample_box():
    return ("31.220000", "31.24", "121.4600", "121.49")


class MapPublicLayerAdapterContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = source()
        cls.mapping = client_types(cls.text)
        cls.sources = known_sources(cls.text)
        cls.markers = marker_states(cls.text)
        cls.contracts = CONTRACTS.read_text(encoding="utf-8")

    def test_source_table_comes_from_the_adapter_and_keeps_story_node(self):
        self.assertEqual(self.mapping["story_node"], "storyNode")
        self.assertEqual(self.mapping["roam_poi"], "roamPOI")
        self.assertEqual(self.mapping["store"], "store")
        self.assertEqual(self.mapping["activity"], "registrableActivity")
        self.assertEqual(self.mapping["theme"], "themeNode")
        self.assertNotIn("sideQuest", self.mapping.values())
        self.assertNotIn('"sideQuest"', self.text)
        self.assertNotIn("return .sideQuest", self.text)
        self.assertIn("story_node", self.sources)
        self.assertNotIn("layers.sorted", self.text)
        self.assertEqual(self.markers, {
            "unfound": "locked", "found": "completed", "pending_redeem": "active",
            "open": "interactive", "closed": "unavailable",
            "notStarted": "locked", "running": "active", "completed": "completed",
            "recruiting": "active", "selfPlay": "interactive", "sessions": "interactive",
            "unlocked": "active",
        })
        self.assertNotIn("standard", self.markers.values())
        self.assertNotIn("visibilityVersion = 1", self.text)
        self.assertNotIn("visibilityVersion: 1", self.text)
        self.assertNotIn(".standard", self.text)
        self.assertIn("VISIBILITY_VERSION_ABSENT", self.text)
        self.assertIn("VISUAL_STATE_ABSENT", self.text)
        self.assertIn("ACTION_REJECTED", self.text)
        self.assertIn("STORY_NODE_PARENT_ABSENT", self.text)
        self.assertIn("THEME_TOPIC_ID_MISMATCH", self.text)
        self.assertNotIn("URLSession", self.text)
        self.assertNotIn("CLLocation", self.text)
        self.assertNotIn("AppSession", self.text)
        self.assertNotIn("projected(to:", self.text)
        self.assertNotIn("aggregatedQueryEnabled = true", self.text)
        self.assertIn("static let aggregatedQueryEnabled = false", self.contracts)
        self.assertIn('path = "/api/map/public-layers"', self.text)
        self.assertIn("MapLayerMerge.merge", self.text)
        failed = self.text[self.text.index("if failed"):self.text.index("} else if let nextCursor")]
        self.assertIn("request.cursor", failed)
        self.assertNotIn("nextCursor", failed)
        unavailable = self.text[self.text.index('case "UNAVAILABLE"'):self.text.index('case "OK"')]
        self.assertIn(".unavailable", unavailable)
        self.assertNotIn(".ok", unavailable)
        actions = self.text[self.text.index("func exposedActions"):self.text.index("func unpublished")]
        self.assertNotIn("read", actions)
        self.assertIn('names.contains("navigate")', actions)
        self.assertIn('names.contains("register")', actions)

    def test_request_uses_gcj_bbox_caller_order_and_a_limit_of_one_to_fifty(self):
        south, north, west, east = sample_box()
        for bad in (
            (0, "GCJ-02", south, north, west, east, ["store"], 10),
            (7, "WGS84", south, north, west, east, ["store"], 10),
            (7, "GCJ-02", south, north, west, east, ["store"], 0),
            (7, "GCJ-02", south, north, west, east, ["store"], 51),
            (7, "GCJ-02", north, south, west, east, ["store"], 10),
            (7, "GCJ-02", "30", "32", "120", "122", ["store"], 10),
            (7, "GCJ-02", south, north, west, east, ["sideQuest"], 10),
            (7, "GCJ-02", south, north, west, east, ["store", "store"], 10),
            (7, "GCJ-02", south, north, west, east, ["store", "roam_poi", "activity", "theme", "story_node", "store"], 10),
        ):
            with self.assertRaises(ValueError):
                open_query(*bad, self.sources)
        session = open_query(7, "GCJ-02", south, north, west, east, ["roam_poi", "story_node", "store"], 50, self.sources)
        self.assertEqual(session["layers"], ["roam_poi", "story_node", "store"])
        self.assertEqual(session["minLat"], "31.22")
        session, issued = request(session)
        self.assertNotIn("cursor", issued["body"])
        self.assertIn('"datum":"GCJ-02"', issued["body"])
        self.assertLess(issued["body"].index("roam_poi"), issued["body"].index("story_node"))
        self.assertLess(issued["body"].index("story_node"), issued["body"].index("store"))
        self.assertIn('"limit":50', issued["body"])
        self.assertIn("pageLimit = 1...50", self.text)

    def test_failed_keeps_the_sent_cursor_and_unavailable_is_not_an_empty_page(self):
        south, north, west, east = sample_box()
        session = open_query(7, "GCJ-02", south, north, west, east, ["roam_poi", "story_node"], 10, self.sources)
        session["cursor"] = "page-1"
        session["token"] = 4
        issued = {"attempt": 4, "viewer": 7, "fingerprint": session["fingerprint"], "cursor": "page-1"}
        payload = {
            "datum": "GCJ-02",
            "nextCursor": "page-2",
            "layers": [
                {"sourceType": "roam_poi", "status": "FAILED", "reason": "SOURCE_FAILED", "capabilities": {"read": True, "count": False, "cluster": False}, "items": []},
                {"sourceType": "story_node", "status": "UNAVAILABLE", "reason": "STORY_NODE_NOT_PROVEN_PUBLIC", "capabilities": {"read": False, "count": False, "cluster": False}, "items": []},
            ],
        }
        kind, applied = accept(session, issued, payload, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(applied["cursor"], "page-1")
        self.assertFalse(applied["complete"])
        self.assertEqual(applied["pages"][0]["status"], "failed")
        self.assertEqual(applied["pages"][1]["status"], "unavailable")
        self.assertFalse(applied["pages"][1]["status"] == "ok" and applied["pages"][1]["items"] == [])
        empty = {
            "datum": "GCJ-02",
            "layers": [
                {"sourceType": "roam_poi", "status": "OK", "capabilities": {"read": True}, "items": []},
                {"sourceType": "story_node", "status": "UNAVAILABLE", "reason": "STORY_NODE_NOT_PROVEN_PUBLIC", "capabilities": {"read": False}, "items": []},
            ],
        }
        kind, done = accept(session, issued, empty, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertTrue(done["pages"][0]["status"] == "ok" and done["pages"][0]["items"] == [])
        self.assertEqual(done["pages"][1]["status"], "unavailable")
        self.assertIsNone(done["cursor"])
        self.assertTrue(done["complete"])

    def test_dedupe_is_source_plus_id_and_order_is_numeric(self):
        south, north, west, east = sample_box()
        session = open_query(7, "GCJ-02", south, north, west, east, ["store", "roam_poi"], 10, self.sources)
        session, issued = request(session)
        def item(source, source_id, **extra):
            version = "4100000004" if source == "roam_poi" else "2026-03-01T08:00:00"
            state = "unfound" if source == "roam_poi" else "open"
            row = {"sourceType": source, "sourceId": source_id, "name": "点", "latitude": "31.23", "longitude": "121.47",
                   "visibilityVersion": version, "visualState": state, "actions": ["navigate"] if source == "store" else []}
            row.update(extra)
            return row
        payload = {
            "datum": "GCJ-02",
            "nextCursor": "next",
            "layers": [
                {"sourceType": "store", "status": "OK", "capabilities": {"read": True, "count": False, "cluster": False},
                 "items": [item("store", 10), item("store", 2), item("store", 2, name="重复")]},
                {"sourceType": "roam_poi", "status": "OK", "capabilities": {"read": True, "count": False, "cluster": False},
                 "items": [item("roam_poi", 2)]},
            ],
        }
        kind, applied = accept(session, issued, payload, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual([row["sourceID"] for row in applied["pages"][0]["items"]], [2, 10])
        self.assertEqual(applied["pages"][0]["items"][0]["name"], "重复")
        self.assertEqual(applied["pages"][0]["items"][0]["visibilityVersion"], "2026-03-01T08:00:00")
        mapped = ready(applied, self.markers)
        self.assertEqual([(row["type"], row["id"]) for row in mapped], [("store", "2"), ("store", "10"), ("roamPOI", "2")])
        self.assertEqual(len({(row["type"], row["id"]) for row in mapped}), 3)

    def test_stale_account_or_query_does_not_apply(self):
        south, north, west, east = sample_box()
        session = open_query(7, "GCJ-02", south, north, west, east, ["store"], 10, self.sources)
        session, issued = request(session)
        payload = {"datum": "GCJ-02", "aggregatedQueryEnabled": False, "layers": [{"sourceType": "store", "status": "OK", "items": [
            {"sourceType": "store", "sourceId": 3, "name": "店", "latitude": "31.23", "longitude": "121.47",
             "visibilityVersion": "2026-03-01T08:00:00", "visualState": "open", "actions": []}
        ]}]}
        late = dict(issued, attempt=issued["attempt"] - 1)
        kind, kept = accept(session, late, payload, self.mapping)
        self.assertEqual(kind, "stale")
        self.assertEqual(kept["pages"][0]["status"], "idle")
        other_account = dict(issued, viewer=8)
        kind, kept = accept(session, other_account, payload, self.mapping)
        self.assertEqual(kind, "stale")
        self.assertEqual(kept["cursor"], None)
        moved = open_query(7, "GCJ-02", south, north, "121.47", east, ["store"], 10, self.sources)
        moved["token"] = session["token"] + 1
        kind, kept = accept(moved, issued, payload, self.mapping)
        self.assertEqual(kind, "stale")
        self.assertEqual(kept["pages"][0]["items"], [])

    def test_null_version_fails_the_layer_without_advancing_the_cursor(self):
        south, north, west, east = sample_box()
        session = open_query(7, "GCJ-02", south, north, west, east, ["roam_poi", "store", "activity"], 10, self.sources)
        session["cursor"] = "same"
        session["token"] = 3
        issued = {"attempt": 3, "viewer": 7, "fingerprint": session["fingerprint"], "cursor": "same"}
        def point(source, source_id, version, state, actions):
            return {"sourceType": source, "sourceId": source_id, "name": "点", "latitude": "31.23", "longitude": "121.47",
                    "visibilityVersion": version, "visualState": state, "actions": actions}
        payload = {
            "datum": "GCJ-02",
            "aggregatedQueryEnabled": False,
            "nextCursor": "advanced",
            "layers": [
                {"sourceType": "roam_poi", "status": "OK", "capabilities": {"read": True}, "items": [
                    point("roam_poi", 6, None, "found", []),
                    point("roam_poi", 7, "4100000007", "unfound", []),
                ]},
                {"sourceType": "store", "status": "OK", "capabilities": {"read": True}, "items": [
                    point("store", 4, "2026-03-01T08:00:00", "closed", []),
                    point("store", 56, "2026-03-02T09:00:00", "open", ["navigate"]),
                ]},
                {"sourceType": "activity", "status": "OK", "capabilities": {"read": True}, "items": [
                    point("activity", 4, "2026-04-01T10:00:00", "notStarted", []),
                    point("activity", 16, "2026-04-02T11:00:00", "running", ["navigate"]),
                    point("activity", 17, "2026-04-03T12:00:00", "completed", []),
                ]},
            ],
        }
        kind, applied = accept(session, issued, payload, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(applied["cursor"], "same")
        self.assertFalse(applied["complete"])
        self.assertEqual(applied["pages"][0]["status"], "failed")
        self.assertEqual(applied["pages"][0]["reason"], "VISIBILITY_VERSION_ABSENT")
        self.assertEqual(applied["pages"][0]["items"], [])
        self.assertNotEqual(applied["pages"][1]["items"][0]["visibilityVersion"], "1")
        self.assertEqual(applied["pages"][1]["items"][1]["visibilityVersion"], "2026-03-02T09:00:00")
        mapped = ready(applied, self.markers)
        self.assertEqual([(row["type"], row["id"], row["wireState"], row["state"], tuple(sorted(row["actions"]))) for row in mapped], [
            ("store", "4", "closed", "unavailable", ()),
            ("store", "56", "open", "interactive", ("navigate",)),
            ("registrableActivity", "4", "notStarted", "locked", ()),
            ("registrableActivity", "16", "running", "active", ()),
            ("registrableActivity", "17", "completed", "completed", ()),
        ])
        self.assertTrue(all(row["layerRead"] for row in mapped))
        self.assertNotIn("register", {action for row in mapped for action in row["actions"]})
        self.assertNotIn("sideQuest", [row["type"] for row in mapped])

        absent = {"datum": "GCJ-02", "nextCursor": "nope", "layers": [
            {"sourceType": "roam_poi", "status": "FAILED", "reason": "VISIBILITY_VERSION_ABSENT", "items": []},
            {"sourceType": "store", "status": "OK", "capabilities": {"read": True}, "items": [
                point("store", 4, "map-public-v1", "open", ["navigate"]),
            ]},
            {"sourceType": "activity", "status": "OK", "capabilities": {"read": True}, "items": [
                point("activity", 4, "2026-04-01T10:00:00", "available", []),
            ]},
        ]}
        kind, blocked = accept(session, issued, absent, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(blocked["cursor"], "same")
        self.assertEqual(blocked["pages"][0]["reason"], "VISIBILITY_VERSION_ABSENT")
        self.assertEqual(blocked["pages"][1]["reason"], "VISIBILITY_VERSION_ABSENT")
        self.assertEqual(blocked["pages"][1]["items"], [])
        self.assertEqual(blocked["pages"][2]["reason"], "VISUAL_STATE_ABSENT")
        registered = {"datum": "GCJ-02", "layers": [
            {"sourceType": "roam_poi", "status": "OK", "items": [point("roam_poi", 1, "4100000001", "pending_redeem", [])]},
            {"sourceType": "store", "status": "OK", "capabilities": {"read": True}, "items": [
                point("store", 4, "2026-03-01T08:00:00", "open", ["register"]),
            ]},
            {"sourceType": "activity", "status": "UNAVAILABLE", "reason": "NO_AUTHORITATIVE_PUBLIC_QUERY", "items": []},
        ]}
        # activity in this session is a readable source, so UNAVAILABLE is a legal status, not an empty OK page.
        kind, rejected = accept(session, issued, registered, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(rejected["pages"][1]["reason"], "ACTION_REJECTED")
        self.assertEqual(rejected["cursor"], "same")
        self.assertEqual(ready(rejected, self.markers)[0]["wireState"], "pending_redeem")
        self.assertEqual(ready(rejected, self.markers)[0]["actions"], set())
        self.assertNotIn("register", ready(rejected, self.markers)[0]["actions"])

    def test_older_visibility_version_does_not_replace_a_newer_item(self):
        south, north, west, east = sample_box()
        session = open_query(7, "GCJ-02", south, north, west, east, ["store"], 10, self.sources)
        session, issued = request(session)
        first = {"datum": "GCJ-02", "nextCursor": "c2", "layers": [{"sourceType": "store", "status": "OK", "capabilities": {"read": True}, "items": [
            {"sourceType": "store", "sourceId": 4, "name": "新", "latitude": "31.23", "longitude": "121.47",
             "visibilityVersion": "2026-04-01T10:00:00", "visualState": "open", "actions": ["navigate"]}
        ]}]}
        kind, applied = accept(session, issued, first, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(applied["cursor"], "c2")
        applied, issued = request(applied)
        older = {"datum": "GCJ-02", "layers": [{"sourceType": "store", "status": "OK", "capabilities": {"read": True}, "items": [
            {"sourceType": "store", "sourceId": 4, "name": "旧", "latitude": "31.23", "longitude": "121.47",
             "visibilityVersion": "2026-03-01T08:00:00", "visualState": "closed", "actions": []}
        ]}]}
        kind, applied = accept(applied, issued, older, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(applied["pages"][0]["items"][0]["name"], "新")
        self.assertEqual(applied["pages"][0]["items"][0]["visibilityVersion"], "2026-04-01T10:00:00")
        self.assertEqual(ready(applied, self.markers)[0]["version"], 20260401100000)
        self.assertEqual(ready(applied, self.markers)[0]["actions"], {"navigate"})
        roam = open_query(7, "GCJ-02", south, north, west, east, ["roam_poi"], 10, self.sources)
        roam, issued = request(roam)
        newer = {"datum": "GCJ-02", "nextCursor": "r2", "layers": [{"sourceType": "roam_poi", "status": "OK", "items": [
            {"sourceType": "roam_poi", "sourceId": 1, "name": "新点", "latitude": "31.23", "longitude": "121.47",
             "visibilityVersion": "4100000002", "visualState": "found", "actions": []}
        ]}]}
        kind, roam = accept(roam, issued, newer, self.mapping)
        roam, issued = request(roam)
        stale_version = {"datum": "GCJ-02", "layers": [{"sourceType": "roam_poi", "status": "OK", "items": [
            {"sourceType": "roam_poi", "sourceId": 1, "name": "旧点", "latitude": "31.23", "longitude": "121.47",
             "visibilityVersion": "4100000001", "visualState": "unfound", "actions": ["navigate"]}
        ]}]}
        kind, roam = accept(roam, issued, stale_version, self.mapping)
        self.assertEqual(roam["pages"][0]["items"][0]["visibilityVersion"], "4100000002")
        self.assertEqual(ready(roam, self.markers)[0]["version"], 4100000002)
        self.assertEqual(ready(roam, self.markers)[0]["actions"], set())

    def test_zero_and_negative_ids_are_rejected(self):
        south, north, west, east = sample_box()
        session = open_query(7, "GCJ-02", south, north, west, east, ["store"], 1, self.sources)
        session, issued = request(session)
        for source_id in (0, -3):
            payload = {"datum": "GCJ-02", "layers": [{"sourceType": "store", "status": "OK", "items": [
                {"sourceType": "store", "sourceId": source_id, "name": "店", "latitude": "31.23", "longitude": "121.47"}
            ]}]}
            kind, kept = accept(session, issued, payload, self.mapping)
            self.assertEqual(kind, "rejected")
            self.assertEqual(kept["pages"][0]["status"], "idle")

    def test_story_node_stays_unavailable_and_side_quest_is_rejected(self):
        south, north, west, east = sample_box()
        with self.assertRaises(ValueError):
            open_query(7, "GCJ-02", south, north, west, east, ["sideQuest"], 10, self.sources)
        session = open_query(7, "GCJ-02", south, north, west, east, ["story_node", "theme"], 10, self.sources)
        session, issued = request(session)
        bad_version = {"datum": "GCJ-02", "nextCursor": "c2", "layers": [
            {"sourceType": "story_node", "status": "OK", "items": [
                {"sourceType": "story_node", "sourceId": 8, "topicId": 100, "chapterId": 200, "name": "节点", "latitude": "31.23", "longitude": "121.47",
                 "visibilityVersion": "1", "visualState": "open", "actions": []}
            ]},
            {"sourceType": "theme", "status": "UNAVAILABLE", "reason": "NO_AUTHORITATIVE_PUBLIC_QUERY", "items": []},
        ]}
        kind, failed_ver = accept(session, issued, bad_version, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(failed_ver["pages"][0]["status"], "failed")
        self.assertEqual(failed_ver["pages"][0]["reason"], "VISIBILITY_VERSION_ABSENT")
        self.assertIsNone(failed_ver["cursor"])

        missing_parent = {"datum": "GCJ-02", "nextCursor": "c2", "layers": [
            {"sourceType": "story_node", "status": "OK", "items": [
                {"sourceType": "story_node", "sourceId": 8, "name": "孤立节点", "latitude": "31.23", "longitude": "121.47",
                 "visibilityVersion": "2026-05-01T10:00:00", "visualState": "open", "actions": []}
            ]},
            {"sourceType": "theme", "status": "OK", "items": [
                {"sourceType": "theme", "sourceId": 100, "topicId": 100, "nodeId": 8, "name": "外滩暗线", "latitude": "31.23", "longitude": "121.47",
                 "visibilityVersion": "2026-05-01T09:00:00", "visualState": "selfPlay", "actions": []}
            ]},
        ]}
        kind, failed_parent = accept(session, issued, missing_parent, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(failed_parent["pages"][0]["status"], "failed")
        self.assertEqual(failed_parent["pages"][0]["reason"], "STORY_NODE_PARENT_ABSENT")
        self.assertEqual(failed_parent["pages"][1]["status"], "ok")
        self.assertEqual([r["type"] for r in ready(failed_parent, self.markers)], ["themeNode"])

        valid_both = {"datum": "GCJ-02", "nextCursor": "c3", "layers": [
            {"sourceType": "story_node", "status": "OK", "capabilities": {"read": True}, "items": [
                {"sourceType": "story_node", "sourceId": 8, "topicId": 100, "chapterId": 200, "nodeId": 8,
                 "topicName": "外滩暗线", "chapterTitle": "第一章", "name": "海关钟楼", "latitude": "31.23", "longitude": "121.47",
                 "visibilityVersion": "2026-05-01T10:00:00", "visualState": "unlocked", "actions": []}
            ]},
            {"sourceType": "theme", "status": "OK", "capabilities": {"read": True}, "items": [
                {"sourceType": "theme", "sourceId": 100, "topicId": 100, "nodeId": 8, "name": "外滩暗线", "latitude": "31.23", "longitude": "121.47",
                 "visibilityVersion": "2026-05-01T09:00:00", "visualState": "selfPlay", "actions": []}
            ]},
        ]}
        kind, applied_ok = accept(session, issued, valid_both, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(applied_ok["cursor"], "c3")
        mapped = ready(applied_ok, self.markers)
        self.assertEqual([(r["type"], r["id"], r["state"], r["actions"]) for r in mapped], [
            ("storyNode", "8", "active", set()),
            ("themeNode", "100", "interactive", set()),
        ])
        self.assertNotIn("sideQuest", [row["type"] for row in mapped])

        unavailable = {"datum": "GCJ-02", "aggregatedQueryEnabled": False, "layers": [
            {"sourceType": "story_node", "status": "UNAVAILABLE", "reason": "STORY_NODE_NOT_PROVEN_PUBLIC", "capabilities": {"read": False}, "items": []},
            {"sourceType": "theme", "status": "UNAVAILABLE", "reason": "NO_AUTHORITATIVE_PUBLIC_QUERY", "capabilities": {"read": False}, "items": []},
        ]}
        kind, applied = accept(session, issued, unavailable, self.mapping)
        self.assertEqual(kind, "applied")
        self.assertEqual(applied["pages"][0]["status"], "unavailable")
        self.assertFalse(applied["pages"][0]["status"] == "ok")
        self.assertEqual(ready(applied, self.markers), [])
        turned_on = {"datum": "GCJ-02", "aggregatedQueryEnabled": True, "layers": unavailable["layers"]}
        self.assertEqual(accept(session, issued, turned_on, self.mapping)[0], "rejected")


if __name__ == "__main__":
    unittest.main()
