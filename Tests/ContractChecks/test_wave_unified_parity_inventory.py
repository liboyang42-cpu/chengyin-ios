"""Source and documentation inventory guards for Wave 2, Wave 3, and Reform Plan v9 (Batch 4/5).

Verifies:
1. All 21 Wave-2 parity docs (`docs/parity/w2-01.md` .. `docs/parity/w2-21.md`) exist and are non-empty.
2. All Wave-3 handoff docs (`docs/handoff/ios-I00-I11-20261019.md`, `ios-I01-20261019.md` .. `ios-I10-20261019.md`,
   `ios-BK-20261019.md`) and `docs/plan-progress/{F,G,H}-20261019.md` exist and are non-empty.
3. Batch 4 & Batch 5 `Core/*.swift` and `App/*SectionView.swift` / `App/ReleasePreflightDiagnosticsView.swift`
   files exist and contain their expected public types and fail-closed defaults (`47.103.124.64` forbidden host
   check, `Text(verbatim:)` usage in Batch 5 views).
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


class WaveUnifiedParityInventoryContractTests(unittest.TestCase):
    def test_all_21_wave2_parity_docs_exist_and_are_non_empty(self):
        for index in range(1, 22):
            rel = f"docs/parity/w2-{index:02d}.md"
            path = resolve_repo_file(rel)
            self.assertTrue(path.is_file(), f"Missing Wave-2 parity doc: {rel}")
            content = path.read_text(encoding="utf-8").strip()
            self.assertGreater(len(content), 0, f"Empty Wave-2 parity doc: {rel}")
            self.assertIn(f"w2-{index:02d}", content, f"Doc {rel} should reference its scope id")

    def test_all_wave3_handoff_and_plan_progress_docs_exist(self):
        handoff_docs = [
            "docs/handoff/ios-I00-I11-20261019.md",
            *[f"docs/handoff/ios-I{index:02d}-20261019.md" for index in range(1, 11)],
            "docs/handoff/ios-BK-20261019.md",
        ]
        for rel in handoff_docs:
            path = resolve_repo_file(rel)
            self.assertTrue(path.is_file(), f"Missing Wave-3 handoff doc: {rel}")
            content = path.read_text(encoding="utf-8").strip()
            self.assertGreater(len(content), 0, f"Empty Wave-3 handoff doc: {rel}")

        for track in ("F", "G", "H"):
            rel = f"docs/plan-progress/{track}-20261019.md"
            path = resolve_repo_file(rel)
            self.assertTrue(path.is_file(), f"Missing Reform Plan progress doc: {rel}")
            content = path.read_text(encoding="utf-8").strip()
            self.assertGreater(len(content), 0, f"Empty Reform Plan progress doc: {rel}")

    def test_core_unified_inventory_and_preflight_fail_closed_defaults(self):
        inventory_text = read_repo_text("Core/WaveUnifiedParityInventory.swift")
        self.assertIn("public enum WaveUnifiedParityInventory", inventory_text)
        self.assertIn("public static let wave2Scopes: [Wave2ScopeEntry]", inventory_text)
        self.assertIn("public static let wave3HandoffScopes: [Wave3HandoffEntry]", inventory_text)
        self.assertIn("public static let reformWorkPackages: [ReformWorkPackageEntry]", inventory_text)
        self.assertIn("public static let unifiedDecisionPackages: [ReformWorkPackageEntry]", inventory_text)
        self.assertIn("public static func evaluateHighRiskSwitches()", inventory_text)
        self.assertIn("public static func verifyReleaseReadinessInvariants()", inventory_text)
        for index in range(1, 22):
            self.assertIn(f'"w2-{index:02d}"', inventory_text)
        for index in range(2, 21):
            self.assertIn(f'"W{index:02d}"', inventory_text)
        for index in range(1, 9):
            self.assertIn(f'"U{index:02d}"', inventory_text)

        preflight_text = read_repo_text("Core/ReleasePreflightAndUIReadinessContract.swift")
        self.assertIn("public enum ReleasePreflightAndUIReadinessContract", preflight_text)
        self.assertIn('public static let forbiddenLegacyMiniProgramHost = "47.103.124.64"', preflight_text)
        self.assertIn("public var isFailClosedDefault: Bool", preflight_text)

    def test_batch4_core_bridges_and_presentations_exist_with_expected_types(self):
        expected_core_symbols = {
            "Core/CommerceOrderLifecycleBridge.swift": [
                "public struct CommerceOrderLineHostSummary",
                "public struct CommerceOrderHostSnapshot",
                "public struct StaffRedemptionHostEvaluation",
                "public struct SponsoredRewardHostProjection",
                "public enum CommerceOrderLifecycleBridge",
            ],
            "Core/EnvironmentBranchHostPresentation.swift": [
                "public enum EnvironmentBranchHostMode",
                "public struct EnvironmentBranchHostPresentation",
                "public static func resolve(",
            ],
            "Core/RewardLedgerHostPresentation.swift": [
                "public struct RewardLedgerRowPresentation",
                "public struct RewardLedgerHostSnapshot",
                "public enum RewardLedgerHostPresentation",
                "public static let supportsCashInLedger = false",
                "public static let canBridgePointsToCash = false",
            ],
        }
        for rel, symbols in expected_core_symbols.items():
            text = read_repo_text(rel)
            for symbol in symbols:
                self.assertIn(symbol, text, f"{rel} missing expected symbol: {symbol}")

    def test_batch5_section_views_and_preflight_diagnostics_use_text_verbatim(self):
        expected_views = {
            "App/EnvironmentBranchAndRewardLedgerSectionView.swift": [
                "public struct EnvironmentBranchHostSectionView: View",
                "public struct RewardLedgerHostSectionView: View",
            ],
            "App/ReleasePreflightDiagnosticsView.swift": [
                "public struct ReleasePreflightDiagnosticsView: View",
                "47.103.124.64",
            ],
        }
        for rel, symbols in expected_views.items():
            text = read_repo_text(rel)
            self.assertIn("Text(", text, f"{rel} should render SwiftUI Text views")
            self.assertIn("verbatim:", text, f"{rel} must use Text(verbatim:)")
            self.assertNotIn("tableName:", text, f"{rel} must not add new localization table lookups")
            # Ensure no bare localized Text("...") calls exist without verbatim:
            bare_text_calls = re.findall(r'\bText\(\s*"', text)
            self.assertEqual(
                bare_text_calls,
                [],
                f"{rel} must use Text(verbatim:) instead of localized Text(\"...\")",
            )
            for symbol in symbols:
                self.assertIn(symbol, text, f"{rel} missing expected symbol: {symbol}")


if __name__ == "__main__":
    unittest.main()
