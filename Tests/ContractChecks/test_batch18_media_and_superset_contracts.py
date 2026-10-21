"""Contract checks for Batch 18 media permission degradation, haptic/motion compliance,
telemetry privacy redaction, journal corruption recovery, App Store review demo readiness,
and native superset policy deliverables.
"""
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]

BATCH18_CORE_MODULES = [
    (
        "Core/PhotoLibraryAndCameraPermissionGracefulDegradationAudit.swift",
        "PhotoLibraryAndCameraPermissionGracefulDegradationAudit",
    ),
    (
        "Core/HapticFeedbackAndMotionReduceComplianceAudit.swift",
        "HapticFeedbackAndMotionReduceComplianceAudit",
    ),
    (
        "Core/ProductionTelemetryAndPrivacyRedactionPipelineAudit.swift",
        "ProductionTelemetryAndPrivacyRedactionPipelineAudit",
    ),
    (
        "Core/SQLiteAndJSONJournalCorruptionRecoveryAudit.swift",
        "SQLiteAndJSONJournalCorruptionRecoveryAudit",
    ),
    (
        "Core/AppStoreReviewDemoAccountAndFixtureReadinessAudit.swift",
        "AppStoreReviewDemoAccountAndFixtureReadinessAudit",
    ),
    (
        "Core/NativeSupersetOverMiniProgramPolicyAudit.swift",
        "NativeSupersetOverMiniProgramPolicyAudit",
    ),
]

BATCH18_APP_VIEWS = [
    (
        "App/PhotoLibraryAndCameraPermissionSectionView.swift",
        "PhotoLibraryAndCameraPermissionSectionView",
    ),
    (
        "App/HapticFeedbackAndMotionReduceSectionView.swift",
        "HapticFeedbackAndMotionReduceSectionView",
    ),
    (
        "App/ProductionTelemetryAndPrivacyRedactionSectionView.swift",
        "ProductionTelemetryAndPrivacyRedactionSectionView",
    ),
    (
        "App/SQLiteAndJSONJournalCorruptionRecoverySectionView.swift",
        "SQLiteAndJSONJournalCorruptionRecoverySectionView",
    ),
    (
        "App/AppStoreReviewDemoAccountAndFixtureSectionView.swift",
        "AppStoreReviewDemoAccountAndFixtureSectionView",
    ),
    (
        "App/NativeSupersetOverMiniProgramSectionView.swift",
        "NativeSupersetOverMiniProgramSectionView",
    ),
]

BATCH18_CORE_TESTS = [
    "Tests/CoreTests/PhotoLibraryAndCameraPermissionGracefulDegradationAuditTests.swift",
    "Tests/CoreTests/HapticFeedbackAndMotionReduceComplianceAuditTests.swift",
    "Tests/CoreTests/ProductionTelemetryAndPrivacyRedactionPipelineAuditTests.swift",
    "Tests/CoreTests/SQLiteAndJSONJournalCorruptionRecoveryAuditTests.swift",
    "Tests/CoreTests/AppStoreReviewDemoAccountAndFixtureReadinessAuditTests.swift",
    "Tests/CoreTests/NativeSupersetOverMiniProgramPolicyAuditTests.swift",
]

BATCH18_APP_UNIT_TESTS = [
    "Tests/AppUnitTests/PhotoLibraryAndCameraPermissionSectionViewTests.swift",
    "Tests/AppUnitTests/HapticFeedbackAndMotionReduceSectionViewTests.swift",
    "Tests/AppUnitTests/ProductionTelemetryAndPrivacyRedactionSectionViewTests.swift",
    "Tests/AppUnitTests/SQLiteAndJSONJournalCorruptionRecoverySectionViewTests.swift",
    "Tests/AppUnitTests/AppStoreReviewDemoAccountAndFixtureSectionViewTests.swift",
    "Tests/AppUnitTests/NativeSupersetOverMiniProgramSectionViewTests.swift",
]


class Batch18MediaAndSupersetContractTests(unittest.TestCase):
    def test_batch18_core_audits_exist_and_expose_public_types(self):
        for rel_path, expected_symbol in BATCH18_CORE_MODULES:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 18 Core file: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn(expected_symbol, content, f"Missing symbol {expected_symbol} in {rel_path}")
            self.assertIn("Sendable", content, f"Missing Sendable conformance in {rel_path}")
            self.assertIn("Equatable", content, f"Missing Equatable conformance in {rel_path}")
            for forbidden in ("URLSession", "URLRequest", "http://", "https://"):
                self.assertNotIn(forbidden, content, f"Forbidden token {forbidden} in {rel_path}")

    def test_batch18_app_section_views_use_verbatim_text_and_accessibility_hooks(self):
        for rel_path, expected_view in BATCH18_APP_VIEWS:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 18 App view file: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn("import SwiftUI", content, f"Missing SwiftUI import in {rel_path}")
            self.assertIn(f"public struct {expected_view}: View", content, f"Missing public View {expected_view} in {rel_path}")
            self.assertIn("Text(verbatim:", content, f"Expected Text(verbatim:) in {rel_path}")
            self.assertIn(".accessibilityIdentifier(", content, f"Expected accessibilityIdentifier hooks in {rel_path}")

    def test_batch18_core_and_app_unit_tests_exist(self):
        for rel_path in BATCH18_CORE_TESTS + BATCH18_APP_UNIT_TESTS:
            path = REPO_ROOT / rel_path
            self.assertTrue(path.is_file(), f"Missing Batch 18 unit test file: {rel_path}")
            content = path.read_text(encoding="utf-8")
            self.assertIn("XCTestCase", content, f"Missing XCTestCase in {rel_path}")
            self.assertIn("func test", content, f"Missing test methods in {rel_path}")


if __name__ == "__main__":
    unittest.main()
