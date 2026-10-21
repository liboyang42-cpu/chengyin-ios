from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Core/ChapterReplacementInvitation.swift"
COORD = ROOT / "Core/ChapterReplacementInvitationCoordinator.swift"
VIEW = ROOT / "App/ChapterReplacementInvitationView.swift"
UNIT = ROOT / "Tests/CoreTests/ChapterReplacementInvitationTests.swift"
SHARED = [
    "Core/MerchantContentCommands.swift",
    "Core/MerchantContentService.swift",
    "Core/MerchantContentDomain.swift",
    "App/MerchantContentViews.swift",
]


def read(path):
    return Path(path).read_text()


class ChapterReplacementInvitationContracts(unittest.TestCase):
    def test_wire_paths_and_exact_invite_fields(self):
        core = read(CORE)
        for token in [
            '"api/merchant/chapter-application/invitable"',
            '"api/merchant/chapter-application/invite"',
            '"api/merchant/chapter-application/owner-list"',
            '"api/merchant/chapter-application/owner-mine"',
            '"chapterId": .integer(candidate.chapterID)',
            '"merchantMemberId": .integer(candidate.merchantMemberID)',
            '"replacementOfOfferId": .integer(candidate.replacementOfOfferID)',
        ]:
            self.assertIn(token, core)
        # No requestId field is ever sent: UNKNOWN is tuple-verified only.
        for path in [CORE, COORD, VIEW]:
            self.assertNotIn('"requestId"', read(path))
            self.assertNotIn("requestID", read(path))

    def test_vacancy_candidate_and_scope_gates(self):
        core = read(CORE)
        for token in [
            "status == 0, !reason.isEmpty",
            "candidate.chapterID == vacancy.chapterID",
            "candidate.replacementOfOfferID == vacancy.offerID",
            "candidate.merchantMemberID != vacancy.originalMerchantMemberID",
            "row.replacementOfOfferID == vacancy.offerID",
            "access.isOwner",
            "access.allows(.projects)",
            "topicPublisherVerified",
            "ChapterReplacementInvitationFailure.notTopicPublisher",
        ]:
            self.assertIn(token, core)

    def test_no_auto_accept_supply_or_money_actions(self):
        core = read(CORE)
        self.assertIn("public var autoAccepts: Bool { false }", core)
        self.assertIn("public var fillsSupply: Bool { false }", core)
        self.assertIn("public var triggersPaymentOrRefund: Bool { false }", core)
        for path in [CORE, COORD, VIEW]:
            text = read(path)
            for forbidden in ["chapter-application/audit", "chapter-node/submit",
                              "api/payment", "api/refund", "respond"]:
                self.assertNotIn(forbidden, text)

    def test_unknown_never_resends_and_readback_is_exact_tuple(self):
        coord = read(COORD)
        self.assertIn("case unknown(ChapterReplacementInvitationPlan)", coord)
        self.assertEqual(coord.count("effects.sendInvite(plan)"), 1)
        verify = coord.split("public func verifyUnknown()")[1].split("private func verify(")[0]
        self.assertNotIn("sendInvite", verify)
        core = read(CORE)
        for token in [
            'row["replacementOfOfferId"].integer == plan.candidate.replacementOfOfferID',
            'row["source"].integer == 1',
            'row["status"].integer == 0',
            "duplicateReadback",
            "stateMismatch",
        ]:
            self.assertIn(token, core)

    def test_no_location_still_queries(self):
        core = read(CORE)
        self.assertIn("public let coordinates: ChapterReplacementInvitationCoordinates?", core)
        coord = read(COORD)
        self.assertIn("coordinates: ChapterReplacementInvitationCoordinates? = nil", coord)

    def test_shared_files_untouched_by_this_line(self):
        # C9 owns only the new ChapterReplacementInvitation* files; the shared
        # MerchantContent hunks are handed to C7 as unapplied text, never edited here.
        import subprocess
        out = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"], cwd=ROOT,
            capture_output=True, text=True, check=True).stdout.split()
        for shared in SHARED:
            self.assertNotIn(shared, out)
        for changed in out:
            self.assertTrue(
                "ChapterReplacementInvitation" in changed,
                f"C9 changed a non-exclusive file: {changed}")

    def test_unit_coverage_topics_present(self):
        unit = read(UNIT)
        for token in [
            "testMultipleVacanciesAndSameMerchantAcrossChaptersStayDistinct",
            "testLostResponseBecomesUnknownNeverResendsAndLateFillVerifies",
            "testTopicOrAccountChangeRetiresFrozenPlan",
            "testNonPublisherCannotInviteInEitherScope",
            "testMerchantScopeRequiresOwnerMappedProjectManage",
            "testExistingReplacementOrPendingApprovedApplicationBlocks",
            "testInvitableRequestRequiresTopicAndAllowsNoLocation",
        ]:
            self.assertIn(token, unit)


if __name__ == "__main__":
    unittest.main()
