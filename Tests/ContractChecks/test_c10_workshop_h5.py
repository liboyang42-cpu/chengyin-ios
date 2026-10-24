"""Linux source contracts for exclusive workshop module / H5 author-publish-consume.

These checks do not compile or execute Swift. XCTest / App / CI = NOT_RUN.
"""
from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE_FILES = [
    "Core/WorkshopModuleImportGate.swift",
    "Core/WorkshopPackageVersionPublish.swift",
    "Core/WorkshopInstallUpgradeRollback.swift",
    "Core/WorkshopRunServerVerification.swift",
    "Core/H5SessionCapabilityGate.swift",
    "Core/H5AnswerProtection.swift",
]
TEST_FILES = [
    "Tests/CoreTests/WorkshopModuleImportGateTests.swift",
    "Tests/CoreTests/WorkshopPackageVersionPublishTests.swift",
    "Tests/CoreTests/WorkshopInstallUpgradeRollbackTests.swift",
    "Tests/CoreTests/WorkshopRunServerVerificationTests.swift",
    "Tests/CoreTests/H5SessionCapabilityGateTests.swift",
    "Tests/CoreTests/H5AnswerProtectionTests.swift",
]
CONTRACT = "Tests/ContractChecks/test_c10_workshop_h5.py"
HUNK = "docs/issue5-hunks/C10-ios-dot-hunk.md"
EXISTING_WORKSHOP_CORE = [
    "Core/WorkshopCreatorConsentContracts.swift",
    "Core/WorkshopCreatorConsentController.swift",
    "Core/WorkshopCreatorConsentService.swift",
    "Core/WorkshopCreatorPendingContracts.swift",
    "Core/WorkshopCreatorPendingController.swift",
    "Core/WorkshopCreatorPendingService.swift",
    "Core/WorkshopOwnedBrowser.swift",
    "Core/WorkshopOwnedContracts.swift",
    "Core/WorkshopOwnedPackage.swift",
    "Core/WorkshopOwnedPackageBrowser.swift",
    "Core/WorkshopOwnedPackageService.swift",
    "Core/WorkshopOwnedPresentation.swift",
    "Core/WorkshopOwnedService.swift",
    "Core/WorkshopPaidInstallContracts.swift",
    "Core/WorkshopPaidInstallController.swift",
    "Core/WorkshopPaidInstallPendingStore.swift",
    "Core/WorkshopPaidInstallService.swift",
    "Core/WorkshopPaidInstalledTextContracts.swift",
    "Core/WorkshopPaidInstalledTextController.swift",
    "Core/WorkshopPaidInstalledTextService.swift",
    "Core/WorkshopPaidProfessionalContracts.swift",
    "Core/WorkshopPaidProfessionalController.swift",
    "Core/WorkshopPaidProfessionalOperation.swift",
    "Core/WorkshopPaidProfessionalPendingStore.swift",
    "Core/WorkshopPaidProfessionalPreparation.swift",
    "Core/WorkshopPaidProfessionalService.swift",
    "Core/WorkshopPurchasedBrowser.swift",
    "Core/WorkshopPurchasedContracts.swift",
    "Core/WorkshopPurchasedPresentation.swift",
    "Core/WorkshopPurchasedService.swift",
]
FORBIDDEN_TOUCH = [
    "App/AppSession.swift",
    "App/AppCompositionRoot.swift",
    "Questify.xcodeproj/project.pbxproj",
]
WHITELIST = CORE_FILES + TEST_FILES + [CONTRACT, HUNK]


