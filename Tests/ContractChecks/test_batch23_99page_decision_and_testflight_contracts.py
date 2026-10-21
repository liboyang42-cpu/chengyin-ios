#!/usr/bin/env python3
"""Contract checks for Batch 23 99-Page Decision & TestFlight deliverables."""

from pathlib import Path
import re
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]


class Batch23PageByPage99DecisionAndTestFlightContractTests(unittest.TestCase):
    CORE_DELIVERABLES = [
        (
            "Core/MiniProgramPageByPage99DecisionLedgerContract.swift",
            "MiniProgramPageByPage99Decision",
        ),
        (
            "Core/ProductionSigningAndLocalXcconfigValidatorContract.swift",
            "ProductionSigningAndLocalXcconfig",
        ),
        (
            "Core/TestFlightInternalAndExternalSmokeMatrixContract.swift",
            "TestFlightInternalAndExternalSmoke",
        ),
        (
            "Core/ZeroRegressionLegacyServerIsolationGuardAudit.swift",
            "ZeroRegressionLegacyServerIsolation",
        ),
    ]

    APP_DELIVERABLES = [
        (
            "App/MiniProgramPageByPage99DecisionSectionView.swift",
            "MiniProgramPageByPage99DecisionSectionView",
        ),
        (
            "App/ProductionSigningAndLocalXcconfigSectionView.swift",
            "ProductionSigningAndLocalXcconfigSectionView",
        ),
        (
            "App/TestFlightInternalAndExternalSmokeSectionView.swift",
            "TestFlightInternalAndExternalSmokeSectionView",
        ),
        (
            "App/ZeroRegressionLegacyServerIsolationSectionView.swift",
            "ZeroRegressionLegacyServerIsolationSectionView",
        ),
        (
            "App/UltimateReleaseReadinessExecutiveSummaryView.swift",
            "UltimateReleaseReadinessExecutiveSummaryView",
        ),
    ]

    CORE_TEST_FILES = [
        "Tests/CoreTests/MiniProgramPageByPage99DecisionLedgerContractTests.swift",
        "Tests/CoreTests/ProductionSigningAndLocalXcconfigValidatorContractTests.swift",
        "Tests/CoreTests/TestFlightInternalAndExternalSmokeMatrixContractTests.swift",
        "Tests/CoreTests/ZeroRegressionLegacyServerIsolationGuardAuditTests.swift",
    ]

    APP_UNIT_TEST_FILES = [
        "Tests/AppUnitTests/MiniProgramPageByPage99DecisionSectionViewTests.swift",
        "Tests/AppUnitTests/ProductionSigningAndLocalXcconfigSectionViewTests.swift",
        "Tests/AppUnitTests/TestFlightInternalAndExternalSmokeSectionViewTests.swift",
        "Tests/AppUnitTests/ZeroRegressionLegacyServerIsolationSectionViewTests.swift",
        "Tests/AppUnitTests/UltimateReleaseReadinessExecutiveSummaryViewTests.swift",
    ]

    UNTRACKED_DOT_KEY_PATTERN = re.compile(
        r'(?<![\w.])Text\s*\(\s*"([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)"\s*\)'
    )

    def test_batch23_core_contracts_exist_and_expose_public_symbols(self) -> None:
        for rel_path, expected_symbol in self.CORE_DELIVERABLES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 23 Core deliverable: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn(expected_symbol, content, f"Missing {expected_symbol} in {rel_path}")
            self.assertIn("public ", content, f"Expected public API in {rel_path}")

    def test_batch23_app_views_exist_and_enforce_text_verbatim_discipline(self) -> None:
        for rel_path, expected_view in self.APP_DELIVERABLES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 23 App deliverable: {rel_path}")
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

    def test_batch23_core_and_app_unit_tests_exist(self) -> None:
        for rel_path in self.CORE_TEST_FILES + self.APP_UNIT_TEST_FILES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 23 test file: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn("XCTestCase", content, f"{rel_path} must define an XCTestCase")
            self.assertIn("func test", content, f"{rel_path} must contain test methods")


if __name__ == "__main__":
    unittest.main()
