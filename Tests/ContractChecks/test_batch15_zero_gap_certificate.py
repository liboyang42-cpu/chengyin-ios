#!/usr/bin/env python3
"""Contract checks for Batch 15 Zero-Gap Certificate deliverables."""

from pathlib import Path
import re
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]


class Batch15ZeroGapCertificateContractTests(unittest.TestCase):
    CORE_DELIVERABLES = [
        (
            "Core/GameJournalCompositionAndPlaySummaryAudit.swift",
            "GameJournalCompositionAndPlaySummaryAudit",
        ),
        (
            "Core/SocialGraphAndProfilePrivacyParityAudit.swift",
            "SocialGraphAndProfilePrivacyParityAudit",
        ),
        (
            "Core/ExplorationPrivateToolsAndCapsuleAudit.swift",
            "ExplorationPrivateToolsAndCapsuleAudit",
        ),
        (
            "Core/PublishTopicAndCommentModerationAudit.swift",
            "PublishTopicAndCommentModerationAudit",
        ),
        (
            "Core/MemberSubscriptionAndOrderInvoiceAudit.swift",
            "MemberSubscriptionAndOrderInvoiceAudit",
        ),
        (
            "Core/FinalReleaseSignoffAndZeroGapCertificateContract.swift",
            "FinalReleaseSignoffAndZeroGapCertificate",
        ),
    ]

    APP_DELIVERABLES = [
        (
            "App/GameJournalCompositionAndPlaySummarySectionView.swift",
            "GameJournalCompositionAndPlaySummarySectionView",
        ),
        (
            "App/SocialGraphAndProfilePrivacySectionView.swift",
            "SocialGraphAndProfilePrivacySectionView",
        ),
        (
            "App/ExplorationPrivateToolsAndCapsuleSectionView.swift",
            "ExplorationPrivateToolsAndCapsuleSectionView",
        ),
        (
            "App/PublishTopicAndCommentModerationSectionView.swift",
            "PublishTopicAndCommentModerationSectionView",
        ),
        (
            "App/MemberSubscriptionAndOrderInvoiceSectionView.swift",
            "MemberSubscriptionAndOrderInvoiceSectionView",
        ),
        (
            "App/FinalReleaseSignoffAndZeroGapCertificateView.swift",
            "FinalReleaseSignoffAndZeroGapCertificateView",
        ),
    ]

    CORE_TEST_FILES = [
        "Tests/CoreTests/GameJournalCompositionAndPlaySummaryAuditTests.swift",
        "Tests/CoreTests/SocialGraphAndProfilePrivacyParityAuditTests.swift",
        "Tests/CoreTests/ExplorationPrivateToolsAndCapsuleAuditTests.swift",
        "Tests/CoreTests/PublishTopicAndCommentModerationAuditTests.swift",
        "Tests/CoreTests/MemberSubscriptionAndOrderInvoiceAuditTests.swift",
        "Tests/CoreTests/FinalReleaseSignoffAndZeroGapCertificateContractTests.swift",
    ]

    APP_UNIT_TEST_FILES = [
        "Tests/AppUnitTests/GameJournalCompositionAndPlaySummarySectionViewTests.swift",
        "Tests/AppUnitTests/SocialGraphAndProfilePrivacySectionViewTests.swift",
        "Tests/AppUnitTests/ExplorationPrivateToolsAndCapsuleSectionViewTests.swift",
        "Tests/AppUnitTests/PublishTopicAndCommentModerationSectionViewTests.swift",
        "Tests/AppUnitTests/MemberSubscriptionAndOrderInvoiceSectionViewTests.swift",
        "Tests/AppUnitTests/FinalReleaseSignoffAndZeroGapCertificateViewTests.swift",
    ]

    UNTRACKED_DOT_KEY_PATTERN = re.compile(
        r'(?<![\w.])Text\s*\(\s*"([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)"\s*\)'
    )

    def test_batch15_core_audit_contracts_exist_and_expose_public_symbols(self) -> None:
        for rel_path, expected_symbol in self.CORE_DELIVERABLES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 15 Core deliverable: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn(expected_symbol, content, f"Missing {expected_symbol} in {rel_path}")
            self.assertIn("public ", content, f"Expected public API in {rel_path}")

    def test_batch15_app_views_exist_and_enforce_text_verbatim_discipline(self) -> None:
        for rel_path, expected_view in self.APP_DELIVERABLES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 15 App deliverable: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn(f"public struct {expected_view}: View", content)
            self.assertIn("Text(verbatim:", content, f"{rel_path} must use Text(verbatim:)")
            self.assertIn(".accessibilityIdentifier(", content, f"{rel_path} must expose accessibility identifiers")
            untracked = self.UNTRACKED_DOT_KEY_PATTERN.findall(content)
            self.assertEqual(
                untracked,
                [],
                f"{rel_path} must not introduce untracked dot-separated Text keys: {untracked}",
            )

    def test_batch15_core_and_app_unit_tests_exist(self) -> None:
        for rel_path in self.CORE_TEST_FILES + self.APP_UNIT_TEST_FILES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 15 test file: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn("XCTestCase", content, f"{rel_path} must define an XCTestCase")
            self.assertIn("func test", content, f"{rel_path} must contain test methods")

    def test_a4_and_a5_formal_evidence_and_fail_closed_ledger_contracts(self) -> None:
        a4_core = (REPO_ROOT / "Core/FinalReleaseSignoffAndZeroGapCertificateContract.swift").read_text(encoding="utf-8")
        self.assertIn("public enum ReleaseEvidenceOrigin", a4_core)
        self.assertIn("public static func isValidFormalCommitSHA(_ raw: String) -> Bool", a4_core)
        self.assertIn("public static func canonicalRequiredCount(forPillarID id: String) -> Int?", a4_core)
        self.assertIn("public static func isCanonicalPillarCertified(", a4_core)
        self.assertIn("evidenceOrigin: .previewFixture", a4_core)

        a4_view = (REPO_ROOT / "App/FinalReleaseSignoffAndZeroGapCertificateView.swift").read_text(encoding="utf-8")
        self.assertIn("FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(", a4_view)
        self.assertIn("FinalReleaseSignoffAndZeroGapCertificateContract.isCanonicalPillarCertified(", a4_view)
        self.assertIn("FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(", a4_view)

        a5_ledger = (REPO_ROOT / "Core/MiniProgramPageByPage99DecisionLedgerContract.swift").read_text(encoding="utf-8")
        self.assertIn("codeStatus: .pending", a5_ledger)
        self.assertIn("wiringStatus: .pending", a5_ledger)
        self.assertIn("canonical99PageRouteSet", a5_ledger)
        self.assertNotIn("codeStatus: .passed,\n                        wiringStatus: .passed", a5_ledger)

        a5_registry = (REPO_ROOT / "Core/MiniProgram99PageParityRegistry.swift").read_text(encoding="utf-8")
        self.assertIn("verifiedBaselineTargetsByRoute", a5_registry)
        self.assertIn("public var isSourceMappingVerified: Bool", a5_registry)
        self.assertNotIn("nativeReaderOrPresentationContract: row.decisionMode.rawValue", a5_registry)

        a5_crosswalk = (REPO_ROOT / "Core/ThreeDocumentMasterCrosswalkContract.swift").read_text(encoding="utf-8")
        self.assertIn("public static let clientTrackingWorkPackageSubIDs: [String]", a5_crosswalk)
        self.assertIn("public static let clientTracking176EnumerationIDs: [String]", a5_crosswalk)
        self.assertIn("mappedItems: []", a5_crosswalk)
        self.assertNotIn("mappedItems: doc1Items", a5_crosswalk)
        self.assertNotIn("mappedItems: doc2Items", a5_crosswalk)
        self.assertNotIn("mappedItems: doc3Items", a5_crosswalk)


if __name__ == "__main__":
    unittest.main()
