"""Linux source contracts for exclusive C03 six-mechanism Core projections.

These checks do not compile or execute Swift. XCTest on Linux is NOT_RUN.
App / XCTest / CI = NOT_RUN. This is not 100%.
"""
from pathlib import Path
import hashlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
WHITELIST = [
    "Core/MechanismRequestIdProjection.swift",
    "Core/ProgressClockMomentumAspectProjection.swift",
    "Core/OathFlashbackProjection.swift",
    "Core/TradeBargainProjection.swift",
    "Core/OracleBountyProjection.swift",
    "Core/RouteCommunityDayProjection.swift",
    "Core/ClueSecretGoalProjection.swift",
    "Tests/CoreTests/MechanismRequestIdProjectionTests.swift",
    "Tests/CoreTests/ProgressClockMomentumAspectProjectionTests.swift",
    "Tests/CoreTests/OathFlashbackProjectionTests.swift",
    "Tests/CoreTests/TradeBargainProjectionTests.swift",
    "Tests/CoreTests/OracleBountyProjectionTests.swift",
    "Tests/CoreTests/RouteCommunityDayProjectionTests.swift",
    "Tests/CoreTests/ClueSecretGoalProjectionTests.swift",
    "Tests/ContractChecks/test_c03_six_mechanism_projections.py",
    "docs/issue5-hunks/C03-ios-dot-hunk.md",
]
CORE_FILES = [path for path in WHITELIST if path.startswith("Core/")]
TEST_FILES = [path for path in WHITELIST if path.startswith("Tests/CoreTests/")]
FORBIDDEN_TOUCH = [
    "App/AppSession.swift",
    "Questify.xcodeproj/project.pbxproj",
    "Core/PlayExperienceCoordinator.swift",
    "Core/PlayExperienceService.swift",
    "App/AppCompositionRoot.swift",
]
BASE = "origin/migration/native-ios"


def _git_names(*args):
    output = subprocess.check_output(["git", *args], cwd=ROOT, text=True)
    return {line for line in output.splitlines() if line}


