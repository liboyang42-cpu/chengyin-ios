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
        self.assertNotIn("token", code("Core/WorkshopUpgradeDraftStore.swift").lower())

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
