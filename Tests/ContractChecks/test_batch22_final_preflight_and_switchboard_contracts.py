#!/usr/bin/env python3
"""Contract checks for Batch 22 Final Preflight & Switchboard deliverables."""

from pathlib import Path
import re
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]


class Batch22FinalPreflightAndSwitchboardContractTests(unittest.TestCase):
    CORE_DELIVERABLES = [
        (
            "Core/DeepLinkToMiniProgramPathTranslatorAudit.swift",
            "DeepLinkToMiniProgramPathTranslatorAudit",
        ),
        (
            "Core/WeChatShareCardAndPosterExportParityAudit.swift",
            "WeChatShareCardAndPosterExportParityAudit",
        ),
        (
            "Core/AppStoreSubmissionFinalPreflightGateRunner.swift",
            "AppStoreSubmissionFinalPreflightGateRunner",
        ),
        (
            "Core/BackendRolloutAllowlistSwitchboardContract.swift",
            "BackendRolloutAllowlistSwitchboard",
        ),
        (
            "Core/AppStoreReviewRejectionPreventionPlaybookContract.swift",
            "AppStoreReviewRejectionPrevention",
        ),
    ]

    APP_DELIVERABLES = [
        (
            "App/DeepLinkToMiniProgramPathTranslatorSectionView.swift",
            "DeepLinkToMiniProgramPathTranslatorSectionView",
        ),
        (
            "App/WeChatShareCardAndPosterExportSectionView.swift",
            "WeChatShareCardAndPosterExportSectionView",
        ),
        (
            "App/AppStoreSubmissionFinalPreflightGateView.swift",
            "AppStoreSubmissionFinalPreflightGateView",
        ),
        (
            "App/BackendRolloutAllowlistSwitchboardSectionView.swift",
            "BackendRolloutAllowlistSwitchboardSectionView",
        ),
        (
            "App/AppStoreReviewRejectionPreventionSectionView.swift",
            "AppStoreReviewRejectionPreventionSectionView",
        ),
    ]

    CORE_TEST_FILES = [
        "Tests/CoreTests/DeepLinkToMiniProgramPathTranslatorAuditTests.swift",
        "Tests/CoreTests/WeChatShareCardAndPosterExportParityAuditTests.swift",
        "Tests/CoreTests/AppStoreSubmissionFinalPreflightGateRunnerTests.swift",
        "Tests/CoreTests/BackendRolloutAllowlistSwitchboardContractTests.swift",
        "Tests/CoreTests/AppStoreReviewRejectionPreventionPlaybookContractTests.swift",
    ]

    APP_UNIT_TEST_FILES = [
        "Tests/AppUnitTests/DeepLinkToMiniProgramPathTranslatorSectionViewTests.swift",
        "Tests/AppUnitTests/WeChatShareCardAndPosterExportSectionViewTests.swift",
        "Tests/AppUnitTests/AppStoreSubmissionFinalPreflightGateViewTests.swift",
        "Tests/AppUnitTests/BackendRolloutAllowlistSwitchboardSectionViewTests.swift",
        "Tests/AppUnitTests/AppStoreReviewRejectionPreventionSectionViewTests.swift",
    ]

    UNTRACKED_DOT_KEY_PATTERN = re.compile(
        r'(?<![\w.])Text\s*\(\s*"([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)"\s*\)'
    )

    def test_batch22_core_contracts_exist_and_expose_public_symbols(self) -> None:
        for rel_path, expected_symbol in self.CORE_DELIVERABLES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 22 Core deliverable: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn(expected_symbol, content, f"Missing {expected_symbol} in {rel_path}")
            self.assertIn("public ", content, f"Expected public API in {rel_path}")

    def test_batch22_app_views_exist_and_enforce_text_verbatim_discipline(self) -> None:
        for rel_path, expected_view in self.APP_DELIVERABLES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 22 App deliverable: {rel_path}")
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

    def test_batch22_core_and_app_unit_tests_exist(self) -> None:
        for rel_path in self.CORE_TEST_FILES + self.APP_UNIT_TEST_FILES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 22 test file: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn("XCTestCase", content, f"{rel_path} must define an XCTestCase")
            self.assertIn("func test", content, f"{rel_path} must contain test methods")


if __name__ == "__main__":
    unittest.main()
