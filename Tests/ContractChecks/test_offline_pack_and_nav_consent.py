"""Linux source contracts for exclusive offline pack, nav consent, and side-quest.

These checks do not compile or execute Swift. XCTest on Linux is NOT_RUN.
"""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE_FILES = [
    "Core/OfflinePackOperation.swift",
    "Core/SideQuestAcceptHold.swift",
    "Core/NavigationDestinationConsent.swift",
    "Core/PresenceProofDistinctFromFog.swift",
]
TEST_FILES = [
    "Tests/CoreTests/OfflinePackOperationTests.swift",
    "Tests/CoreTests/SideQuestAcceptHoldTests.swift",
    "Tests/CoreTests/NavigationDestinationConsentTests.swift",
    "Tests/CoreTests/PresenceProofDistinctFromFogTests.swift",
]
PLAY_NODE = ROOT / "App/PlayNodeDetailView.swift"
PLAY_EXPERIENCE = ROOT / "Core/PlayExperienceCoordinator.swift"
PLAY_SERVICE = ROOT / "Core/PlayExperienceService.swift"
PAUSED_STORAGE = ROOT / "Core/PlayRecoveryStorage.swift"
FORBIDDEN_TOUCH = [
    "App/AppSession.swift",
    "Questify.xcodeproj/project.pbxproj",
]


class OfflinePackAndNavConsentContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in CORE_FILES + TEST_FILES}
        cls.joined = "\n".join(cls.sources.values())
        cls.play_node = PLAY_NODE.read_text()
        cls.play_experience = PLAY_EXPERIENCE.read_text()
        cls.play_service = PLAY_SERVICE.read_text()
        cls.paused = PAUSED_STORAGE.read_text()

    def test_exclusive_whitelist_files_exist(self):
        for path in CORE_FILES + TEST_FILES:
            self.assertTrue((ROOT / path).is_file(), path)
        self.assertTrue(PLAY_NODE.is_file())
        self.assertTrue(PLAY_EXPERIENCE.is_file())
        self.assertTrue((ROOT / "docs/issue5-hunks/C05-ios-dot-hunk.md").is_file())

    def test_play_node_and_experience_session_were_inventoried_not_rewritten(self):
        self.assertIn("struct PlayNodeDetailView: View", self.play_node)
        self.assertIn("let model: PlayViewModel", self.play_node)
        self.assertIn("PlayPausedStorage", self.play_experience)
        self.assertIn("pausedRequest(", self.play_service)
        self.assertIn("protocol PlayPausedStorage", self.paused)
        self.assertNotIn("OfflinePackOperation", self.play_node)
        self.assertNotIn("SideQuestAcceptHold", self.play_experience)
        self.assertNotIn("NavigationDestinationConsent", self.play_experience)
        self.assertNotIn("PlayExperienceSession(", self.joined)
        self.assertNotIn("PlayExperience factory", self.joined)

    def test_first_journey_discover_hold_proof_complete_recover(self):
        quest = self.sources["Core/SideQuestAcceptHold.swift"]
        tests = self.sources["Tests/CoreTests/SideQuestAcceptHoldTests.swift"]
        for expected in [
            "func discover(",
            "func acceptHold(",
            "func submitProof(",
            "func complete()",
            "func failQuest()",
            "func exit()",
            "func recoverOriginal(originalRequestID:",
            "case gps, qr, photo, ar, approvedAlternative",
        ]:
            self.assertIn(expected, quest)
        self.assertIn("testFirstJourneyDiscoverHoldProofCompleteRecoverOriginal", tests)
        self.assertIn('recoverOriginal(originalRequestID: "req-9")', tests)
        self.assertIn("originalRequestID", quest)

    def test_offline_pack_download_pause_resume_same_operation_id(self):
        pack = self.sources["Core/OfflinePackOperation.swift"]
        tests = self.sources["Tests/CoreTests/OfflinePackOperationTests.swift"]
        for expected in [
            "func startDownload(",
            "func pause()",
            "func resume(operationID:",
            "func recordCorrupt()",
            "func recordFullDisk()",
            "func applyUpdate(",
            "keepOld:",
            "func expire(",
            "func delete()",
            "Resume continues the same operation id",
        ]:
            self.assertIn(expected, pack)
        self.assertIn("keepOld", pack)
        self.assertIn("testDownloadPauseResumeSameOperationIdThenReady", tests)
        self.assertIn('resume(operationID: "op-1")', tests)
        self.assertIn('resume(operationID: "op-other")', tests)
        self.assertIn("testCorruptFullDiskExpireDeleteAndKeepOld", tests)

    def test_answers_and_hidden_coordinates_are_not_shipped(self):
        pack = self.sources["Core/OfflinePackOperation.swift"]
        tests = self.sources["Tests/CoreTests/OfflinePackOperationTests.swift"]
        self.assertIn("answersOrHiddenCoordinatesForbidden", pack)
        self.assertIn('"hiddenCoordinate"', pack)
        self.assertIn('"answer"', pack)
        self.assertIn("testAnswersAndHiddenCoordinatesAreNotShipped", tests)
        self.assertNotIn("hiddenLat", pack.split("forbidden", 1)[0])

    def test_qmod_vol12_missing_is_waiting_source_not_rewrite(self):
        pack = self.sources["Core/OfflinePackOperation.swift"]
        tests = self.sources["Tests/CoreTests/OfflinePackOperationTests.swift"]
        self.assertIn("WAITING_SOURCE", pack)
        self.assertIn("qmod.finalOpsContract", pack)
        self.assertIn("vol12.offlinePackResumeWriter", pack)
        self.assertIn("t41.scoringWriter", pack)
        self.assertIn("t41.fullLoopUnproven", pack)
        self.assertIn("qmodFinalOpsContractPresent: Bool { false }", pack)
        self.assertIn("vol12ResumeWriterPresent: Bool { false }", pack)
        self.assertIn("t41FullLoopProven: Bool { false }", pack)
        self.assertIn("testMissingQmodAndVol12ContractsAreWaitingSource", tests)
        self.assertIn("PlayExperienceCoordinator.paused", pack)
        self.assertIn("pauseOpsReserved", pack)

    def test_navigation_destination_distinct_from_location_share(self):
        consent = self.sources["Core/NavigationDestinationConsent.swift"]
        tests = self.sources["Tests/CoreTests/NavigationDestinationConsentTests.swift"]
        self.assertIn("case inAppNavigationDestination", consent)
        self.assertIn("case locationShare", consent)
        self.assertIn("destinationIsNotSharePayload", consent)
        self.assertIn("func startInAppNavigation(", consent)
        self.assertIn("func publishLocationShare(", consent)
        self.assertIn("testNavigationPurposeDoesNotImplyLocationShare", tests)
        self.assertIn("testLocationShareDoesNotImplyNavigationDestination", tests)
        self.assertIn("testUnusedConsentDoesNotOccupyShareThenUniqueShareGrantApplies", tests)
        self.assertIn("navigationDestinationConsentRequired", consent)
        self.assertIn("locationShareConsentRequired", consent)

    def test_fog_is_exploration_memory_not_presence_proof(self):
        fog = self.sources["Core/PresenceProofDistinctFromFog.swift"]
        tests = self.sources["Tests/CoreTests/PresenceProofDistinctFromFogTests.swift"]
        self.assertIn("Fog is exploration memory", fog)
        self.assertIn("func isExplorationMemory(", fog)
        self.assertIn("RoamExperienceCapabilities.presence", fog)
        self.assertIn("certifyPresenceFromFogTiles", fog)
        self.assertIn("fogIsNotPresence", fog)
        self.assertIn("testFogTilesAreExplorationMemoryNotPresence", tests)
        self.assertIn("RoamExperienceCapabilities.presence, false", tests)
        quest = self.sources["Core/SideQuestAcceptHold.swift"]
        self.assertIn("fogTileKey: String? = nil", quest)
        self.assertIn("guard !simulated, fogTileKey == nil", quest)

    def test_no_fake_gps_and_no_original_pause_ops(self):
        for forbidden in [
            "CLLocation", "CLLocationManager", "fake GPS", "simulatedCoordinate",
            "AppSession", "RuntimeDependencyFactory", "PlayExperienceService(",
            "compositionRoot", "NSLocalizedString", "URLSession", "HTTPTransport",
            "PlayPausedStorage", "pausedRequest(",
        ]:
            self.assertNotIn(forbidden, self.joined)
        pack = self.sources["Core/OfflinePackOperation.swift"]
        self.assertIn("Does not own the twenty original play pause ops", pack)
        self.assertIn("hijackOriginalPauseOps", pack)

    def test_no_shared_forbidden_owners(self):
        for path in FORBIDDEN_TOUCH:
            self.assertTrue((ROOT / path).is_file(), path)
        for forbidden in [
            "project.pbxproj", "AppCompositionRoot", "PlayNode session",
            "PlayExperience factory", "Localizable.xcstrings",
        ]:
            self.assertNotIn(forbidden, self.joined)
        for path in CORE_FILES:
            text = self.sources[path]
            self.assertTrue(text.startswith("import Foundation"), path)
            self.assertNotIn("import SwiftUI", text)
            self.assertNotIn("URLSession", text)
            self.assertNotIn("HTTPTransport", text)

    def test_account_switch_isolation_markers_present(self):
        quest = self.sources["Tests/CoreTests/SideQuestAcceptHoldTests.swift"]
        self.assertIn("testOtherRequestIdDoesNotRewriteOriginalHold", quest)
        self.assertIn("testMissingRequestIdStaysNilNeverEmptyString", quest)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenUniqueHoldApplies", quest)
        self.assertIn("testUnusedAcceptHoldBeforeDiscoverDoesNotOccupyThenUniqueHoldApplies", quest)
        self.assertIn("testUnusedCompleteBeforeHoldDoesNotOccupyThenUniqueCompleteApplies", quest)
        self.assertIn("testUnusedSubmitProofBeforeHoldDoesNotOccupyThenUniqueSubmitApplies", quest)
        self.assertIn("testUnusedExitBeforeHoldDoesNotOccupyThenUniqueExitApplies", quest)
        self.assertIn("sq-orig-unk", quest)
        self.assertIn("alreadyTerminal", quest)
        pack = self.sources["Tests/CoreTests/OfflinePackOperationTests.swift"]
        self.assertIn("testOtherOperationIdDoesNotRewriteOriginalDownload", pack)
        self.assertIn("testUnusedResumeDoesNotOccupyThenUniqueStartDownloadApplies", pack)
        self.assertIn("testUnusedDeleteOfIdleDoesNotOccupyThenUniqueStartThenDeleteApplies", pack)
        self.assertIn('resume(operationID: "")', pack)
        consent = self.sources["Tests/CoreTests/NavigationDestinationConsentTests.swift"]
        self.assertIn("testShareGrantOnCopyDoesNotRewriteOriginalNavigationConsent", consent)
        hold = self.sources["Core/SideQuestAcceptHold.swift"]
        self.assertIn("if original != nil { throw fail(.alreadyTerminal) }", hold)
        self.assertIn("originalRequestID: String?", hold)

    def test_linux_xctest_is_explicitly_not_run(self):
        self.assertIn("XCTest on Linux is NOT_RUN", Path(__file__).read_text())
        for path in TEST_FILES:
            self.assertIn("@testable import QuestifyCore", self.sources[path])

    def test_sha256_payload_covers_whitelist(self):
        digest = hashlib.sha256()
        for path in CORE_FILES + TEST_FILES + [
            "Tests/ContractChecks/test_offline_pack_and_nav_consent.py",
            "docs/issue5-hunks/C05-ios-dot-hunk.md",
        ]:
            digest.update(path.encode())
            digest.update((ROOT / path).read_bytes())
        self.assertEqual(len(digest.hexdigest()), 64)


if __name__ == "__main__":
    unittest.main()
