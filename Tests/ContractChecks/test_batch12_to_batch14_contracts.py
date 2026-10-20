import pathlib
import re
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


class Batch12ToBatch14ContractTests(unittest.TestCase):
    """Verifies Batch 12 & Batch 13 Core audit contracts and App SwiftUI diagnostic views."""

    BARE_LOCALIZED_TEXT_RE = re.compile(r'\bText\(\s*"')

    EXPECTED_CORE_CONTRACTS = {
        "Core/ReformWorkPackagesW02ToW20ComplianceAudit.swift": (
            "public enum ReformWorkPackageDomain",
            "public enum ReformWorkPackageID",
            "public struct ReformWorkPackageComplianceRecord",
            "ReformWorkPackagesW02ToW20ComplianceAudit",
        ),
        "Core/AppSessionCompositionAndFixtureShortCircuitAudit.swift": (
            "public struct AppSessionFenceSnapshot",
            "AppSessionCompositionAndFixtureShortCircuitAudit",
        ),
        "Core/XcodeGenAndProjectScaffoldIntegrityAudit.swift": (
            "public enum XcodeGenAndProjectScaffoldIntegrityAudit",
            "public enum CanonicalTarget",
        ),
        "Core/EndToEndReleaseCandidateReadinessGate.swift": (
            "public enum EndToEndReleaseCandidateReadinessGate",
            "public enum GateID",
        ),
        "Core/SideQuestAndPersonalFogHostAudit.swift": (
            "public enum SideQuestAndPersonalFogHostAudit",
            "public struct FeatureGateAuditInput",
        ),
        "Core/UITestFlowReadinessAnchorAudit.swift": (
            "public enum UITestFlowSurfaceID",
            "public struct UITestFlowReadinessAnchorRecord",
            "UITestFlowReadinessAnchorAudit",
        ),
        "Core/NPCChatAndSceneAISafetyAudit.swift": (
            "public enum NPCSafetyAuditedDataClass",
            "public enum NPCSafetyAuditedAuthorityEffect",
            "NPCChatAndSceneAISafetyAudit",
        ),
        "Core/PlayRuntimeAndAuxiliaryBindingAudit.swift": (
            "public enum PlayRuntimeAndAuxiliaryBindingAudit",
            "public enum Pillar",
        ),
        "Core/AppStorePrivacyManifestAndPermissionAudit.swift": (
            "public enum AppStorePrivacyManifestAndPermissionAudit",
            "public enum RequiredReasonAPICategory",
            "public enum RequiredUsageDescriptionKey",
        ),
        "Core/GrowthAndLeaderboardParityAudit.swift": (
            "public enum GrowthLeaderboardStandingAudit",
            "public enum GrowthProfileHTTPFailureKind",
            "public struct GrowthAndLeaderboardParityAudit",
        ),
        "Core/ScheduleAndLeadProgressPollingAudit.swift": (
            "public enum ScheduleAndLeadPollingAuditError",
            "public struct ClubSeriesScheduleDatesAuditInput",
            "ScheduleAndLeadProgressPollingAudit",
        ),
    }

    EXPECTED_APP_VIEWS = {
        "App/ReformWorkPackagesW02ToW20SectionView.swift": (
            "public struct ReformWorkPackagesW02ToW20SectionView: View",
        ),
        "App/AppSessionCompositionDiagnosticsSectionView.swift": (
            "public struct AppSessionCompositionDiagnosticsSectionView: View",
        ),
        "App/XcodeGenAndScaffoldDiagnosticsSectionView.swift": (
            "public struct XcodeGenAndScaffoldDiagnosticsSectionView: View",
        ),
        "App/EndToEndReleaseCandidateGateSectionView.swift": (
            "public struct EndToEndReleaseCandidateGateSectionView: View",
        ),
        "App/UnifiedReleaseAuditHubView.swift": (
            "public struct UnifiedReleaseAuditHubView: View",
        ),
        "App/SideQuestAndPersonalFogAuditSectionView.swift": (
            "public struct SideQuestAndPersonalFogAuditSectionView: View",
        ),
        "App/UITestFlowReadinessAnchorSectionView.swift": (
            "public struct UITestFlowReadinessAnchorSectionView: View",
        ),
        "App/NPCChatAndSceneAISafetySectionView.swift": (
            "public struct NPCChatAndSceneAISafetySectionView: View",
        ),
        "App/PlayRuntimeAndAuxiliaryBindingSectionView.swift": (
            "public struct PlayRuntimeAndAuxiliaryBindingSectionView: View",
        ),
        "App/AppStorePrivacyManifestSectionView.swift": (
            "public struct AppStorePrivacyManifestSectionView: View",
        ),
        "App/GrowthAndLeaderboardParitySectionView.swift": (
            "public struct GrowthAndLeaderboardParitySectionView: View",
        ),
        "App/ScheduleAndLeadProgressPollingSectionView.swift": (
            "public struct ScheduleAndLeadProgressPollingSectionView: View",
        ),
    }

    def test_batch12_and_batch13_core_contracts_exist_and_expose_public_types(self) -> None:
        for rel_path, expected_tokens in self.EXPECTED_CORE_CONTRACTS.items():
            with self.subTest(contract=rel_path):
                path = REPO_ROOT / rel_path
                self.assertTrue(path.is_file(), f"Missing Batch 12/13 Core contract: {rel_path}")
                content = path.read_text(encoding="utf-8")
                for token in expected_tokens:
                    self.assertIn(
                        token,
                        content,
                        f"Expected public symbol/token '{token}' in {rel_path}",
                    )

    def test_batch12_and_batch13_app_views_exist_and_use_text_verbatim_only(self) -> None:
        for rel_path, expected_tokens in self.EXPECTED_APP_VIEWS.items():
            with self.subTest(view=rel_path):
                path = REPO_ROOT / rel_path
                self.assertTrue(path.is_file(), f"Missing Batch 12/13 App view: {rel_path}")
                content = path.read_text(encoding="utf-8")
                for token in expected_tokens:
                    self.assertIn(
                        token,
                        content,
                        f"Expected view declaration '{token}' in {rel_path}",
                    )
                self.assertIn(
                    "Text(verbatim:",
                    content,
                    f"Expected Text(verbatim:) usage in {rel_path}",
                )
                bare_matches = self.BARE_LOCALIZED_TEXT_RE.findall(content)
                self.assertEqual(
                    len(bare_matches),
                    0,
                    f"Found bare localized Text(\"...\") calls in {rel_path}; use Text(verbatim:) instead",
                )


if __name__ == "__main__":
    unittest.main()
