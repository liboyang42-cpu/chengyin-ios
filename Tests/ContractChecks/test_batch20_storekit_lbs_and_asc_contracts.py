"""Source guards for Batch 20 StoreKit 2 subscription & refund lifecycle, LBS geofence &
battery/thermal budget, cold-start launch latency & prewarm, App Store Connect metadata &
screenshot matrix, and mini-program vs native superset classifier section view.
"""
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

BATCH20_CORE_TYPES = {
    "Core/StoreKit2SubscriptionAndRefundLifecycleAudit.swift": "StoreKit2SubscriptionAndRefundLifecycleAudit",
    "Core/LBSGeofenceAndBatteryThermalBudgetAudit.swift": "LBSGeofenceAndBatteryThermalBudgetAudit",
    "Core/ColdStartLaunchLatencyAndPrewarmAudit.swift": "ColdStartLaunchLatencyAndPrewarmAudit",
    "Core/AppStoreConnectMetadataAndScreenshotMatrixContract.swift": "AppStoreConnectMetadataAndScreenshotMatrixContract",
}

BATCH20_APP_VIEWS = {
    "App/StoreKit2SubscriptionAndRefundSectionView.swift": "StoreKit2SubscriptionAndRefundSectionView",
    "App/LBSGeofenceAndBatteryThermalSectionView.swift": "LBSGeofenceAndBatteryThermalSectionView",
    "App/ColdStartLaunchLatencyAndPrewarmSectionView.swift": "ColdStartLaunchLatencyAndPrewarmSectionView",
    "App/AppStoreConnectMetadataAndScreenshotSectionView.swift": "AppStoreConnectMetadataAndScreenshotSectionView",
    "App/MiniProgramVsNativeSupersetClassifierSectionView.swift": "MiniProgramVsNativeSupersetClassifierSectionView",
}

BATCH20_CORE_TESTS = {
    "Tests/CoreTests/StoreKit2SubscriptionAndRefundLifecycleAuditTests.swift": "StoreKit2SubscriptionAndRefundLifecycleAuditTests",
    "Tests/CoreTests/LBSGeofenceAndBatteryThermalBudgetAuditTests.swift": "LBSGeofenceAndBatteryThermalBudgetAuditTests",
    "Tests/CoreTests/ColdStartLaunchLatencyAndPrewarmAuditTests.swift": "ColdStartLaunchLatencyAndPrewarmAuditTests",
    "Tests/CoreTests/AppStoreConnectMetadataAndScreenshotMatrixContractTests.swift": "AppStoreConnectMetadataAndScreenshotMatrixContractTests",
}

BATCH20_APP_UNIT_TESTS = {
    "Tests/AppUnitTests/StoreKit2SubscriptionAndRefundSectionViewTests.swift": "StoreKit2SubscriptionAndRefundSectionViewTests",
    "Tests/AppUnitTests/LBSGeofenceAndBatteryThermalSectionViewTests.swift": "LBSGeofenceAndBatteryThermalSectionViewTests",
    "Tests/AppUnitTests/ColdStartLaunchLatencyAndPrewarmSectionViewTests.swift": "ColdStartLaunchLatencyAndPrewarmSectionViewTests",
    "Tests/AppUnitTests/AppStoreConnectMetadataAndScreenshotSectionViewTests.swift": "AppStoreConnectMetadataAndScreenshotSectionViewTests",
    "Tests/AppUnitTests/MiniProgramVsNativeSupersetClassifierSectionViewTests.swift": "MiniProgramVsNativeSupersetClassifierSectionViewTests",
}


class Batch20StoreKitLBSAndASCContractTests(unittest.TestCase):
    def test_batch20_core_contracts_exist_and_expose_public_types(self):
        for rel_path, symbol in BATCH20_CORE_TYPES.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing Core file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import Foundation", content, rel_path)
            self.assertIn(symbol, content, rel_path)
            self.assertIn("Sendable", content, rel_path)
            self.assertIn("Equatable", content, rel_path)

    def test_batch20_app_views_exist_and_use_text_verbatim_discipline(self):
        for rel_path, view_symbol in BATCH20_APP_VIEWS.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing App view file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import SwiftUI", content, rel_path)
            self.assertIn(f"public struct {view_symbol}: View", content, rel_path)
            self.assertIn("Text(verbatim:", content, rel_path)
            self.assertIn(".accessibilityIdentifier(", content, rel_path)

    def test_batch20_core_tests_and_app_unit_tests_exist(self):
        for rel_path, test_class in {**BATCH20_CORE_TESTS, **BATCH20_APP_UNIT_TESTS}.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing test file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import XCTest", content, rel_path)
            self.assertIn(f"final class {test_class}: XCTestCase", content, rel_path)
            self.assertIn("func test", content, rel_path)


if __name__ == "__main__":
    unittest.main()
