"""Linux source contracts for exclusive ordinary city-orienteering selector.

These checks do not compile or execute Swift. XCTest on Linux is NOT_RUN;
only python source contracts run here.
"""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE_FILES = [
    "Core/OrdinaryCityCourseSelector.swift",
    "Core/OrienteeringSafetyVersion.swift",
    "Core/TeamClubEligibilityProjection.swift",
    "Core/EventScoreVersionProjection.swift",
]
TEST_FILES = [
    "Tests/CoreTests/OrdinaryCityCourseSelectorTests.swift",
    "Tests/CoreTests/TeamClubEligibilityProjectionTests.swift",
]
PLAY_NODE = ROOT / "App/PlayNodeDetailView.swift"


class OrdinaryCityCourseSelectorContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {path: (ROOT / path).read_text() for path in CORE_FILES + TEST_FILES}
        cls.joined = "\n".join(cls.sources.values())
        cls.play_node = PLAY_NODE.read_text()

    def test_exclusive_whitelist_files_exist(self):
        for path in CORE_FILES + TEST_FILES:
            self.assertTrue((ROOT / path).is_file(), path)
        self.assertTrue(PLAY_NODE.is_file())

    def test_play_node_detail_was_inventoried_and_not_rewritten(self):
        self.assertIn("struct PlayNodeDetailView: View", self.play_node)
        self.assertIn("let model: PlayViewModel", self.play_node)
        self.assertNotIn("OrdinaryCityCourseSelector", self.play_node)
        self.assertNotIn("EventScoreStartPayload", self.play_node)
        self.assertNotIn("fake GPS", self.play_node)
        self.assertNotIn("PlayExperienceSession(", self.joined)

    def test_first_journey_select_safety_team_freeze_finish_dispute(self):
        selector = self.sources["Core/OrdinaryCityCourseSelector.swift"]
        safety = self.sources["Core/OrienteeringSafetyVersion.swift"]
        eligibility = self.sources["Core/TeamClubEligibilityProjection.swift"]
        score = self.sources["Core/EventScoreVersionProjection.swift"]
        tests = self.sources["Tests/CoreTests/OrdinaryCityCourseSelectorTests.swift"]
        for expected in [
            "ORDINARY_CITY_ORIENTEERING",
            "prepareStart(",
            "OrienteeringSafetyVersion.display",
            "TeamClubEligibilityProjection.evaluate",
            "EventScoreVersionProjection.freeze",
        ]:
            self.assertIn(expected, selector)
        self.assertIn("cityCivilDate(now: Date, timeZone: TimeZone)", safety)
        self.assertIn("calendar.timeZone = timeZone", safety)
        self.assertNotIn("TimeZone.current", safety)
        self.assertNotIn("TimeZone.autoupdatingCurrent", self.joined)
        self.assertIn('participationMode == OrdinaryCityCourseSelector.teamMode', eligibility)
        self.assertIn("MULTI_CLUB_UNSATISFIED", eligibility)
        self.assertIn("resultVersionID: selection.publishedRuleVersionID", score)
        self.assertIn("frozenRuleVersionID", score)
        self.assertIn("func finish(", score)
        self.assertIn("func dispute(", score)
        self.assertIn("testFirstJourneyFreezesRuleVersionForFinishAndDispute", tests)
        self.assertIn('EventScoreVersionProjection.finish(start: start.payload, resultVersionID: "rule-v3")', tests)
        self.assertIn('EventScoreVersionProjection.dispute(start: start.payload, resultVersionID: "rule-v3")', tests)

    def test_rejects_growth_rank_matchmaking_and_fake_gps(self):
        selector = self.sources["Core/OrdinaryCityCourseSelector.swift"]
        eligibility = self.sources["Core/TeamClubEligibilityProjection.swift"]
        tests = self.joined
        self.assertIn('record.kind == ordinaryKind', selector)
        self.assertIn("record.latitude == nil, record.longitude == nil, record.accuracyMeters == nil", selector)
        self.assertIn('record.matchmakingStatus == nil || record.matchmakingStatus == cancelledMatchmaking', selector)
        self.assertIn("growthRankGrantsEligibility", eligibility)
        self.assertIn("rejectsCancelledMatchmaking", eligibility)
        self.assertIn("GROWTH_PERSONAL_RANK", tests)
        self.assertIn("RANDOM_MATCH", tests)
        self.assertIn('"latitude":31.2', tests)
        self.assertIn("return false", eligibility.split("growthRankGrantsEligibility", 1)[1].split("}", 1)[0])
        for forbidden in [
            "CLLocation", "CLLocationManager", "fake GPS", "simulatedCoordinate",
            "GrowthCenterRecord", "GrowthBoardQuery", "AppSession", "RuntimeDependencyFactory",
            "PlayExperienceService(", "compositionRoot", "NSLocalizedString",
        ]:
            self.assertNotIn(forbidden, self.joined)

    def test_no_shared_forbidden_owners(self):
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

    def test_account_switch_recover_and_missing_request_id(self):
        tests = self.sources["Tests/CoreTests/OrdinaryCityCourseSelectorTests.swift"]
        eligibility_tests = self.sources["Tests/CoreTests/TeamClubEligibilityProjectionTests.swift"]
        score = self.sources["Core/EventScoreVersionProjection.swift"]
        eligibility = self.sources["Core/TeamClubEligibilityProjection.swift"]
        selector = self.sources["Core/OrdinaryCityCourseSelector.swift"]
        self.assertIn("testOtherTeamRegisterFinishRequestDoesNotRewriteOriginalFreezeFinishRequestID", tests)
        self.assertIn("testInProcessRecoverKeepsOriginalFinishedAndNotFoundUnknown", tests)
        self.assertIn("testMissingBlankRequestIDStaysOptionalNoneOrTypedNotFoundNeverEmptyString", tests)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenUniqueWriteApplies", tests)
        self.assertIn("testLedgerRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueFinishApplies", tests)
        self.assertIn("testLedgerRecoverOriginalOfNeverSeenStartIdDoesNotOccupyThenUniqueFreezeApplies", tests)
        self.assertIn("testUnusedFinishOfUnfrozenStartDoesNotOccupyThenUniqueFreezeThenFinishApplies", tests)
        self.assertIn("c04-fin-class", tests)
        self.assertIn("c04-sta-class", tests)
        self.assertIn("testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenUniqueRegisterApplies", eligibility_tests)
        self.assertIn("testUnusedIneligibleRegisterDoesNotOccupyThenUniqueRegisterApplies", eligibility_tests)
        self.assertIn("fin-orig-unk", tests)
        self.assertIn("reg-orig-unk", eligibility_tests)
        self.assertIn("testOtherTeamRegisterRequestDoesNotRewriteOriginalRequestID", eligibility_tests)
        self.assertIn("originalRequestID", score)
        self.assertIn("originalRequestID", eligibility)
        self.assertIn("func recoverUnknown(", score)
        self.assertIn("func recoverOriginal(", score)
        self.assertIn("recoverFromOriginalRewardRead", score)
        self.assertIn("orientation.originalRewardRead", score)
        self.assertIn("testRecoverFromOriginalRewardReadDoesNotOccupyThenUniqueFactApplies", tests)
        self.assertIn("recoverFromScoringReceipt", score)
        self.assertIn("orientScoring.receipt", score)
        self.assertIn("async throws", score)
        self.assertIn("case int(Int64)", score)
        self.assertIn("case transport(String)", score)
        self.assertIn("testRecoverFromScoringReceiptReadsOriginalWithoutOccupyingFinishLedger", tests)
        self.assertIn("recoverFromSessionReceipt", score)
        self.assertIn("orientSession.receipt", score)
        self.assertIn("testRecoverFromSessionReceiptReadsOriginalWithoutOccupyingFinishLedger", tests)
        self.assertIn("func recoverUnknown(", eligibility)
        self.assertIn("func recoverOriginal(", eligibility)
        self.assertIn("NOT_FOUND", score)
        self.assertIn("FINISHED", score)
        self.assertIn("Optional.none", score)
        self.assertIn("EVENT_IDEMPOTENCY_CONFLICT", score)
        self.assertIn("mintedNewRequest: false", score)
        self.assertIn("EventScoreOriginalLedger", selector)
        self.assertNotIn('requestId = ""', self.joined)
        self.assertNotIn('originalRequestID = ""', self.joined)
        self.assertIn("XCTAssertNil(EventScoreRequestIdentity.parse(nil))", tests)
        self.assertIn('XCTAssertNil(EventScoreRequestIdentity.parse(""))', tests)
        self.assertIn("EventScoreOriginalOutcome.notFound", tests)
        self.assertIn(".finished", tests)
        self.assertIn("fin-isol-02", tests)
        self.assertIn("reg-isol-01", eligibility_tests)

    def test_draft_explore_unpublished_gps_and_growth_stay_rejected(self):
        tests = self.sources["Tests/CoreTests/OrdinaryCityCourseSelectorTests.swift"]
        score = self.sources["Core/EventScoreVersionProjection.swift"]
        self.assertIn('"publicationStatus":"DRAFT"', tests)
        self.assertIn('"publicationStatus":"UNPUBLISHED"', tests)
        self.assertIn("FREE_EXPLORATION", tests)
        self.assertIn("GROWTH_PERSONAL_RANK", tests)
        self.assertIn('"latitude":31.2', tests)
        self.assertIn("rejectsGPSEvidence", score)
        self.assertIn("growthLeaderboardSubstitutesEventScore", score)
        self.assertIn("testGPSEvidenceAndGrowthLeaderboardStayRejected", tests)
        self.assertIn("return false", score.split("growthLeaderboardSubstitutesEventScore", 1)[1].split("}", 1)[0])

    def test_waiting_source_leftovers_named_not_invented(self):
        selector = self.sources["Core/OrdinaryCityCourseSelector.swift"]
        self.assertIn("WAITING_SOURCE", selector)
        self.assertIn("vol.21", selector)
        self.assertIn("vol.22", selector)
        self.assertIn("vol.25-App", selector)
        self.assertIn("vol.38", selector)
        self.assertIn("e2d86c4", selector)
        self.assertIn("host-session-wiring", selector)
        self.assertIn("vol21Present: Bool { false }", selector)
        self.assertIn("unpushedIosSHAPresent: Bool { false }", selector)

    def test_linux_xctest_is_explicitly_not_run(self):
        self.assertIn("XCTest on Linux is NOT_RUN", Path(__file__).read_text())
        self.assertIn("only python source contracts run here", Path(__file__).read_text())
        self.assertIn("@testable import QuestifyCore", self.sources["Tests/CoreTests/OrdinaryCityCourseSelectorTests.swift"])
        self.assertIn("@testable import QuestifyCore", self.sources["Tests/CoreTests/TeamClubEligibilityProjectionTests.swift"])

    def test_sha256_payload_covers_whitelist(self):
        digest = hashlib.sha256()
        for path in CORE_FILES + TEST_FILES + ["Tests/ContractChecks/test_ordinary_city_course_selector.py"]:
            digest.update(path.encode())
            digest.update((ROOT / path).read_bytes())
        self.assertEqual(len(digest.hexdigest()), 64)


if __name__ == "__main__":
    unittest.main()
