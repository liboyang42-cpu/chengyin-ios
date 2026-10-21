"""G / W18.4 local upgrade-draft contract. Runs without Swift."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def text(path):
    return (ROOT / path).read_text()


def code(path):
    return "\n".join(line for line in text(path).splitlines() if not line.strip().startswith("///") and not line.strip().startswith("//"))


class UpgradeDraftSourceContract(unittest.TestCase):
    def test_library_stays_closed_and_call_site_is_unchanged(self):
        library = text("App/WorkshopPurchasedLibraryView.swift")
        self.assertEqual(library.count("makeUpgrade: @escaping WorkshopPurchasedUpgradeFactory = { nil }"), 3)
        self.assertIn("if let handlers = makeUpgrade() { WorkshopPurchasedUpgradeEntry(item: item, handlers: handlers) }", library)
        self.assertNotIn("WorkshopUpgradeDraftStore", library)
        self.assertNotIn("URLSession", library)

    def test_entry_reports_success_only_after_the_write_returns(self):
        entry = text("App/WorkshopPurchasedUpgradeEntry.swift")
        for symbol in [
            "WorkshopPurchasedUpgradeHandlers",
            "WorkshopPurchasedUpgradeFactory = () -> WorkshopPurchasedUpgradeHandlers?",
            "WorkshopPurchasedUpgradeEntry",
            "WorkshopModUpgradeSheetView(presentation: presentation)",
            "saveDraft",
            "showing = false",
            "performBeginCompare",
            "performFinishCompare",
            "performSaveDraft",
            "performDismissSheet",
            "performCommitDraft",
            "performRestore",
            "performCancel",
            "performAcceptCompare",
        ]:
            self.assertIn(symbol, entry)
        save = entry.split("static func performSaveDraft", 1)[1].split("static func performCommitDraft", 1)[0]
        self.assertIn("try handlers.saveDraft(draft)", save)
        self.assertLess(save.index("try handlers.saveDraft(draft)"), save.index("draftSaved = true"))
        catch = save.split("} catch {", 1)[1]
        self.assertNotIn("draftSaved = true", catch)
        body = code("App/WorkshopPurchasedUpgradeEntry.swift")
        for bad in ["URLSession", "http://", "https://", "/api/", "CompareModVersions", "UpgradeInstallDraft", "WorkshopModVersionRef(", "coverage: .covered"]:
            self.assertNotIn(bad, body)
        self.assertIsNone(re.search(r'"/[a-z]+/', body))

    def test_sheet_waits_for_the_save_and_keeps_the_comparison_sections(self):
        sheet = text("App/WorkshopModUpgradeSheetView.swift")
        for marker in ["版本与能力差异对比", "新增能力", "移除能力", "保持不变能力", "升级保障与重审规则", "买方显式确认", "workshop.upgrade.confirmToggle"]:
            self.assertIn(marker, sheet)
        submit = sheet.split("private func submitUpgradeDraft()", 1)[1]
        self.assertLess(submit.index("try onConfirmDraft(request)"), submit.index("confirmedRequestId = request.requestId"))
        self.assertIn("guard confirmedRequestId == nil else { return }", submit)
        self.assertIn("本机保存未接通，未保存升级草稿。", submit)
        self.assertIn("升级草稿未能保存，现有版本与场次保持不变。", submit)
        self.assertNotIn("URLSession", code("App/WorkshopModUpgradeSheetView.swift"))

    def test_store_and_flow_are_local_and_fail_closed(self):
        store = text("Core/WorkshopUpgradeDraftStore.swift")
        flow = text("Core/WorkshopUpgradeFlow.swift")
        for marker in ["options: .atomic", "readBack == data", "sameDecision", "staleLease", "makeReceipt()", "persisted: true"]:
            self.assertIn(marker, store)
        self.assertNotIn("persisted: false", store)
        for marker in ["func begin", "func cancel", "func commit", "func restore", "stalePresentation", ".revoked", "WorkshopUpgradeDraftRequest", "pinnedVersion"]:
            self.assertIn(marker, flow)
        for path in ["Core/WorkshopUpgradeDraftStore.swift", "Core/WorkshopUpgradeFlow.swift"]:
            body = code(path)
            for bad in ["URLSession", "http://", "https://", "URLRequest", "/api/", "CompareModVersions", "UpgradeInstallDraft"]:
                self.assertNotIn(bad, body)
        self.assertNotIn("WorkshopUpgradeProductionBoundary", flow)
        self.assertNotIn("token", code("Core/WorkshopUpgradeDraftStore.swift").lower())

    def test_production_ports_stay_disabled_and_unwired(self):
        boundary = text("Core/WorkshopUpgradeFlowBoundary.swift")
        self.assertIn("public static let callsNetwork = false", boundary)
        self.assertIn("public static let portsEnabled = false", boundary)
        self.assertIn('case compareModVersions = "CompareModVersions"', boundary)
        self.assertIn('case upgradeInstallDraft = "UpgradeInstallDraft"', boundary)
        body = code("Core/WorkshopUpgradeFlowBoundary.swift")
        for bad in ["URLSession", "http://", "https://", "URLRequest", "/api/", "makeUpgrade"]:
            self.assertNotIn(bad, body)

    def test_acceptance_tests_exist(self):
        core = text("Tests/CoreTests/WorkshopUpgradeDraftTests.swift")
        app = text("Tests/AppUnitTests/WorkshopUpgradeDraftEntryTests.swift")
        for name in [
            "testSaveFailureDoesNotReportSuccessOrLeaveADraft",
            "testReadbackMismatchRemovesTheFileAndRefusesTheReceipt",
            "testAtomicSaveRestoresForTheSameLeaseAndPinsThePurchasedVersion",
            "testDuplicateConfirmDoesNotCreateASecondDraft",
            "testConflictCancelAndStaleGenerationDoNotWrite",
            "testUnknownCoverageRevocationAndNewPurchaseAreRefused",
            "testRestoreRejectsRevokedLeaseHashModuleAndVersionMismatches",
        ]:
            self.assertIn(name, core)
        self.assertIn("testVoidSaveFailureDoesNotMarkTheDraftSaved", app)
        self.assertIn("testCommitFailureStaysOnTheSheetAndSuccessRestoresWithoutChangingThePurchasedVersion", app)
        self.assertIn("testNilFlowRestoreMissAndAccountChangeDoNotKeepADraft", app)
        self.assertIn("testSheetPresentedDoesNotInvalidateAndPopDoes", app)

    def test_nil_flow_is_unavailable_and_leave_cancels(self):
        entry = text("App/WorkshopPurchasedUpgradeEntry.swift")
        commit = entry.split("static func performCommitDraft", 1)[1].split("static func performRestore", 1)[0]
        self.assertIn("guard let flow = handlers.flow else { throw WorkshopUpgradeDraftIssue.unavailable }", commit)
        self.assertNotIn("saveDraft", commit)
        self.assertLess(commit.index("throw WorkshopUpgradeDraftIssue.unavailable"), commit.index("draftSaved = true"))
        self.assertIn("draftSaved = false", commit.split("catch WorkshopUpgradeDraftIssue.unavailable", 1)[1].split("catch WorkshopUpgradeDraftIssue.staleLease", 1)[0])
        restore = entry.split("static func performRestore", 1)[1].split("static func performDismissSheet", 1)[0]
        self.assertIn("receipt = nil; draftSaved = false; return", restore)
        self.assertGreaterEqual(restore.count("draftSaved = false"), 2)
        self.assertGreaterEqual(restore.count("receipt = nil"), 2)
        body = entry.split("var body: some View", 1)[1]
        for marker in [
            "lease: liveAccount.lease",
            "WorkshopUpgradeLeasePublish(live: liveAccount, flow: handlers.flow)",
            ".onDisappear {",
            ".onChange(of: handlers.flow?.accountLease)",
            "onDismiss:",
            "Self.performInvalidate(compareToken: &compareToken, flow: armedFlow)",
            "Self.performAccountChanged(",
        ]:
            self.assertIn(marker, body)
        disappear = body.split(".onDisappear {", 1)[1].split(".onChange", 1)[0]
        self.assertIn("performDisappear(sheetPresented: showing, detailPresented: detailPresented", disappear)
        self.assertNotIn("performInvalidate", disappear)
        rule = entry.split("static func performDisappear", 1)[1].split("static func performCancel", 1)[0]
        self.assertIn("if popSignal {", rule)
        self.assertIn("guard !detailPresented else { return }", rule)
        self.assertIn("} else if sheetPresented || detailPresented {", rule)
        self.assertIn("return", rule)
        self.assertIn("armed !== current", rule)
        pop = body.split(".onChange(of: detailPresented)", 1)[1].split(".onChange(of: handlers.flow?.accountLease)", 1)[0]
        self.assertIn("popSignal: true", pop)
        flow = text("Core/WorkshopUpgradeFlow.swift")
        self.assertIn("func matches(token: UUID, lease: WorkshopUpgradeAccountLease?) -> Bool", flow)
        self.assertIn("generation == token && accountLease == lease && accountLeaseIsCurrent", flow)
        self.assertIn("func cancel(ifGeneration token: UUID)", flow)
        self.assertIn("guard generation == token else { return }", flow)
        self.assertNotIn("WorkshopUpgradeProductionBoundary", flow)
        self.assertIn("case invalid, staleLease, stalePresentation, saveFailed, conflict, revoked, unavailable", text("Core/WorkshopUpgradeDraftStore.swift"))
        submit = text("App/WorkshopModUpgradeSheetView.swift").split("private func submitUpgradeDraft()", 1)[1]
        unavailable = submit.split("catch WorkshopUpgradeDraftIssue.unavailable", 1)[1].split("} catch {", 1)[0]
        self.assertIn("本机保存未接通，未保存升级草稿。", unavailable)
        self.assertNotIn("confirmedRequestId = request.requestId", unavailable)
        self.assertNotIn("URLSession", code("App/WorkshopPurchasedUpgradeEntry.swift"))
        self.assertEqual(text("App/WorkshopPurchasedLibraryView.swift").count("makeUpgrade: @escaping WorkshopPurchasedUpgradeFactory = { nil }"), 3)


class UpgradeDraftLifecycleModel(unittest.TestCase):
    """Counterexamples for the G2 entry rules. This is not the Swift runtime."""

    def test_nil_flow_commit_does_not_save(self):
        result = commit_draft(flow=False, save_calls=0, draft_saved=True)
        self.assertEqual(result["error"], "unavailable")
        self.assertFalse(result["draft_saved"])
        self.assertIsNone(result["receipt"])
        self.assertEqual(result["save_calls"], 0)
        self.assertFalse(result["save_failed"])

    def test_restore_clears_on_nil_flow_miss_and_error(self):
        for name, kwargs in [
            ("nil-flow", dict(flow=False, found="persisted")),
            ("miss", dict(flow=True, found="missing")),
            ("error", dict(flow=True, found="persisted", error="staleLease")),
        ]:
            with self.subTest(name=name):
                result = restore_draft(draft_saved=True, receipt="old", **kwargs)
                self.assertFalse(result["draft_saved"])
                self.assertIsNone(result["receipt"])
        kept = restore_draft(draft_saved=False, receipt=None, flow=True, found="persisted")
        self.assertTrue(kept["draft_saved"])
        self.assertEqual(kept["receipt"], "stored")

    def test_sheet_presented_does_not_invalidate(self):
        for detail in (True, False):
            with self.subTest(detail=detail):
                kept = disappear("g", "t", sheet_presented=True, detail_presented=detail)
                self.assertEqual(kept["generation"], "g")
                self.assertEqual(kept["token"], "t")
        cover = disappear("g", "t", sheet_presented=False, detail_presented=True)
        self.assertEqual(cover["generation"], "g")
        self.assertEqual(cover["token"], "t")
        still_up = disappear("g", "t", sheet_presented=False, detail_presented=True, pop_signal=True)
        self.assertEqual(still_up["generation"], "g")

    def test_pop_invalidates(self):
        popped = disappear("g", "t", sheet_presented=False, detail_presented=False)
        self.assertIsNone(popped["generation"])
        self.assertIsNone(popped["token"])
        while_sheet = disappear("g", "t", sheet_presented=True, detail_presented=False, pop_signal=True)
        self.assertIsNone(while_sheet["generation"])
        self.assertIsNone(while_sheet["token"])

    def test_dismiss_leave_and_account_change_drop_the_generation(self):
        for name in ("dismiss", "leave", "account"):
            with self.subTest(name=name):
                result = invalidate(generation="g", token="g")
                self.assertIsNone(result["generation"])
                self.assertIsNone(result["token"])

    def test_compare_return_checks_lease_and_does_not_cancel_a_replacement(self):
        revoked = accept(token="g", current="g", generation="g", flow_lease="a", live_lease="a", lease_current=False, checking=True)
        self.assertFalse(revoked["opened"])
        self.assertTrue(revoked["unavailable"])
        self.assertFalse(revoked["checking"])
        self.assertIsNone(revoked["generation"])
        swapped = accept(token="g", current="g", generation="g", flow_lease="a", live_lease="b", lease_current=True, checking=True)
        self.assertFalse(swapped["opened"])
        self.assertIsNone(swapped["generation"])
        self.assertTrue(swapped["unavailable"])
        replacement = accept(token="old", current="new", generation="new", flow_lease="a", live_lease="a", lease_current=True, checking=True)
        self.assertEqual(replacement["generation"], "new")
        self.assertTrue(replacement["checking"])
        self.assertFalse(replacement["opened"])
        self.assertFalse(replacement["unavailable"])
        stale_only = accept(token="old", current=None, generation=None, flow_lease=None, live_lease=None, lease_current=False, checking=True, has_flow=False)
        self.assertTrue(stale_only["checking"])
        self.assertFalse(stale_only["opened"])
        opened = accept(token="g", current="g", generation="g", flow_lease="a", live_lease="a", lease_current=True, checking=True)
        self.assertTrue(opened["opened"])
        self.assertEqual(opened["generation"], "g")
        self.assertFalse(opened["checking"])


def commit_draft(flow, save_calls, draft_saved):
    if not flow:
        return {"error": "unavailable", "draft_saved": False, "receipt": None, "save_calls": save_calls, "save_failed": False}
    return {"error": None, "draft_saved": draft_saved, "receipt": "stored", "save_calls": save_calls + 1, "save_failed": False}


def restore_draft(draft_saved, receipt, flow, found, error=None):
    del draft_saved, receipt
    if not flow or error or found != "persisted":
        return {"draft_saved": False, "receipt": None}
    return {"draft_saved": True, "receipt": "stored"}


def invalidate(generation, token):
    del generation, token
    return {"generation": None, "token": None}


def disappear(generation, token, sheet_presented, detail_presented, pop_signal=False):
    if pop_signal:
        if detail_presented:
            return {"generation": generation, "token": token}
    elif sheet_presented or detail_presented:
        return {"generation": generation, "token": token}
    return {"generation": None, "token": None}


def accept(token, current, generation, flow_lease, live_lease, lease_current, checking, has_flow=True):
    matches = bool(has_flow and generation == token and flow_lease == live_lease and lease_current)
    live = matches if has_flow else True
    if token != current or not live:
        if has_flow and generation == token:
            generation = None
        if token != current:
            return {"generation": generation, "opened": False, "checking": checking, "unavailable": False}
        return {"generation": generation, "opened": False, "checking": False, "unavailable": True}
    return {"generation": generation, "opened": True, "checking": False, "unavailable": False}


class UpgradeDraftDecisionModel(unittest.TestCase):
    """Runnable decision table for the local loop. This is not the Swift runtime."""

    def test_matrix(self):
        cases = [
            ("save-fail", dict(write_fails=True), "saveFailed", None),
            ("readback", dict(corrupt=True), "saveFailed", None),
            ("save", dict(), None, "upgrade-0001"),
            ("reopen", dict(reopen=True), None, "upgrade-0001"),
            ("duplicate", dict(again="upgrade-0002"), None, "upgrade-0001"),
            ("conflict", dict(other_version=True), "conflict", "upgrade-0001"),
            ("cancel", dict(cancel=True), "stalePresentation", None),
            ("stale", dict(replace_generation=True), "stalePresentation", None),
            ("unknown", dict(coverage="unknown"), "licenseUnknown", None),
            ("purchase", dict(coverage="requiresNewPurchase"), "notCovered", None),
            ("unconfirmed", dict(confirmed=False), "unconfirmed", None),
            ("revoked", dict(revoked=True), "revoked", None),
            ("bad-hash", dict(restore_hash="e"), "invalid", "upgrade-0001"),
            ("bad-module", dict(restore_module="other"), "invalid", "upgrade-0001"),
            ("bad-version", dict(restore_version="v9"), "invalid", "upgrade-0001"),
            ("revoked-lease", dict(revoke_lease=True), "staleLease", "upgrade-0001"),
            ("other-account", dict(other_account=True), None, None),
        ]
        for name, options, error, request_id in cases:
            with self.subTest(name=name):
                result = decide(**options)
                self.assertEqual(result["error"], error)
                self.assertEqual(result["requestId"], request_id)
                self.assertEqual(result["files"], 0 if request_id is None else 1)
                self.assertEqual(result["pinned"], ("v1", "a" * 8))
                self.assertFalse(result["network"])


def decide(**options):
    pinned = ("v1", "a" * 8)
    lease = {"account": 53, "epoch": 7, "revoked": False}
    generation = "g1"
    record = None
    files = 0
    error = None
    request_id = None
    if options.get("cancel"):
        generation = None
    if options.get("replace_generation"):
        generation = "g2"
    coverage = options.get("coverage", "covered")
    confirmed = options.get("confirmed", True)
    item_revoked = options.get("revoked", False)
    presented = "g1"
    if item_revoked:
        error = "revoked"
    elif presented != generation:
        error = "stalePresentation"
    elif not confirmed:
        error = "unconfirmed"
    elif coverage == "unknown":
        error = "licenseUnknown"
    elif coverage == "requiresNewPurchase":
        error = "notCovered"
    elif options.get("write_fails") or options.get("corrupt"):
        error = "saveFailed"
    else:
        record = {"requestId": "upgrade-0001", "version": "v2", "hash": "c", "account": 53, "epoch": 7, "module": "mod", "from": pinned}
        files = 1
        request_id = record["requestId"]
        if options.get("again"):
            request_id = record["requestId"]
        if options.get("other_version"):
            error = "conflict"
            request_id = record["requestId"]
    if record and options.get("restore_hash"):
        error, request_id = "invalid", record["requestId"]
    if record and options.get("restore_module"):
        error, request_id = "invalid", record["requestId"]
    if record and options.get("restore_version"):
        error, request_id = "invalid", record["requestId"]
    if record and options.get("revoke_lease"):
        error, request_id = "staleLease", record["requestId"]
    if options.get("other_account"):
        error, request_id, files = None, None, 0
    if options.get("reopen") and record and error is None:
        request_id = record["requestId"]
    return {"error": error, "requestId": request_id, "files": files, "pinned": pinned, "network": False}


if __name__ == "__main__":
    unittest.main()
