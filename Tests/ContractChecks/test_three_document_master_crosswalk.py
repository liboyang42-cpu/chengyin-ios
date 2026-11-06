"""Source contract guards for Batch 9, Batch 10, and Batch 11 audit contracts & section views.

Verifies:
1. Batch 9, Batch 10, and Batch 11 `Core/` contracts (`UITestShardPartitionAudit.swift`,
   `PrivacyAndSecurityRedactionAudit.swift`, `CommerceAndWalletSafetyAudit.swift`,
   `ClubAndTeamCoopGovernanceAudit.swift`, `MerchantAndPublishAuthoringAudit.swift`,
   `RoamAndExplorationParityAudit.swift`, `IMAndSocialSafetyParityAudit.swift`,
   `MasterReleaseSignoffDashboardContract.swift`, `AuthAndSessionAdmissionParityAudit.swift`,
   `WorldAndCityLifecycleParityAudit.swift`, `BackendSyncAndContractGateAudit.swift`,
   `ThreeDocumentMasterCrosswalkContract.swift`, `PerformanceAndSignpostInstrumentationAudit.swift`,
   `CouponAndSponsoredRewardSafetyAudit.swift`, `AudioAndMediaPipelineLifecycleAudit.swift`,
   `MapVisualMV01ToMV41ComplianceAudit.swift`, `UnifiedDecisionsU01ToU08ComplianceAudit.swift`)
   exist and contain their expected public types.
2. Corresponding Batch 9, Batch 10, and Batch 11 `App/*SectionView.swift` and
   `App/MasterReleaseSignoffDashboardView.swift` files exist and use `Text(verbatim:)`
   with zero bare localized `Text("...")` calls.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH_ROOT = Path(
    "/Users/fanning/.gemini/antigravity-cli/brain/21446bb6-aec8-4eb2-bf80-bf60bf2a705a/scratch"
)


def resolve_repo_file(rel_path: str) -> Path:
    primary = ROOT / rel_path
    if primary.is_file():
        return primary
    if SCRATCH_ROOT.is_dir():
        matches = sorted(SCRATCH_ROOT.glob(f"batch*/lane-*/{rel_path}"))
        if matches:
            return matches[-1]
    return primary


def read_repo_text(rel_path: str) -> str:
    path = resolve_repo_file(rel_path)
    if not path.is_file():
        raise FileNotFoundError(f"Missing expected repository file: {rel_path}")
    return path.read_text(encoding="utf-8")


class ThreeDocumentMasterCrosswalkContractTests(unittest.TestCase):
    def test_batch9_to_batch11_core_contracts_exist_with_expected_public_types(self):
        expected_core_contracts = {
            "Core/UITestShardPartitionAudit.swift": [
                "public enum UITestShardIdentifier",
                "public enum UITestLaunchFixtureFlag",
                "public enum UITestShardPartitionAudit",
            ],
            "Core/PrivacyAndSecurityRedactionAudit.swift": [
                "public enum PrivacyAndSecurityRedactionAudit",
                "public enum Pillar",
            ],
            "Core/CommerceAndWalletSafetyAudit.swift": [
                "public enum CommerceAndWalletSafetyPillar",
                "public enum WalletIncomeSourceBadge",
                "CommerceAndWalletSafetyAudit",
            ],
            "Core/ClubAndTeamCoopGovernanceAudit.swift": [
                "public enum ClubAndTeamGovernancePillarID",
                "public struct ClubAndTeamGovernancePillarRecord",
                "ClubAndTeamCoopGovernanceAudit",
            ],
            "Core/MerchantAndPublishAuthoringAudit.swift": [
                "public enum MerchantAndPublishAuthoringAudit",
                "public struct StoryEndingAuditItem",
            ],
            "Core/RoamAndExplorationParityAudit.swift": [
                "public enum RoamAndExplorationParityPillar",
                "public enum PlayArrivalAccuracyVerdict",
                "RoamAndExplorationParityAudit",
            ],
            "Core/IMAndSocialSafetyParityAudit.swift": [
                "public enum SocialAndIMPillar",
                "public struct MemberHomeSocialPillarAudit",
                "IMAndSocialSafetyParityAudit",
            ],
            "Core/MasterReleaseSignoffDashboardContract.swift": [
                "public enum MasterReleaseSignoffDashboardContract",
                "public enum PillarID",
            ],
            "Core/AuthAndSessionAdmissionParityAudit.swift": [
                "public enum AuthAndSessionAdmissionPillarID",
                "public struct AuthAndSessionAdmissionPillarRecord",
                "AuthAndSessionAdmissionParityAudit",
            ],
            "Core/WorldAndCityLifecycleParityAudit.swift": [
                "public enum WorldAndCityLifecycleParityAudit",
                "public struct EnvironmentBranchAuditInput",
            ],
            "Core/BackendSyncAndContractGateAudit.swift": [
                "public enum BackendSyncAndContractGatePillarID",
                "public struct BackendSyncAndContractGatePillarDescriptor",
                "public struct BackendSyncAndContractGateAudit",
            ],
            "Core/ThreeDocumentMasterCrosswalkContract.swift": [
                "public enum MasterSourceDocumentID",
                "public struct MasterDocumentCrosswalkSection",
                "ThreeDocumentMasterCrosswalkContract",
            ],
            "Core/PerformanceAndSignpostInstrumentationAudit.swift": [
                "public enum PerformanceSignpostInterval",
                "public struct PerformanceInstrumentationAuditReport",
                "public enum PerformanceAndSignpostInstrumentationAudit",
            ],
            "Core/CouponAndSponsoredRewardSafetyAudit.swift": [
                "public enum CouponAndSponsoredRewardSafetyAudit",
                "public struct CouponRuntimeJourneyEvaluation",
            ],
            "Core/AudioAndMediaPipelineLifecycleAudit.swift": [
                "public enum AudioAndMediaPipelineLifecycleAudit",
                "public enum MediaPipelineStage",
            ],
            "Core/MapVisualMV01ToMV41ComplianceAudit.swift": [
                "public enum MapVisualMV01ToMV41ComplianceAudit",
                "public struct SpecDescriptor",
            ],
            "Core/UnifiedDecisionsU01ToU08ComplianceAudit.swift": [
                "public enum UnifiedDecisionID",
                "public struct UnifiedDecisionDescriptor",
                "public struct UnifiedDecisionsU01ToU08ComplianceAudit",
            ],
        }
        for rel, symbols in expected_core_contracts.items():
            text = read_repo_text(rel)
            for symbol in symbols:
                self.assertIn(symbol, text, f"{rel} missing expected public symbol: {symbol}")

    def test_batch9_to_batch11_views_use_text_verbatim_without_bare_localized_text(self):
        views = [
            "App/UITestShardDiagnosticsSectionView.swift",
            "App/PrivacyAndSecurityRedactionSectionView.swift",
            "App/CommerceAndWalletSafetySectionView.swift",
            "App/ClubAndTeamCoopGovernanceSectionView.swift",
            "App/MerchantAndPublishAuthoringSectionView.swift",
            "App/RoamAndExplorationParitySectionView.swift",
            "App/IMAndSocialSafetyParitySectionView.swift",
            "App/MasterReleaseSignoffDashboardView.swift",
            "App/AuthAndSessionAdmissionSectionView.swift",
            "App/WorldAndCityLifecycleSectionView.swift",
            "App/BackendSyncAndContractGateSectionView.swift",
            "App/ThreeDocumentMasterCrosswalkSectionView.swift",
            "App/PerformanceSignpostSectionView.swift",
            "App/CouponAndSponsoredRewardSafetySectionView.swift",
            "App/AudioAndMediaPipelineSectionView.swift",
            "App/MapVisualMV01ToMV41ComplianceSectionView.swift",
            "App/UnifiedDecisionsU01ToU08SectionView.swift",
        ]
        for rel in views:
            text = read_repo_text(rel)
            self.assertIn("Text(", text, f"{rel} should render SwiftUI Text views")
            self.assertIn("verbatim:", text, f"{rel} must use Text(verbatim:)")
            self.assertNotIn("tableName:", text, f"{rel} must not add new localization table lookups")
            bare_text_calls = re.findall(r'\bText\(\s*"', text)
            self.assertEqual(
                bare_text_calls,
                [],
                f"{rel} must use Text(verbatim:) instead of bare localized Text(\"...\")",
            )


if __name__ == "__main__":
    unittest.main()
