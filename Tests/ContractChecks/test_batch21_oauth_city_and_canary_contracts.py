"""Source guards for Batch 21 OAuth nonce/state security, city switch & cross-city roaming
data isolation, final 20-batch master completion manifest, and production canary rollout /
phased release contracts and SwiftUI views.
"""
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

BATCH21_CORE_TYPES = {
    "Core/WeChatAndAppleSignInNonceStateSecurityAudit.swift": "WeChatAndAppleSignInNonceStateSecurityAudit",
    "Core/CitySwitchAndCrossCityRoamingDataIsolationAudit.swift": "CitySwitchAndCrossCityRoamingDataIsolationAudit",
    "Core/FinalTwentyBatchMasterCompletionManifest.swift": "FinalTwentyBatchMasterCompletionManifest",
    "Core/ProductionCanaryRolloutAndPhasedReleaseContract.swift": "ProductionCanaryRolloutAndPhasedReleaseContract",
}

BATCH21_APP_VIEWS = {
    "App/WeChatAndAppleSignInNonceStateSectionView.swift": "WeChatAndAppleSignInNonceStateSectionView",
    "App/CitySwitchAndCrossCityRoamingSectionView.swift": "CitySwitchAndCrossCityRoamingSectionView",
    "App/FinalTwentyBatchMasterCompletionView.swift": "FinalTwentyBatchMasterCompletionView",
    "App/ProductionCanaryRolloutAndPhasedReleaseSectionView.swift": "ProductionCanaryRolloutAndPhasedReleaseSectionView",
}

BATCH21_CORE_TESTS = {
    "Tests/CoreTests/WeChatAndAppleSignInNonceStateSecurityAuditTests.swift": "WeChatAndAppleSignInNonceStateSecurityAuditTests",
    "Tests/CoreTests/CitySwitchAndCrossCityRoamingDataIsolationAuditTests.swift": "CitySwitchAndCrossCityRoamingDataIsolationAuditTests",
    "Tests/CoreTests/FinalTwentyBatchMasterCompletionManifestTests.swift": "FinalTwentyBatchMasterCompletionManifestTests",
    "Tests/CoreTests/ProductionCanaryRolloutAndPhasedReleaseContractTests.swift": "ProductionCanaryRolloutAndPhasedReleaseContractTests",
}

BATCH21_APP_UNIT_TESTS = {
    "Tests/AppUnitTests/WeChatAndAppleSignInNonceStateSectionViewTests.swift": "WeChatAndAppleSignInNonceStateSectionViewTests",
    "Tests/AppUnitTests/CitySwitchAndCrossCityRoamingSectionViewTests.swift": "CitySwitchAndCrossCityRoamingSectionViewTests",
    "Tests/AppUnitTests/FinalTwentyBatchMasterCompletionViewTests.swift": "FinalTwentyBatchMasterCompletionViewTests",
    "Tests/AppUnitTests/ProductionCanaryRolloutAndPhasedReleaseSectionViewTests.swift": "ProductionCanaryRolloutAndPhasedReleaseSectionViewTests",
}


class Batch21OAuthCityAndCanaryContractTests(unittest.TestCase):
    def test_batch21_core_contracts_exist_and_expose_public_types(self):
        for rel_path, symbol in BATCH21_CORE_TYPES.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing Core file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import Foundation", content, rel_path)
            self.assertIn(symbol, content, rel_path)
            self.assertIn("Sendable", content, rel_path)
            self.assertIn("Equatable", content, rel_path)

    def test_batch21_app_views_exist_and_use_text_verbatim_discipline(self):
        for rel_path, view_symbol in BATCH21_APP_VIEWS.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing App view file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import SwiftUI", content, rel_path)
            self.assertIn(f"public struct {view_symbol}: View", content, rel_path)
            self.assertIn("Text(verbatim:", content, rel_path)
            self.assertIn(".accessibilityIdentifier(", content, rel_path)

    def test_batch21_core_tests_and_app_unit_tests_exist(self):
        for rel_path, test_class in {**BATCH21_CORE_TESTS, **BATCH21_APP_UNIT_TESTS}.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing test file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import XCTest", content, rel_path)
            self.assertIn(f"final class {test_class}: XCTestCase", content, rel_path)
            self.assertIn("func test", content, rel_path)


if __name__ == "__main__":
    unittest.main()
