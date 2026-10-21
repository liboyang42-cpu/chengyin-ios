"""Caller contract for the public-layer map entry.

Parses the Swift caller, transport, and composition gate. The generation
machine below is the caller fence: a late page or detail from account A or
query N must not apply after the account or the query moves on.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class Fence:
    def __init__(self):
        self.account = None
        self.account_g = 0
        self.query_g = 0
        self.detail_g = 0
        self.token = 0
        self.applied = None
        self.detail = None

    def note_account(self, account):
        if account == self.account:
            return
        self.account = account
        self.account_g += 1
        self.query_g += 1
        self.detail_g += 1
        self.applied = None
        self.detail = None

    def submit(self):
        self.query_g += 1
        self.detail_g += 1
        self.detail = None
        self.token += 1
        return (self.account_g, self.query_g, self.detail_g, self.token)

    def accept_page(self, account_g, query_g, token):
        if account_g != self.account_g or query_g != self.query_g or token != self.token:
            return "dropped"
        self.applied = token
        return "applied"

    def open_detail(self):
        self.detail_g += 1
        return (self.account_g, self.query_g, self.detail_g)

    def accept_detail(self, account_g, query_g, detail_g, text):
        if account_g != self.account_g or query_g != self.query_g or detail_g != self.detail_g:
            return "dropped"
        self.detail = text
        return "shown"

    def returned(self):
        self.detail_g += 1
        self.query_g += 1
        self.detail = None
        self.token += 1
        return (self.account_g, self.query_g, self.token)


def detail(kind, capabilities, item_id):
    if item_id <= 0:
        return None
    if kind == "roamPOI":
        return ("cityNode", item_id)
    if kind == "store":
        return ("merchant", item_id) if capabilities == {"navigate"} else None
    if kind == "registrableActivity":
        return ("activity", item_id)
    return None


class MapPublicLayerCallerContracts(unittest.TestCase):
    def setUp(self):
        self.caller = read("Core/MapPublicLayerCaller.swift")
        self.service = read("Core/SearchMapService.swift")
        self.reading = read("Core/SearchMapReading.swift")
        self.bridge = read("Core/MapVisualHostBridge.swift")
        self.adapter = read("Core/MapPublicLayerAdapter.swift")
        self.root = read("App/AppCompositionRoot.swift")
        self.entry = read("App/SessionGlobalSearchView.swift")
        self.search = read("App/GlobalSearchView.swift")
        self.hub = read("App/MapCoreEntryHubView.swift")
        self.contracts = read("Core/MapLayerSourceContracts.swift")

    def test_chain_uses_the_existing_request_and_projection(self):
        for marker in [
            "MapPublicLayerAdapter.open",
            "MapPublicLayerAdapter.replace",
            "MapPublicLayerAdapter.request",
            "MapPublicLayerAdapter.accept(current",
            "MapPublicLayerAdapter.readyItems",
            "projectAcceptedPublicLayers",
            "MapLayerFeature.aggregatedQueryEnabled == false",
            'contains("aggregatedQueryEnabled")',
        ]:
            self.assertIn(marker, self.caller)
        post = self.caller.index("transport.post")
        self.assertLess(post, self.caller.index("MapPublicLayerAdapter.accept(current"))
        self.assertIn("try projectAnnotations(items: MapPublicLayerAdapter.readyItems(in: session)", self.bridge)
        self.assertIn("let merged = MapLayerMerge.merge(items, [])", self.bridge)
        self.assertIn("return MapLayerMerge.merge([], ready)", self.adapter)
        self.assertIn('static let aggregatedQueryEnabled = false', self.contracts)
        self.assertNotIn("aggregatedQueryEnabled = true", self.caller + self.service + self.root)

    def test_transport_reuses_manual_map_approval_and_raw_token(self):
        method = self.service.split("func publicLayers", 1)[1].split("private func topicRows", 1)[0]
        self.assertIn('baseRequest("api/map/public-layers"', method)
        self.assertNotIn("Authorization", method)
        self.assertNotIn("Bearer", method)
        self.assertIn('request.setValue(token, forHTTPHeaderField: "Authorization")', self.service)
        gate = self.reading.split("func publicLayers", 1)[1].split("private func read", 1)[0]
        self.assertIn("manualMapApprovalRevision != nil", gate)
        self.assertIn("ensureSelected(area)", gate)
        self.assertIn("try await read { try await $0.publicLayers", gate)
        self.assertIn("func publicLayers(area: RoamSearchArea, body: Data) async throws -> Data { throw APIError.notConfigured }", self.reading)
        self.assertIn("acceptsPublicLayers", self.root)
        self.assertIn("manualRead != nil || publicLayers", self.root)
        self.assertIn('appendingPathComponent("api/map/public-layers")', self.root)
        self.assertIn("deployment.reads.contains(.manualMap)", self.root)
        self.assertIn("approval.matches(context)", self.root)

    def test_roam_version_stays_on_the_unexecuted_candidate_column(self):
        self.assertIn("docs/w13/map-public-visibility-version.sql", self.adapter)
        self.assertIn("unexecuted candidate column", self.adapter)
        self.assertIn("visibility_version", self.adapter)
        self.assertIn("SOURCE_FAILED", self.adapter)
        self.assertIn("not 1", self.adapter)

    def test_detail_routes_and_entry_points(self):
        self.assertEqual(detail("roamPOI", set(), 4), ("cityNode", 4))
        self.assertEqual(detail("store", {"navigate"}, 8), ("merchant", 8))
        self.assertIsNone(detail("store", set(), 8))
        self.assertIsNone(detail("store", {"navigate", "register"}, 8))
        self.assertEqual(detail("registrableActivity", set(), 3), ("activity", 3))
        for kind in ("themeNode", "sideQuest", "cityBoardPoint"):
            self.assertIsNone(detail(kind, {"navigate"}, 3))
        self.assertIsNone(detail("roamPOI", set(), 0))
        body = self.caller.split("static func detail", 1)[1].split("public func openDetail", 1)[0]
        self.assertIn("case .roamPOI: return .cityNode(id)", body)
        self.assertIn('case .store: return item.capabilities == [.navigate] ? .merchant(id) : nil', body)
        self.assertIn("case .registrableActivity: return .activity(id)", body)
        self.assertIn("case .themeNode, .sideQuest, .cityBoardPoint: return nil", body)
        self.assertNotIn("register", body)
        self.assertIn("reader.cityNode", self.caller)
        self.assertIn("reader.merchant", self.caller)
        self.assertIn("session.activityDetail", self.entry)
        self.assertIn("MapPublicLayerCaller(reader: session.searchMapReader)", self.entry)
        self.assertIn('accessibilityIdentifier("mapPublic.entry")', self.search)
        self.assertIn("publicLayers: MapPublicLayerCaller? = nil", self.search)
        self.assertIn('accessibilityIdentifier("mapCore.entry.\\(entry.rawValue)")', self.hub)
        self.assertIn("publicLayers: MapPublicLayerCaller? = nil", self.hub)
        self.assertIn('accessibilityIdentifier("mapPublic.return")', read("App/MapPublicLayerCallerView.swift"))

    def test_account_and_query_generations_drop_late_callbacks(self):
        for marker in ["func noteAccount", "func submit", "func returned", "func openDetail", "func abandon"]:
            self.assertIn(marker, self.caller)
        self.assertIn("accountGeneration &+= 1", self.caller)
        self.assertIn("queryGeneration &+= 1", self.caller)
        self.assertIn("detailGeneration &+= 1", self.caller)
        fence = Fence()
        fence.note_account(7)
        first = fence.submit()
        fence.note_account(8)
        self.assertEqual(fence.accept_page(first[0], first[1], first[3]), "dropped")
        fence.note_account(8)
        same = fence.submit()
        self.assertEqual(fence.accept_page(same[0], same[1], same[3]), "applied")
        opened = fence.open_detail()
        fence.returned()
        self.assertEqual(fence.accept_detail(*opened, "late"), "dropped")
        self.assertIsNone(fence.detail)
        fresh = fence.returned()
        self.assertEqual(fence.accept_page(fresh[0], fresh[1], fresh[2]), "applied")

    def test_roots_and_project_file_are_not_the_commit_hookup(self):
        for path in ["App/AppSession.swift", "App/QuestifyApp.swift", "App/AccountView.swift"]:
            self.assertNotIn("MapPublicLayerCaller", read(path))
        self.assertNotIn("MapPublicLayerCaller.swift", read("Questify.xcodeproj/project.pbxproj"))
        self.assertNotIn("MapPublicLayerCallerView.swift", read("Questify.xcodeproj/project.pbxproj"))


if __name__ == "__main__":
    unittest.main()
