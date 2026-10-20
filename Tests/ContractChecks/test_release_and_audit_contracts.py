"""Source contract guards for ReformWorldHostWorkbenchView and Batch 7/8 release & audit contracts.

Verifies:
1. `App/ReformWorldHostWorkbenchView.swift` exists and embeds `ReleasePreflightDiagnosticsView`,
   `RunAuthorityHostSectionView`, and `NPCAISceneGuardSectionView`.
2. Batch 7 & Batch 8 `Core/` contracts (`AppStoreSubmissionReadinessAudit.swift`,
   `UnifiedTicketExecutionMatrix.swift`, `MiniProgram99PageParityRegistry.swift`,
   `CloudCIShardExecutionContract.swift`, `Wave3HandoffVerificationRegistry.swift`,
   `RegionalEndpointAllowlistAudit.swift`, `LocalizationZeroMissingKeysAudit.swift`,
   `AccessibilityVoiceOverAndDynamicTypeAudit.swift`, `OfflineDurableRecoveryAudit.swift`)
   exist and contain their expected public types.
3. Batch 7 & Batch 8 `App/*SectionView.swift` files use `Text(verbatim:)` with zero bare
   localized `Text("...")` calls.
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


class ReleaseAndAuditContractsTests(unittest.TestCase):
    def test_reform_world_host_workbench_view_embeds_required_sections(self):
        rel = "App/ReformWorldHostWorkbenchView.swift"
        text = read_repo_text(rel)
        self.assertIn("public struct ReformWorldHostWorkbenchView: View", text)
        self.assertIn("ReleasePreflightDiagnosticsView", text)
        self.assertIn("RunAuthorityHostSectionView", text)
        self.assertIn("NPCAISceneGuardSectionView", text)
        self.assertIn("Text(verbatim:", text)
        bare_text_calls = re.findall(r'\bText\(\s*"', text)
        self.assertEqual(
            bare_text_calls,
            [],
            f"{rel} must use Text(verbatim:) with zero bare localized Text(\"...\") calls",
        )

    def test_batch7_and_batch8_core_audit_contracts_exist_with_expected_public_types(self):
        expected_core_contracts = {
            "Core/AppStoreSubmissionReadinessAudit.swift": [
                "public enum AppStoreSubmissionReadinessAudit",
                "public enum CheckID",
                "public enum PrivacyUsageKey",
            ],
            "Core/UnifiedTicketExecutionMatrix.swift": [
                "public enum UnifiedTicketExecutionMatrix",
                "public struct ImplementationPhase",
                "public enum MapVisualCategory",
            ],
            "Core/MiniProgram99PageParityRegistry.swift": [
                "public enum MiniProgramAlignmentDomain",
                "public struct MiniProgramWave2ScopeDescriptor",
                "public struct MiniProgramPageParityEntry",
                "public struct MiniProgram99PageParityRegistry",
            ],
            "Core/CloudCIShardExecutionContract.swift": [
                "public enum CloudCIRunnerOS",
                "public enum CloudCIControlGate",
                "public enum CloudCITestShard",
                "public enum CloudCIShardExecutionContract",
            ],
            "Core/Wave3HandoffVerificationRegistry.swift": [
                "public enum Wave3HandoffVerificationRegistry",
                "public enum LaneID",
                "public enum BackendPrerequisiteID",
            ],
            "Core/RegionalEndpointAllowlistAudit.swift": [
                "public enum RegionalHighRiskWriteRoute",
                "public struct RegionalEndpointAuditReport",
                "public enum RegionalEndpointAllowlistAudit",
            ],
            "Core/LocalizationZeroMissingKeysAudit.swift": [
                "public enum LocalizationCatalogName",
                "public struct LocalizationZeroMissingKeysAuditReport",
                "public enum LocalizationZeroMissingKeysAudit",
            ],
            "Core/AccessibilityVoiceOverAndDynamicTypeAudit.swift": [
                "public enum AccessibilityAuditSurface",
                "public struct VoiceOverElementSpec",
                "public struct AccessibilityAuditReport",
                "public enum AccessibilityVoiceOverAndDynamicTypeAudit",
            ],
            "Core/OfflineDurableRecoveryAudit.swift": [
                "public enum OfflineDurableRecoveryPillarID",
                "public struct OfflineDurableRecoveryPillarDescriptor",
                "public struct OfflineDurableRecoveryAudit",
            ],
        }
        for rel, symbols in expected_core_contracts.items():
            text = read_repo_text(rel)
            for symbol in symbols:
                self.assertIn(symbol, text, f"{rel} missing expected public symbol: {symbol}")

    def test_batch7_and_batch8_section_views_use_text_verbatim_without_bare_localized_text(self):
        section_views = [
            "App/AppStoreSubmissionReadinessSectionView.swift",
            "App/UnifiedTicketExecutionMatrixSectionView.swift",
            "App/MiniProgram99PageParitySectionView.swift",
            "App/CloudCIShardStatusSectionView.swift",
            "App/Wave3HandoffStatusSectionView.swift",
            "App/RegionalEndpointAllowlistSectionView.swift",
            "App/LocalizationCompletenessSectionView.swift",
            "App/AccessibilityReadinessSectionView.swift",
            "App/OfflineDurableRecoverySectionView.swift",
            "App/DeepLinkSafetyDiagnosticsSectionView.swift",
        ]
        for rel in section_views:
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

    def test_regional_endpoint_release_blockers_separate_safely_closed_from_releasable(self):
        core = read_repo_text("Core/RegionalEndpointAllowlistAudit.swift")
        for symbol in ("enum ReleaseBlocker", "case emptyBaseURL", "case missingRealm",
                       "case missingApprovedConfiguration", "var isSafelyClosed",
                       "var isBusinessReleasable", "realm: String? = nil"):
            self.assertIn(symbol, core)
        view = read_repo_text("App/RegionalEndpointAllowlistSectionView.swift")
        for symbol in ("isReleaseReady", "RELEASE BLOCKER", "regionalAllowlist.releaseBlocker"):
            self.assertIn(symbol, view)
        self.assertIn("ReleaseBlocker.allCases", view)  # default is blocked, never green
        launch = read_repo_text("App/RegionalLaunchConfiguration.swift")
        self.assertIn("approved:[RegionalMarket:Set<String>]=[:]", launch)
        self.assertNotIn("47.103.124.64", launch)


if __name__ == "__main__":
    unittest.main()