class C10WorkshopH5Contracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in CORE_FILES + TEST_FILES}
        cls.joined = "\n".join(cls.sources.values())
        cls.existing = {path: (ROOT / path).read_text() for path in EXISTING_WORKSHOP_CORE}

    def test_exclusive_whitelist_files_exist(self):
        self.assertEqual(len(EXISTING_WORKSHOP_CORE), 30)
        for path in WHITELIST + EXISTING_WORKSHOP_CORE:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_existing_workshop_core_inventory_was_not_rewritten(self):
        pattern = re.compile(r"rollback|installPackage|qmod|H5Session")
        for path, text in self.existing.items():
            self.assertFalse(pattern.search(text), path)
            for marker in CORE_FILES:
                name = Path(marker).stem
                self.assertNotIn(name, text, path)
        paid = self.existing["Core/WorkshopPaidInstallContracts.swift"]
        self.assertIn("W18_PRIVATE_COMPONENT_ONLY", paid)
        self.assertIn("executable", paid)
        self.assertIn("false", paid)
        purchased = self.existing["Core/WorkshopPurchasedContracts.swift"]
        self.assertIn("permitsContentUse: Bool { false }", purchased)
        self.assertIn("permitsPurchase: Bool { false }", purchased)

    def test_first_journey_import_publish_install_run_recover(self):
        tests = self.sources["Tests/CoreTests/WorkshopModuleImportGateTests.swift"]
        self.assertIn("testFirstJourneyImportPublishInstallRunRecoverOriginal", tests)
        importer = self.sources["Core/WorkshopModuleImportGate.swift"]
        for expected in [
            "func importFromNormalEntry(",
            "func validate(",
            "func previewMetadataOnly()",
            "func markReviewPending()",
            "schemaVersion == 1",
            "sha256Hex",
        ]:
            self.assertIn(expected, importer)
        self.assertIn("authorizedHold(originalRequestID: \"req-c10-1\"", tests)
        self.assertIn("install(originalRequestID: \"req-c10-1\")", tests)
        self.assertIn("kind: .serverPass", tests)
        self.assertIn("kind: .unknown", tests)
        self.assertIn("recoverOriginal(originalRequestID: \"req-c10-1\")", tests)
        self.assertIn("installCount, 1", tests)

    def test_javascript_self_report_is_rejected(self):
        run = self.sources["Core/WorkshopRunServerVerification.swift"]
        tests = self.sources["Tests/CoreTests/WorkshopRunServerVerificationTests.swift"]
        self.assertIn("jsSelfReportRejected", run)
        self.assertIn("func applyJavaScriptClear(", run)
        self.assertIn("func applyH5SelfReport(", run)
        self.assertIn("testJavaScriptSelfReportCannotClearRun", tests)
        answers = self.sources["Core/H5AnswerProtection.swift"]
        self.assertIn("func succeedFromJSReport()", answers)
        self.assertIn("func succeedFromClientClock(", answers)
        self.assertIn("jsSelfReportRejected", answers)
        self.assertIn("testAnswersNeverInClientPackAndJSReportCannotSucceed",
                      self.sources["Tests/CoreTests/H5AnswerProtectionTests.swift"])

    def test_missing_qmod_original_is_waiting_source_not_success(self):
        importer = self.sources["Core/WorkshopModuleImportGate.swift"]
        tests = self.sources["Tests/CoreTests/WorkshopModuleImportGateTests.swift"]
        self.assertIn("WAITING_SOURCE", importer)
        self.assertIn("qmod.original", importer)
        self.assertIn("qmodOriginalPresent: Bool { false }", importer)
        self.assertIn("ios.e2d86c4.unpushed", importer)
        self.assertIn("implPack.232.hashes", importer)
        self.assertIn("questify.v12.docx", importer)
        self.assertIn("qmod.workshop.candidate.binaries", importer)
        self.assertIn("testMissingQmodOriginalIsWaitingSourceNotSuccess", tests)
        self.assertIn('format: .unknownQmod', tests)
        self.assertIn("waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal)", tests)

    def test_answers_and_hidden_coordinates_are_not_shipped(self):
        importer = self.sources["Core/WorkshopModuleImportGate.swift"]
        answers = self.sources["Core/H5AnswerProtection.swift"]
        self.assertIn("answersOrHiddenCoordinatesForbidden", importer)
        self.assertIn('"hiddenCoordinate"', importer)
        self.assertIn('"answer"', importer)
        self.assertIn("answersMustNotShipInClientPack", answers)
        self.assertIn("compareServerFrozenAuthorVersion", answers)
        self.assertIn("Same public-catalog rule as OfflinePackOperation.inspect", answers)

    def test_h5_gate_signed_allowlist_and_discovery_already_bans_arbitrary_banner(self):
        gate = self.sources["Core/H5SessionCapabilityGate.swift"]
        tests = self.sources["Tests/CoreTests/H5SessionCapabilityGateTests.swift"]
        self.assertIn("h5.sdk.original", gate)
        self.assertIn("h5SdkOriginalPresent: Bool { false }",
                      self.sources["Core/WorkshopModuleImportGate.swift"])
        self.assertIn("arbitraryH5Forbidden", gate)
        self.assertIn("versionIncompatible", gate)
        self.assertIn("func openArbitraryH5(", gate)
        self.assertIn("DiscoveryContracts already bans arbitrary banner H5", gate)
        self.assertIn("testArbitraryH5UnsignedDomainAndVersionMismatchReject", tests)
        self.assertIn("testRejectedAdmitDoesNotOccupyThenUniqueAdmitApplies", tests)
        discovery = (ROOT / "Core/DiscoveryContracts.swift").read_text()
        self.assertIn("Never open arbitrary H5 URLs from a banner", discovery)

    def test_unknown_receipt_keeps_intent_and_install_has_no_iap(self):
        run = self.sources["Core/WorkshopRunServerVerification.swift"]
        self.assertIn("Does not mint a new requestId", run)
        self.assertIn("current projection as success", run)
        self.assertIn("projectionSucceeded", run)
        self.assertIn("currentProjectionIsSuccess", run)
        install = self.sources["Core/WorkshopInstallUpgradeRollback.swift"]
        self.assertIn("digitalGoodsOpenDecision", install)
        self.assertIn("func purchaseViaIAP()", install)
        self.assertIn("func rollback()", install)
        self.assertIn("noRetainedPrior", install)
        self.assertIn("W18_PRIVATE_COMPONENT_ONLY", install)
        self.assertIn("OpenDecision", install)
        publish = self.sources["Core/WorkshopPackageVersionPublish.swift"]
        self.assertIn("func republish(originalRequestID:", publish)
        self.assertIn("frozenHashMutation", publish)
        self.assertIn("publicRegistryReserved", publish)
        self.assertIn("Does not own the public author-publish registry", publish)

    def test_no_shared_forbidden_owners_or_iap(self):
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
            text = (ROOT / path).read_text()
            for name in [
                "WorkshopModuleImportGate", "WorkshopPackageVersionPublish",
                "WorkshopInstallUpgradeRollback", "WorkshopRunServerVerification",
                "H5SessionCapabilityGate", "H5AnswerProtection",
            ]:
                self.assertNotIn(name, text)
        for forbidden in [
            "StoreKit", "SKPayment", "requestPayment", "URLSession", "HTTPTransport",
            "AppSession", "AppCompositionRoot", "project.pbxproj", "RuntimeDependencyFactory",
            "NSLocalizedString", "import SwiftUI", "iapPrice", "digitalGoodsPrice",
        ]:
            self.assertNotIn(forbidden, self.joined)
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertTrue(text.startswith("import Foundation"), path)
            self.assertNotIn("import SwiftUI", text)
            self.assertNotIn("import Observation", text)

    def test_other_request_cannot_rewrite_original_import(self):
        tests = self.sources["Tests/CoreTests/WorkshopModuleImportGateTests.swift"]
        importer = self.sources["Core/WorkshopModuleImportGate.swift"]
        self.assertIn("testOtherRequestIdDoesNotRewriteImportedOriginal", tests)
        self.assertIn("testMissingRequestIdStaysNilNeverEmptyString", tests)
        self.assertIn("testUnknownQmodImportOfNeverSeenIdDoesNotOccupyThenUniqueImportApplies", tests)
        self.assertIn("c10-import-never-c10", tests)
        self.assertIn("case requestMismatch", importer)
        self.assertIn("originalRequestID: String?", importer)
        self.assertIn('throw fail(.requestMismatch)', importer)
        self.assertIn("guard existing == requestID, self.entry == entry else", importer)
        run_tests = self.sources["Tests/CoreTests/WorkshopRunServerVerificationTests.swift"]
        self.assertIn("testOtherRequestIdDoesNotRewriteBoundOriginal", run_tests)
        self.assertIn("testMissingBindRequestIdStaysNilNeverEmptyString", run_tests)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueBindApplies", run_tests)
        self.assertIn("c10-run-never", run_tests)
        self.assertIn(
            "testOtherRequestIdCannotRewriteAuthorizedHold",
            self.sources["Tests/CoreTests/WorkshopInstallUpgradeRollbackTests.swift"])
        self.assertIn(
            "testNotHeldInstallOfNeverSeenIdDoesNotOccupyThenUniqueHoldApplies",
            self.sources["Tests/CoreTests/WorkshopInstallUpgradeRollbackTests.swift"])
        self.assertIn("c10-ins-never-c10",
                      self.sources["Tests/CoreTests/WorkshopInstallUpgradeRollbackTests.swift"])
        self.assertIn(
            "testOtherRequestIdCannotMutateFrozenOriginal",
            self.sources["Tests/CoreTests/WorkshopPackageVersionPublishTests.swift"])
        self.assertIn(
            "testNotReviewedFreezeOfNeverSeenIdDoesNotOccupyThenUniqueFreezeApplies",
            self.sources["Tests/CoreTests/WorkshopPackageVersionPublishTests.swift"])
        self.assertIn("c10-pub-never-c10",
                      self.sources["Tests/CoreTests/WorkshopPackageVersionPublishTests.swift"])
        answers = self.sources["Core/H5AnswerProtection.swift"]
        self.assertIn("case requestMismatch", answers)
        self.assertIn("guard existing == originalRequestID, matchedHash == serverFrozenHash else", answers)
        self.assertIn("req-a-other", self.sources["Tests/CoreTests/H5AnswerProtectionTests.swift"])
        answers_tests = self.sources["Tests/CoreTests/H5AnswerProtectionTests.swift"]
        self.assertIn("testHashMismatchOfNeverSeenIdDoesNotOccupyThenUniqueCompareApplies", answers_tests)
        self.assertIn("req-a-never-c10", answers_tests)
        session = self.sources["Core/H5SessionCapabilityGate.swift"]
        self.assertIn("case requestMismatch", session)
        self.assertIn("guard existingHost == host, admittedCapability == capability else", session)
        self.assertIn("location.once", self.sources["Tests/CoreTests/H5SessionCapabilityGateTests.swift"])

    def test_linux_xctest_app_ci_are_explicitly_not_run(self):
        self.assertIn("XCTest / App / CI = NOT_RUN", Path(__file__).read_text())
        self.assertIn("not 100%", (ROOT / HUNK).read_text())
        for path in TEST_FILES:
            self.assertIn("@testable import QuestifyCore", self.sources[path])

    def test_sha256_payload_covers_whitelist(self):
        hunk = (ROOT / HUNK).read_text()
        listed = {line.split()[1]: line.split()[0]
                  for line in hunk.splitlines() if re.fullmatch(r"[0-9a-f]{64} \S+", line)}
        hashed = CORE_FILES + TEST_FILES + [CONTRACT]
        digest = hashlib.sha256()
        for path in hashed:
            digest.update(path.encode())
            digest.update((ROOT / path).read_bytes())
            self.assertEqual(listed[path], hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), path)
        digest.update(HUNK.encode())
        digest.update((ROOT / HUNK).read_bytes())
        self.assertEqual(len(digest.hexdigest()), 64)
        for path in hashed:
            self.assertIn(path, hunk)


if __name__ == "__main__":
    unittest.main()
