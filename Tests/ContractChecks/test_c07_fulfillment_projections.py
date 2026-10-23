"""Linux source contracts for exclusive C07 merchant supply / fulfillment projections.

These checks do not compile or execute Swift. XCTest on Linux is NOT_RUN.
App / CI = NOT_RUN. Isolation tests only. No real payment, refund, redeem, or award.
"""
from pathlib import Path
import hashlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = "76ce1b313af2595f9b7d7ace49040866209c7974"
CORE_FILES = [
    "Core/MerchantSupplyDryRunProjection.swift",
    "Core/EntitlementHoldProjection.swift",
    "Core/FulfillmentEvidenceProjection.swift",
    "Core/FourLedgerBillRereadProjection.swift",
    "Core/InvoiceHistoryUnknownProjection.swift",
    "Core/TransferSoldPolicyProjection.swift",
]
TEST_FILES = [
    "Tests/CoreTests/MerchantSupplyDryRunProjectionTests.swift",
    "Tests/CoreTests/EntitlementHoldProjectionTests.swift",
    "Tests/CoreTests/FulfillmentEvidenceProjectionTests.swift",
    "Tests/CoreTests/FourLedgerBillRereadProjectionTests.swift",
    "Tests/CoreTests/InvoiceHistoryUnknownProjectionTests.swift",
    "Tests/CoreTests/TransferSoldPolicyProjectionTests.swift",
]
CONTRACT = "Tests/ContractChecks/test_c07_fulfillment_projections.py"
HUNK = "docs/issue5-hunks/C07-ios-dot-hunk.md"
WHITELIST = CORE_FILES + TEST_FILES + [CONTRACT, HUNK]
FORBIDDEN_TOUCH = [
    "Core/MerchantAftercareEvidenceAdapter.swift",
    "Core/OrderLifecycleService.swift",
    "Core/OrderLifecycleCoordinator.swift",
    "Core/OrderLifecycleProduction.swift",
    "Core/MerchantSettlementProgress.swift",
    "Core/MerchantSettlementEntryPresentation.swift",
    "Core/MerchantRedemptionContext.swift",
    "Core/MerchantRedemptionFilter.swift",
    "Core/MerchantRedemptionProgress.swift",
    "Core/OrderPaymentVerifier.swift",
    "App/AppSession.swift",
    "App/AppCompositionRoot.swift",
    "Questify.xcodeproj/project.pbxproj",
]


