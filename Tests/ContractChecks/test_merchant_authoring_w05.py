"""W05 merchant authoring client contract. Not Swift execution."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ROUTES = [
    "api/merchant/authoring/jobs",
    "api/merchant/authoring/jobs/cancel",
    "api/merchant/authoring/drafts",
    "api/merchant/authoring/releases",
    "api/merchant/authoring/public",
    "api/merchant/authoring/environment",
    "api/merchant/authoring/main-line",
]
WITHHELD = {"order", "orders", "customer", "customers", "cost", "costs"}


def read(path):
    return (ROOT / path).read_text()


def admit(existing, fingerprint):
    if existing is None:
        return "claim"
    return "replay" if existing == fingerprint else "conflict"


def public_facts(stage, release_id, facts):
    if stage != "PUBLISHED" or not release_id:
        return None
    kept = {key: value for key, value in facts.items() if key.lower() not in WITHHELD}
    return kept or None


def accepts_save(content_changed, stage, approvals_reused):
    if not content_changed:
        return True
    if approvals_reused:
        return False
    return stage in {"DRAFT", "CHANGES_REQUIRED", "VALIDATED", "FAILED"}


class MerchantAuthoringW05(unittest.TestCase):
    def test_journal_replay_conflict_and_cancel_are_not_published(self):
        self.assertEqual(admit(None, "a"), "claim")
        self.assertEqual(admit("a", "a"), "replay")
        self.assertEqual(admit("a", "b"), "conflict")
        journal = read("Core/MerchantAuthoringJournal.swift")
        self.assertIn("existingFingerprint == fingerprint ? .replay : .conflict", journal)
        self.assertIn("state: .unknown", journal)
        self.assertIn("record.state = .cancelled", journal)
        self.assertNotIn("case published", journal)
        record = journal.split("struct MerchantAuthoringJobRecord", 1)[1].split("public init", 1)[0]
        for secret in ("prompt", "token", "credential", "customer", "order"):
            self.assertNotIn(secret, record)

    def test_routes_are_the_planned_controller_and_fail_closed(self):
        service = read("Core/MerchantAuthoringService.swift")
        for path in ROUTES:
            self.assertIn('= "%s"' % path, service)
        self.assertIn("ApiMerchantAuthoringController", service)
        self.assertIn("cursor/w05-j-merchant-authoring", service)
        self.assertNotIn("api/ai/", service)
        self.assertNotIn("jobs/generate", service)
        self.assertNotIn("revisions/save", service)
        self.assertIn('api/merchant/authoring/drafts/\\(id)', service)
        self.assertIn("case .create: return .unknown", service)
        self.assertIn('row["publishSucceeded"]', service)
        self.assertIn("static let unset = MerchantAuthoringPolicy()", service)
        self.assertIn("public var modelID: String?", service)
        self.assertIsNone(re.search(r'modelID\s*=\s*"', service))
        mutate = service.split("func mutate", 1)[1].split("func replay", 1)[0]
        self.assertLess(mutate.index("journal.claim"), mutate.index("await send("))
        post = service.split("func send(", 1)[1].split("func allows", 1)[0]
        self.assertIn("transport.send", post)
        self.assertIn("endpointNotApproved", mutate)
        generate = service.split("func generate", 1)[1].split("func query", 1)[0]
        self.assertNotIn("transport.send", generate)
        self.assertIn("query(requestID:", service)
        cancel = service.split("func cancel", 1)[1].split("func save", 1)[0]
        self.assertIn("return .cancelled", cancel)
        self.assertNotIn("acknowledge", cancel)
        self.assertNotIn(".published", cancel)
        self.assertIn('for key in stripped { clean.removeValue(forKey: key) }', service)
        self.assertIn('"approved"', service)
        self.assertIn("EnvironmentBranchSelector.decide", service)
        self.assertIn("snapshot: nil", service)
        self.assertIn("NEW_ROUTE", service)
        self.assertIn("STOCK_PROMISE", service)

    def test_content_change_cannot_keep_an_old_approval(self):
        self.assertFalse(accepts_save(True, "APPROVED", False))
        self.assertFalse(accepts_save(True, "PUBLISHED", False))
        self.assertFalse(accepts_save(True, "DRAFT", True))
        self.assertTrue(accepts_save(True, "DRAFT", False))
        service = read("Core/MerchantAuthoringService.swift")
        self.assertIn("[.draft, .changesRequired, .validated, .failed]", service)
        self.assertIn("new.merchantFactsApproval == nil, new.themeContentApproval == nil", service)

    def test_public_projection_keeps_only_a_published_snapshot(self):
        self.assertIsNone(public_facts("DRAFT", "r", {"hours": "9-5"}))
        self.assertIsNone(public_facts("PUBLISHED", "", {"hours": "9-5"}))
        self.assertIsNone(public_facts("PUBLISHED", "r", {"order": "1", "customer": "a", "cost": "2"}))
        self.assertEqual(public_facts("PUBLISHED", "r", {"hours": "9-5", "orders": "secret"}), {"hours": "9-5"})
        contracts = read("Core/ShopNPCContracts.swift")
        for key in WITHHELD:
            self.assertIn('"%s"' % key, contracts)
        self.assertIn("stage == .published", contracts)
        scope = read("Core/SceneAIScope.swift")
        self.assertIn("releaseStage == .published", scope)
        self.assertIn("classes.intersection(allowedData)", scope)
        for forbidden in ("api/", "URLSession", "token", "Authorization"):
            self.assertNotIn(forbidden, scope)

    def test_existing_contract_files_still_have_no_route_strings(self):
        gates = read("Core/MerchantAICommerceGates.swift")
        authoring = read("Core/MerchantAIAuthoring.swift")
        scope = read("Core/SceneAIScope.swift")
        for source in (gates, authoring, scope):
            for forbidden in ("URLSession", "URLRequest", "HTTPTransport", "httpMethod", "api/", "http://", "https://", "token", "Authorization", "Keychain"):
                self.assertNotIn(forbidden, source)
        self.assertIn("public static let reviewedEndpoints: [String] = []", gates)
        self.assertIn("MerchantAuthoringRoute", gates)
        self.assertIn("MerchantAuthoringRoute", authoring)

    def test_owner_switch_drops_private_content_and_stale_replies(self):
        coordinator = read("Core/MerchantAuthoringCoordinator.swift")
        self.assertIn("epoch &+= 1", coordinator)
        self.assertIn("clearPrivate()", coordinator)
        self.assertIn("guard live(snap) else { return }", coordinator)
        self.assertIn("themeMainLineBlocked: Bool { false }", coordinator)
        self.assertNotIn("phase = .published", coordinator)
        host = read("App/ShopNPCSessionHost.swift")
        invalidate = host.split("func invalidate()", 1)[1].split("func ", 1)[0]
        self.assertIn("publicReleaseID = nil", invalidate)
        self.assertLess(invalidate.index("publicReleaseID = nil"), invalidate.index("conversations.removeAll()"))

    def test_view_chain_has_no_self_approval(self):
        view = read("App/MerchantAuthoringView.swift")
        for identifier in (
            "merchant.authoring.list", "merchant.authoring.new", "merchant.authoring.generate",
            "merchant.authoring.cancel", "merchant.authoring.query", "merchant.authoring.save",
            "merchant.authoring.review", "merchant.authoring.publish", "merchant.authoring.readback",
            "merchant.authoring.preview", "merchant.authoring.back", "merchant.authoring.mainLine",
        ):
            self.assertIn('.accessibilityIdentifier("%s")' % identifier, view)
        self.assertNotIn("func approve", view)
        self.assertIn("clientMaySelfApprove", view)
        self.assertNotIn("MerchantAuthoringView", read("App/MerchantHomeView.swift"))
        diff = read("App/MerchantAuthoringWorkbenchHostInject.diff")
        self.assertIn("MerchantAuthoringView", diff)
        self.assertIn("merchant.authoring.open", diff)
        self.assertIn("Call adopt", diff)


if __name__ == "__main__":
    unittest.main()
