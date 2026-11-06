from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Core/ChapterReplacementInvitation.swift"
COORD = ROOT / "Core/ChapterReplacementInvitationCoordinator.swift"
VIEW = ROOT / "App/ChapterReplacementInvitationView.swift"
UNIT = ROOT / "Tests/CoreTests/ChapterReplacementInvitationTests.swift"


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
            "struct ChapterReplacementInvitationPublisherProof",
            "isFreshTopicPublisher",
            "projectManageOwnerMapped",
            "publisherProof.verified",
            "ChapterReplacementInvitationFailure.notTopicPublisher",
        ]:
            self.assertIn(token, core)
        self.assertNotIn("topicPublisherVerified", core)
        self.assertNotIn("isFreshTopicPublisher: true", core)

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
        view = read(VIEW)
        self.assertNotIn("CLLocation", view)
        self.assertNotIn("requestWhenInUse", view)
        self.assertIn("coordinates: coordinates", view)

    def test_publisher_proof_is_injected_not_hardcoded(self):
        coord = read(COORD)
        view = read(VIEW)
        service = read("Core/MerchantContentService.swift")
        self.assertIn("guard let publisherProof else { phase = .failed(.notTopicPublisher); return }", coord)
        self.assertNotIn("isFreshTopicPublisher: true", coord)
        self.assertNotIn("isFreshTopicPublisher: true", view)
        self.assertNotIn("topicPublisherVerified", service)
        self.assertIn("publisherProof.verified", service)
        self.assertIn("publisherProof: ChapterReplacementInvitationPublisherProof?", view)

    def test_view_copy_is_bilingual_and_keeps_parameters(self):
        import json
        view = read(VIEW)
        self.assertNotRegex(view, r'Text\(verbatim: "[^"]*[\u4e00-\u9fff]')
        for key in [
            "chapterReplacement.intro",
            "chapterReplacement.vacancy.row",
            "chapterReplacement.candidate.member",
            "chapterReplacement.message.label",
            "chapterReplacement.message.prompt",
            "chapterReplacement.title",
            "chapterReplacement.review.invite",
            "chapterReplacement.review.pendingOnly",
            "chapterReplacement.unknown",
            "chapterReplacement.verified.application",
            "chapterReplacement.verified",
        ]:
            self.assertIn(key, view)
        self.assertIn("vacancy.withdrawReason", view)
        fragment = json.loads((ROOT / "Resources/ChapterReplacementInvitationLocalizations.fragment.json").read_text())["strings"]
        catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        required = {
            "chapterReplacement.vacancy.row %lld %lld": ("%1$lld", "%2$lld"),
            "chapterReplacement.candidate.member %lld": ("%lld",),
            "chapterReplacement.review.invite %lld %lld %lld": ("%1$lld", "%2$lld", "%3$lld"),
            "chapterReplacement.unknown %@": ("%@",),
            "chapterReplacement.verified.application %lld": ("%lld",),
        }
        self.assertGreaterEqual(len(fragment), 13)
        for key, tokens in required.items():
            self.assertEqual(catalog[key], fragment[key])
            for lang in ("en", "zh-Hans"):
                value = fragment[key]["localizations"][lang]["stringUnit"]["value"]
                for token in tokens:
                    self.assertIn(token, value)

    def test_shared_files_untouched_by_this_line(self):
        # C9 follow-up may touch only its exclusive files, its catalog fragment,
        # and the named shared call-site hunks. MerchantHome and AppSession stay out.
        import subprocess
        out = subprocess.run(
            ["git", "diff", "--name-only", "7ad0b6383480bab1839e3c824e3aaeacd1b9dc14"], cwd=ROOT,
            capture_output=True, text=True, check=True).stdout.split()
        allowed_shared = {
            "Core/MerchantContentCommands.swift",
            "Core/MerchantContentService.swift",
            "Core/CooperationFlowCoordinator.swift",
            "Core/CooperationFlowService.swift",
            "Core/CooperationProtectedDispatch.swift",
            "App/MerchantContentViews.swift",
            "App/MerchantHomeView.swift",
            "App/AppSession.swift",
            "App/AppCompositionRoot.swift",
            "App/MerchantOfferWithdrawalHostView.swift",
            "Resources/Localizable.xcstrings",
            "Tests/ContractChecks/test_chapter_execution_approval.py",
            "Tests/ContractChecks/test_chapter_replacement_invitation.py",
            "Tests/CoreTests/CooperationProtectedDispatchTests.swift",
        }
        for forbidden in ("Core/MerchantContentDomain.swift", "Core/MerchantContentCoordinator.swift"):
            self.assertNotIn(forbidden, out)
        for changed in out:
            self.assertTrue(
                "ChapterReplacementInvitation" in changed or changed in allowed_shared,
                f"C9 changed a non-exclusive file: {changed}")

    def test_c10_journal_withdraw_gate_and_publisher_read(self):
        session = read("App/AppSession.swift")
        home = read("App/MerchantHomeView.swift")
        host = read("App/MerchantOfferWithdrawalHostView.swift")
        service = read("Core/MerchantContentService.swift")
        content = session.split("lazy var merchantContentJournal")[1].split("private var retainedNearbyMerchants")[0]
        self.assertIn("MerchantContentFilePendingStorage", content)
        self.assertIn("journal: merchantContentJournal", content)
        self.assertNotIn("injectedOfflineHarness", content)
        self.assertNotIn("execution:", content)
        self.assertIn("MerchantOfferWithdrawalProtectedExecutor.gated", session)
        self.assertIn("api/coop/offer/withdraw", host)
        self.assertIn("guard permits() else { throw MerchantOfferWithdrawalFailure.disabled }", host)
        self.assertNotIn("permitsSubmission: Bool { true }", host)
        proof = service.split("Fresh `api/topic/info-to-user`")[1].split("fileprivate func chapterReplacementRows")[0]
        self.assertIn("chapterReplacementPublisherProof", proof)
        self.assertIn("api/topic/info-to-user", proof)
        self.assertNotIn("info-to-merchant", proof)
        self.assertIn("fromFreshTopicRead", proof)
        invite = service.split("sendInvite:")[1].split("loadOwnerListRows:")[0]
        self.assertIn("guard self.permits(.invite(", invite)
        self.assertNotIn("permitsWrites", invite)
        self.assertIn("catch MerchantContentFailure.disabled", invite)
        self.assertIn("merchantChapterReplacementContext", home)
        self.assertIn("coordinates: nil", home)
        self.assertNotIn("requestWhenInUse", home)
        self.assertNotIn("isFreshTopicPublisher: true", read("Core/ChapterReplacementInvitation.swift"))
        self.assertNotIn("isFreshTopicPublisher: true", read("App/ChapterReplacementInvitationView.swift"))

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
