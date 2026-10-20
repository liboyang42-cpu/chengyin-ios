"""Source guards for Batch 19 7-day launch critical-path milestone contracts, customer support
and feedback parity, account deletion GDPR/PIPL compliance, mini-program vs native superset
page classifier, and master 7-day launch command center view.
"""
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

BATCH19_CORE_TYPES = {
    "Core/SevenDayLaunchCriticalPathMilestoneContract.swift": "SevenDayLaunchCriticalPathMilestoneContract",
    "Core/InAppCustomerSupportAndFeedbackParityAudit.swift": "InAppCustomerSupportAndFeedbackParityAudit",
    "Core/AccountDeletionAndGDPRPIPLComplianceAudit.swift": "AccountDeletionAndGDPRPIPLComplianceAudit",
    "Core/MiniProgramVsNativeSupersetPageClassifier.swift": "MiniProgramVsNativeSupersetPageClassifier",
}

BATCH19_APP_VIEWS = {
    "App/SevenDayLaunchCriticalPathSectionView.swift": "SevenDayLaunchCriticalPathSectionView",
    "App/InAppCustomerSupportAndFeedbackSectionView.swift": "InAppCustomerSupportAndFeedbackSectionView",
    "App/AccountDeletionAndGDPRPIPLSectionView.swift": "AccountDeletionAndGDPRPIPLSectionView",
    "App/MasterSevenDayLaunchCommandCenterView.swift": "MasterSevenDayLaunchCommandCenterView",
}

BATCH19_CORE_TESTS = {
    "Tests/CoreTests/SevenDayLaunchCriticalPathMilestoneContractTests.swift": "SevenDayLaunchCriticalPathMilestoneContractTests",
    "Tests/CoreTests/InAppCustomerSupportAndFeedbackParityAuditTests.swift": "InAppCustomerSupportAndFeedbackParityAuditTests",
    "Tests/CoreTests/AccountDeletionAndGDPRPIPLComplianceAuditTests.swift": "AccountDeletionAndGDPRPIPLComplianceAuditTests",
    "Tests/CoreTests/MiniProgramVsNativeSupersetPageClassifierTests.swift": "MiniProgramVsNativeSupersetPageClassifierTests",
}

BATCH19_APP_UNIT_TESTS = {
    "Tests/AppUnitTests/SevenDayLaunchCriticalPathSectionViewTests.swift": "SevenDayLaunchCriticalPathSectionViewTests",
    "Tests/AppUnitTests/InAppCustomerSupportAndFeedbackSectionViewTests.swift": "InAppCustomerSupportAndFeedbackSectionViewTests",
    "Tests/AppUnitTests/AccountDeletionAndGDPRPIPLSectionViewTests.swift": "AccountDeletionAndGDPRPIPLSectionViewTests",
    "Tests/AppUnitTests/MasterSevenDayLaunchCommandCenterViewTests.swift": "MasterSevenDayLaunchCommandCenterViewTests",
}


class Batch19SevenDayLaunchContractTests(unittest.TestCase):
    def test_batch19_core_contracts_exist_and_expose_public_types(self):
        for rel_path, symbol in BATCH19_CORE_TYPES.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing Core file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import Foundation", content, rel_path)
            self.assertIn(symbol, content, rel_path)
            self.assertIn("Sendable", content, rel_path)
            self.assertIn("Equatable", content, rel_path)

    def test_batch19_app_views_exist_and_use_text_verbatim_discipline(self):
        for rel_path, view_symbol in BATCH19_APP_VIEWS.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing App view file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import SwiftUI", content, rel_path)
            self.assertIn(f"public struct {view_symbol}: View", content, rel_path)
            self.assertIn("Text(verbatim:", content, rel_path)
            self.assertIn(".accessibilityIdentifier(", content, rel_path)

    def test_batch19_core_tests_and_app_unit_tests_exist(self):
        for rel_path, test_class in {**BATCH19_CORE_TESTS, **BATCH19_APP_UNIT_TESTS}.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing test file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import XCTest", content, rel_path)
            self.assertIn(f"final class {test_class}: XCTestCase", content, rel_path)
            self.assertIn("func test", content, rel_path)


if __name__ == "__main__":
    unittest.main()