def git_changed_names():
    names = set()
    commands = [
        ["git", "diff", "--name-only", BASE],
        ["git", "diff", "--name-only", "--cached", BASE],
        ["git", "diff", "--name-only", BASE, "HEAD"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ]
    for command in commands:
        output = subprocess.check_output(command, cwd=str(ROOT), text=True)
        names.update(line for line in output.splitlines() if line.strip())
    return names


class C07FulfillmentProjectionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in CORE_FILES + TEST_FILES}
        cls.joined = "\n".join(cls.sources.values())
        cls.hunk = (ROOT / HUNK).read_text()

    def test_exclusive_whitelist_files_exist(self):
        for path in WHITELIST:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_git_diff_names_equal_whitelist(self):
        self.assertEqual(git_changed_names(), set(WHITELIST))

    def test_forbidden_files_untouched(self):
        changed = git_changed_names()
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
            self.assertNotIn(path, changed)
            current = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            original = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=str(ROOT))
            self.assertEqual(current, hashlib.sha256(original).hexdigest(), path)

    def test_first_journey_markers_present(self):
        supply = self.sources["Core/MerchantSupplyDryRunProjection.swift"]
        tests = self.sources["Tests/CoreTests/MerchantSupplyDryRunProjectionTests.swift"]
        for expected in [
            "func evaluate(",
            "func recoverOriginal(originalRequestID:",
            "writesStock",
            "writesReservation",
            "holdCount(originalRequestID:",
            "Asia/Shanghai",
            "originalRequestID",
        ]:
            self.assertIn(expected, supply)
        self.assertIn("testFirstJourneyEvaluateAcceptDoesNotWriteStockRecoverOriginal", tests)
        self.assertIn("recoverOriginal(originalRequestID: requestID)", tests)
        self.assertIn("holdCount(originalRequestID: requestID), 1", tests)
        self.assertIn("FulfillmentAppointmentFact", tests)
        self.assertIn("refund trial; no payout", tests)
        self.assertIn("FourLedgerBillRereadProjection", tests)
        self.assertIn("InvoiceHistoryUnknownProjection", tests)
        self.assertIn("TransferSoldPolicyProjection", tests)
        self.assertIn("WAITING_SOURCE", self.sources["Core/TransferSoldPolicyProjection.swift"])

    def test_unknown_is_optional_none_json_null_not_empty_string(self):
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertIn("NSNull()", text, path)
            self.assertIn("originalRequestID.map { $0 as Any } ?? NSNull()", text, path)
            self.assertIn("trimmingCharacters(in: .whitespacesAndNewlines)", text, path)
        self.assertIn("object[\"originalRequestID\"] is NSNull", self.joined)
        self.assertIn('originalRequestID: "  "', self.joined)

    def test_null_hours_on_bookable_sku_is_unknown(self):
        supply = self.sources["Core/MerchantSupplyDryRunProjection.swift"]
        tests = self.sources["Tests/CoreTests/MerchantSupplyDryRunProjectionTests.swift"]
        self.assertIn("business hours missing", supply)
        self.assertIn("do not assume 24h", supply)
        self.assertIn("hoursOpen: nil, hoursClose: nil", tests)
        self.assertIn("testMissingHoursOnBookableSkuIsUnknownNotAWrite", tests)

    def test_holding_is_not_issuance_and_duplicate_does_not_double_hold(self):
        hold = self.sources["Core/EntitlementHoldProjection.swift"]
        self.assertIn("holdingIsIssuance", hold)
        self.assertIn("executedReserve", hold)
        self.assertIn("executedRedeem", hold)
        self.assertIn("executedAward", hold)
        self.assertIn("occupyCountByRequestID", hold)
        tests = self.sources["Tests/CoreTests/EntitlementHoldProjectionTests.swift"]
        self.assertIn("holdingIsIssuance", tests)
        self.assertIn("occupyCount(originalRequestID: \"c07-hold-1\"), 1", tests)

    def test_account_switch_isolation_markers_present(self):
        evidence = self.sources["Tests/CoreTests/FulfillmentEvidenceProjectionTests.swift"]
        hold = self.sources["Tests/CoreTests/EntitlementHoldProjectionTests.swift"]
        self.assertIn("testOtherRequestDoesNotRewriteOriginalJourney", evidence)
        self.assertIn("testInProcessRecoverKeepsOriginalJourneyAndMissingStaysNil", evidence)
        self.assertIn("testOtherRequestDoesNotRewriteOriginalHold", hold)
        self.assertIn("testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenHoldApplies", hold)
        supply_tests = self.sources["Tests/CoreTests/MerchantSupplyDryRunProjectionTests.swift"]
        self.assertIn("testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenAcceptApplies", supply_tests)
        hold_core = self.sources["Core/EntitlementHoldProjection.swift"]
        self.assertIn("view.outcome != .unknown", hold_core)
        supply_core = self.sources["Core/MerchantSupplyDryRunProjection.swift"]
        self.assertIn("decision.outcome != .unknown", supply_core)
        core = self.sources["Core/FulfillmentEvidenceProjection.swift"]
        self.assertIn("if let requestID, let original = originalStepsByRequestID[requestID]", core)

    def test_in_store_evidence_is_not_gps_fake(self):
        evidence = self.sources["Core/FulfillmentEvidenceProjection.swift"]
        tests = self.sources["Tests/CoreTests/FulfillmentEvidenceProjectionTests.swift"]
        self.assertIn("simulatedGPS", evidence)
        self.assertIn("GPS fake rejected", evidence)
        self.assertIn("in-store evidence", evidence)
        self.assertIn("testInStoreEvidenceRejectsGPSFake", tests)
        self.assertNotIn("CLLocation", evidence)
        self.assertNotIn("CLLocationManager", evidence)

    def test_four_ledger_current_projection_is_not_original_receipt(self):
        ledger = self.sources["Core/FourLedgerBillRereadProjection.swift"]
        tests = self.sources["Tests/CoreTests/FourLedgerBillRereadProjectionTests.swift"]
        self.assertIn("currentProjectionReplacesOriginal", ledger)
        self.assertIn("startedNewReconcile", ledger)
        self.assertIn("originalUnknownNotReplacedByProjectionSuccess", ledger)
        self.assertIn("testMissingWechatBillIsUnknownAndDoesNotStartANewReconcile", tests)
        self.assertIn("testNullAmountIsUnknownNotZeroCoercion", tests)
        self.assertIn("testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenMatchedApplies", tests)
        self.assertIn("view.outcomes.values.contains(where: { $0 == .matched || $0 == .diverged })", ledger)

    def test_invoice_unknown_does_not_treat_projection_as_file_success(self):
        invoice = self.sources["Core/InvoiceHistoryUnknownProjection.swift"]
        tests = self.sources["Tests/CoreTests/InvoiceHistoryUnknownProjectionTests.swift"]
        self.assertIn("currentProjectionIsOriginalFileSuccess", invoice)
        self.assertIn("startedNewApply", invoice)
        self.assertIn("historyIsNotAFile", invoice)
        self.assertIn("MANUAL", invoice)
        self.assertIn("testSubmittedManualApplicationHasUnknownFileAndDoesNotStartNewApply", tests)
        self.assertIn("projectionClaimsFileSuccess: true", tests)
        self.assertIn("testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenPresentApplies", tests)
        self.assertIn("view.fileStatus == .present", invoice)

    def test_transfer_sold_policy_missing_source_or_recipient_is_waiting_source(self):
        transfer = self.sources["Core/TransferSoldPolicyProjection.swift"]
        tests = self.sources["Tests/CoreTests/TransferSoldPolicyProjectionTests.swift"]
        self.assertIn("WAITING_SOURCE", transfer)
        self.assertIn("remoteSoldPolicyOriginalPresent = false", transfer)
        self.assertIn("designated recipient missing", transfer)
        self.assertIn("SMS identity is not transfer-sold policy", transfer)
        self.assertIn("usedSmsIdentityAsPolicy", transfer)
        self.assertIn("testMissingDesignatedRecipientIsWaitingSourceNotSuccess", tests)
        self.assertIn("testSmsIdentityIsNotSoldPolicyEvenWhenVerified", tests)
        self.assertIn("usedSmsIdentityAsPolicy: false", transfer)

    def test_no_real_payment_refund_redeem_award_or_shared_owners(self):
        for forbidden in [
            "StoreKit", "SKPayment", "WXPay", "WeChatPay", "IAP",
            "URLSession", "HTTPTransport", "AppSession", "AppCompositionRoot",
            "project.pbxproj", "BundleBookingService", "CLLocationManager",
            "MerchantAftercareEvidenceAdapter", "OrderLifecycleService",
            "OrderPaymentVerifier", "RuntimeDependencyFactory", "compositionRoot",
            "NSLocalizedString", "import SwiftUI",
        ]:
            self.assertNotIn(forbidden, self.joined)
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertTrue(text.startswith("import Foundation"), path)
            self.assertNotIn("import SwiftUI", text)
            self.assertNotIn("URLSession", text)

    def test_hunk_lists_pbx_additions_only(self):
        self.assertIn("Core/MerchantSupplyDryRunProjection.swift", self.hunk)
        self.assertIn("python3 tools/generate_project.py", self.hunk)
        self.assertIn("Do not edit pbxproj", self.hunk)
        self.assertIn("WAITING_SOURCE", self.hunk)
        self.assertIn("NOT_RUN", self.hunk)
        self.assertNotIn("IPHONEOS_DEPLOYMENT_TARGET = 1", self.hunk)

    def test_linux_xctest_is_explicitly_not_run(self):
        self.assertIn("XCTest on Linux is NOT_RUN", Path(__file__).read_text())
        self.assertIn("App / CI = NOT_RUN", Path(__file__).read_text())
        for path in TEST_FILES:
            self.assertIn("@testable import QuestifyCore", self.sources[path])

    def test_sha256_payload_covers_whitelist(self):
        digest = hashlib.sha256()
        for path in WHITELIST:
            digest.update(path.encode())
            digest.update((ROOT / path).read_bytes())
        self.assertEqual(len(digest.hexdigest()), 64)


if __name__ == "__main__":
    unittest.main()
