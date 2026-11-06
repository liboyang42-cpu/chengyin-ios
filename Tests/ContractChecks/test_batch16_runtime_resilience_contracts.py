"""Source guards for Batch 16 runtime resilience, MetricKit diagnostics, push/Live Activity,
network retry backoff, Keychain/biometric session security, disk cache budgets, and scene-phase
lifecycle contracts and SwiftUI section views.
"""
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

BATCH16_CORE_TYPES = {
    "Core/CrashResilienceAndMetricKitDiagnosticsAudit.swift": "CrashResilienceAndMetricKitDiagnosticsAudit",
    "Core/PushNotificationAndLiveActivityParityAudit.swift": "PushNotificationAndLiveActivityParityAudit",
    "Core/NetworkReachabilityAndRetryBackoffAudit.swift": "NetworkReachabilityAndRetryBackoffAudit",
    "Core/KeychainAndBiometricSessionSecurityAudit.swift": "KeychainAndBiometricSessionSecurityAudit",
    "Core/ImageAndVideoDiskCacheBudgetAudit.swift": "ImageAndVideoDiskCacheBudgetAudit",
    "Core/BackgroundTaskAndScenePhaseLifecycleAudit.swift": "BackgroundTaskAndScenePhaseLifecycleAudit",
}

BATCH16_APP_VIEWS = {
    "App/CrashResilienceAndMetricKitDiagnosticsSectionView.swift": "CrashResilienceAndMetricKitDiagnosticsSectionView",
    "App/PushNotificationAndLiveActivitySectionView.swift": "PushNotificationAndLiveActivitySectionView",
    "App/NetworkReachabilityAndRetryBackoffSectionView.swift": "NetworkReachabilityAndRetryBackoffSectionView",
    "App/KeychainAndBiometricSessionSecuritySectionView.swift": "KeychainAndBiometricSessionSecuritySectionView",
    "App/ImageAndVideoDiskCacheBudgetSectionView.swift": "ImageAndVideoDiskCacheBudgetSectionView",
    "App/BackgroundTaskAndScenePhaseLifecycleSectionView.swift": "BackgroundTaskAndScenePhaseLifecycleSectionView",
}

BATCH16_CORE_TESTS = {
    "Tests/CoreTests/CrashResilienceAndMetricKitDiagnosticsAuditTests.swift": "CrashResilienceAndMetricKitDiagnosticsAuditTests",
    "Tests/CoreTests/PushNotificationAndLiveActivityParityAuditTests.swift": "PushNotificationAndLiveActivityParityAuditTests",
    "Tests/CoreTests/NetworkReachabilityAndRetryBackoffAuditTests.swift": "NetworkReachabilityAndRetryBackoffAuditTests",
    "Tests/CoreTests/KeychainAndBiometricSessionSecurityAuditTests.swift": "KeychainAndBiometricSessionSecurityAuditTests",
    "Tests/CoreTests/ImageAndVideoDiskCacheBudgetAuditTests.swift": "ImageAndVideoDiskCacheBudgetAuditTests",
    "Tests/CoreTests/BackgroundTaskAndScenePhaseLifecycleAuditTests.swift": "BackgroundTaskAndScenePhaseLifecycleAuditTests",
}

BATCH16_APP_UNIT_TESTS = {
    "Tests/AppUnitTests/CrashResilienceAndMetricKitDiagnosticsSectionViewTests.swift": "CrashResilienceAndMetricKitDiagnosticsSectionViewTests",
    "Tests/AppUnitTests/PushNotificationAndLiveActivitySectionViewTests.swift": "PushNotificationAndLiveActivitySectionViewTests",
    "Tests/AppUnitTests/NetworkReachabilityAndRetryBackoffSectionViewTests.swift": "NetworkReachabilityAndRetryBackoffSectionViewTests",
    "Tests/AppUnitTests/KeychainAndBiometricSessionSecuritySectionViewTests.swift": "KeychainAndBiometricSessionSecuritySectionViewTests",
    "Tests/AppUnitTests/ImageAndVideoDiskCacheBudgetSectionViewTests.swift": "ImageAndVideoDiskCacheBudgetSectionViewTests",
    "Tests/AppUnitTests/BackgroundTaskAndScenePhaseLifecycleSectionViewTests.swift": "BackgroundTaskAndScenePhaseLifecycleSectionViewTests",
}


class Batch16RuntimeResilienceContractTests(unittest.TestCase):
    def test_batch16_core_audits_exist_and_expose_public_types(self):
        for rel_path, symbol in BATCH16_CORE_TYPES.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing Core file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import Foundation", content, rel_path)
            self.assertIn(symbol, content, rel_path)
            self.assertIn("Sendable", content, rel_path)
            self.assertIn("Equatable", content, rel_path)

    def test_batch16_app_section_views_exist_and_use_text_verbatim_discipline(self):
        for rel_path, view_symbol in BATCH16_APP_VIEWS.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing App view file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import SwiftUI", content, rel_path)
            self.assertIn(f"public struct {view_symbol}: View", content, rel_path)
            self.assertIn("Text(verbatim:", content, rel_path)
            self.assertIn(".accessibilityIdentifier(", content, rel_path)

    def test_batch16_core_tests_and_app_unit_tests_exist(self):
        for rel_path, test_class in {**BATCH16_CORE_TESTS, **BATCH16_APP_UNIT_TESTS}.items():
            full_path = REPO_ROOT / rel_path
            self.assertTrue(full_path.is_file(), f"Missing test file: {rel_path}")
            content = full_path.read_text(encoding="utf-8")
            self.assertIn("import XCTest", content, rel_path)
            self.assertIn(f"final class {test_class}: XCTestCase", content, rel_path)
            self.assertIn("func test", content, rel_path)


if __name__ == "__main__":
    unittest.main()