class C03SixMechanismProjectionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in WHITELIST if path.endswith(".swift")}
        cls.joined = "\n".join(cls.sources.values())
        cls.hunk = (ROOT / "docs/issue5-hunks/C03-ios-dot-hunk.md").read_text()

    def test_exclusive_whitelist_files_exist(self):
        for path in WHITELIST:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_git_diff_against_native_ios_equals_whitelist(self):
        names = _git_names("diff", "--name-only", BASE)
        if not names:
            names = _git_names("diff", "--name-only", BASE, "HEAD")
        if not names:
            names = _git_names("ls-files", "--others", "--exclude-standard")
        self.assertEqual(names, set(WHITELIST), names.symmetric_difference(set(WHITELIST)))

    def test_first_journey_markers_present(self):
        for path in TEST_FILES:
            text = self.sources[path]
            self.assertIn("testFirstJourney", text, path)
            self.assertIn("RecoverOriginal", text, path)
            self.assertIn("originalRequestID", text, path)
            self.assertIn("simulate(", text, path)
            self.assertIn("MechanismStatus.unknown", text, path)

    def test_account_switch_isolation_markers_present(self):
        text = self.sources["Tests/CoreTests/MechanismRequestIdProjectionTests.swift"]
        self.assertIn("testOtherRequestDoesNotRewriteOriginalClock", text)
        self.assertIn("testInProcessRecoverKeepsOriginalAppliedAndUnknown", text)
        self.assertIn("testMissingRequestIDIsRefusedNeverStoredAsEmptyString", text)
        self.assertIn("testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenOneShotApplies", text)
        self.assertIn("c03-never-seen", text)
        trade_tests = self.sources["Tests/CoreTests/TradeBargainProjectionTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueAcceptApplies", trade_tests)
        self.assertIn("c03-bargain-never", trade_tests)
        oath_tests = self.sources["Tests/CoreTests/OathFlashbackProjectionTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueSwearApplies", oath_tests)
        self.assertIn("c03-oath-never", oath_tests)
        oracle_tests = self.sources["Tests/CoreTests/OracleBountyProjectionTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueConsultApplies", oracle_tests)
        self.assertIn("c03-oracle-never", oracle_tests)
        route_tests = self.sources["Tests/CoreTests/RouteCommunityDayProjectionTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueTakeSegmentApplies", route_tests)
        self.assertIn("c03-route-never", route_tests)
        clue_tests = self.sources["Tests/CoreTests/ClueSecretGoalProjectionTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueGainClueApplies", clue_tests)
        self.assertIn("c03-clue-never", clue_tests)
        clock_tests = self.sources["Tests/CoreTests/ProgressClockMomentumAspectProjectionTests.swift"]
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueTickApplies", clock_tests)
        self.assertIn("c03-clock-never", clock_tests)
        self.assertIn("missingOriginalRequestID", text)
        self.assertNotIn('requestId = ""', text)
        kernel = self.sources["Core/MechanismRequestIdProjection.swift"]
        self.assertIn("do not occupy the ledger", kernel)

    def test_original_request_id_on_apply_and_recover(self):
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertIn("originalRequestID", text, path)
            self.assertTrue(text.startswith("import Foundation"), path)
            self.assertNotIn("import SwiftUI", text)
            self.assertNotIn("@MainActor", text)
            if path.endswith("MechanismRequestIdProjection.swift"):
                self.assertIn("func oneShot(", text, path)
                self.assertIn("func recoverUnknown(", text, path)
                self.assertIn("func recoverOriginal(", text, path)
            else:
                self.assertIn("func apply(", text, path)
                self.assertIn("func recoverOriginal(", text, path)
                self.assertIn("func simulate(", text, path)

    def test_waiting_source_unsigned_originals(self):
        kernel = self.sources["Core/MechanismRequestIdProjection.swift"]
        self.assertIn("WAITING_SOURCE", kernel)
        self.assertIn("v12.docx", kernel)
        self.assertIn("232.pack", kernel)
        self.assertIn("e2d86c4", kernel)
        self.assertIn("v12DocxPresent: Bool { false }", kernel)
        self.assertIn("pack232Present: Bool { false }", kernel)
        self.assertIn("unpushedIosSHAPresent: Bool { false }", kernel)
        self.assertIn("OpenDecision", kernel)
        self.assertIn("JSON null", kernel)
        self.assertIn("Optional.none", kernel)
        self.assertIn("oneShot", kernel)
        self.assertIn("TICK_CLOCK", self.sources["Core/ProgressClockMomentumAspectProjection.swift"])
        self.assertIn("SPEND_MOMENTUM", self.sources["Core/ProgressClockMomentumAspectProjection.swift"])
        self.assertIn("INVOKE_ASPECT", self.sources["Core/ProgressClockMomentumAspectProjection.swift"])

    def test_passwords_and_economy_are_not_invented(self):
        oath = self.sources["Core/OathFlashbackProjection.swift"]
        clue = self.sources["Core/ClueSecretGoalProjection.swift"]
        trade = self.sources["Core/TradeBargainProjection.swift"]
        self.assertIn("never a global constant", oath)
        self.assertIn("OpenDecision", clue)
        self.assertIn("does not invent dice", trade)
        self.assertIn("clientClockForbidden", self.sources["Core/RouteCommunityDayProjection.swift"])
        self.assertIn("author-set-cipher", self.sources["Tests/CoreTests/OathFlashbackProjectionTests.swift"])
        self.assertIn("openDecision", self.sources["Tests/CoreTests/ClueSecretGoalProjectionTests.swift"])

    def test_no_shared_forbidden_owners(self):
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
        for forbidden in [
            "AppSession", "AppCompositionRoot", "project.pbxproj",
            "PlayExperienceCoordinator", "PlayExperienceService(",
            "PlayNode", "RouteEffects", "TopicRouteRuntime",
            "CmsTopic", "DynamicAttributeAuthoring",
            "Localizable.xcstrings", "URLSession", "HTTPTransport",
            "CLLocation", "fake GPS", "NSLocalizedString",
        ]:
            self.assertNotIn(forbidden, self.joined)

    def test_hunk_lists_exact_pbx_file_refs(self):
        self.assertIn("E799AC3B9E67E365F601BD10", self.hunk)
        self.assertIn("75D9ACF3AC751488C30D5065", self.hunk)
        self.assertIn("Core/MechanismRequestIdProjection.swift", self.hunk)
        self.assertIn("Tests/CoreTests/ClueSecretGoalProjectionTests.swift", self.hunk)
        self.assertIn("Do not edit pbxproj", self.hunk)
        self.assertIn("WAITING_SOURCE", self.hunk)
        self.assertIn("NOT_RUN", self.hunk)
        self.assertIn("not 100%", self.hunk.lower())

    def test_linux_xctest_is_explicitly_not_run(self):
        self.assertIn("XCTest on Linux is NOT_RUN", Path(__file__).read_text())
        self.assertIn("not 100%", Path(__file__).read_text())
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
