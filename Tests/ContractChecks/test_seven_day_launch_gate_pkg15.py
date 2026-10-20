"""Source contract checks for Package 15 — 7-Day Launch Critical Path Gate Real Input Binding.

Verifies:
1. `Core/SevenDayLaunchCriticalPathMilestoneContract.swift` replaces hardcoded `true` pass defaults
   with SHA-bound `LaunchDayEvidence` and `LaunchEvidenceResult`, distinguishes
   `codeVerifiedAwaitingExternalSignoff` / `isSevenDayLaunchCodeReady` from `verified` /
   `isSevenDayLaunchFullyVerified`, and fails closed when evidence is missing or unverified.
2. `Core/FinalThreeDocumentAndSevenDayGoalCompletionGate.swift` binds the 7-day launch pillar's
   `isDocumentScopeComplete` to `SevenDayLaunchCriticalPathMilestoneContract.evaluate().isSevenDayLaunchFullyVerified`
   instead of a hardcoded `true`.
3. `App/SevenDayLaunchCriticalPathSectionView.swift` and `App/MasterSevenDayLaunchCommandCenterView.swift`
   default to fail-closed `.unverified` snapshots, expose `.from(...)` constructors bound to the Core
   contract evaluation, and use `Text(verbatim:)` with zero bare localized `Text("...")` calls.
4. Corresponding Core and App unit tests cover missing evidence, invalid 40-hex commit SHAs,
   awaiting external sign-off vs full launch verification, and fail-closed default snapshots.
"""
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def read_repo_file(rel_path: str) -> str:
    path = REPO_ROOT / rel_path
    if not path.is_file():
        raise FileNotFoundError(f"Missing expected repository file: {rel_path}")
    return path.read_text(encoding="utf-8")


class SevenDayLaunchGatePkg15ContractTests(unittest.TestCase):
    def test_core_milestone_contract_requires_sha_bound_evidence_and_distinguishes_code_vs_full_verification(self):
        rel = "Core/SevenDayLaunchCriticalPathMilestoneContract.swift"
        text = read_repo_file(rel)

        required_symbols = [
            "public enum LaunchEvidenceResult: String, Sendable, Equatable",
            "public struct LaunchDayEvidence: Sendable, Equatable",
            "public static func isValidCommitSHA(_ value: String) -> Bool",
            "public enum LaunchDayVerificationStatus: String, Sendable, Equatable",
            'case notVerified = "NOT_VERIFIED"',
            'case failed = "FAILED"',
            'case codeVerifiedAwaitingExternalSignoff = "CODE_VERIFIED_AWAITING_EXTERNAL_SIGNOFF"',
            'case verified = "VERIFIED"',
            "public let evidence: LaunchDayEvidence?",
            "public let isSevenDayLaunchCodeReady: Bool",
            "public let isSevenDayLaunchFullyVerified: Bool",
            "public let evidenceBoundToSingleCommit: Bool",
            "public let boundCommitSHA: String?",
        ]
        for symbol in required_symbols:
            self.assertIn(symbol, text, f"{rel} missing required symbol: {symbol}")

        # Must not default codeAndTestGateReady: Bool = true
        self.assertNotIn("codeAndTestGateReady: Bool = true", text)
        self.assertIn("evidence?.hasPassingCodeAndTestEvidence ?? false", text)
        self.assertIn("!requiresExternalOpsSignoff || (evidence?.hasPassingExternalSignoff ?? false)", text)

    def test_final_three_document_gate_binds_seven_day_entry_to_real_evaluation(self):
        rel = "Core/FinalThreeDocumentAndSevenDayGoalCompletionGate.swift"
        text = read_repo_file(rel)

        self.assertIn(
            "isDocumentScopeComplete: SevenDayLaunchCriticalPathMilestoneContract.evaluate().isSevenDayLaunchFullyVerified",
            text,
            f"{rel} must bind seven_day_launch_plan completion to real contract evaluation",
        )

    def test_seven_day_section_view_and_command_center_fail_closed_and_use_text_verbatim(self):
        section_rel = "App/SevenDayLaunchCriticalPathSectionView.swift"
        section_text = read_repo_file(section_rel)

        self.assertIn('case notVerified = "NOT_VERIFIED"', section_text)
        self.assertIn('case verified = "VERIFIED"', section_text)
        self.assertIn("public let contractFullyVerified: Bool", section_text)
        self.assertIn("public static let unverified = SevenDayLaunchPlanSnapshot()", section_text)
        self.assertIn("public static let defaultReady = SevenDayLaunchPlanSnapshot.unverified", section_text)
        self.assertIn("public static func from(", section_text)
        self.assertIn("SevenDayLaunchCriticalPathMilestoneContract.evaluate(", section_text)
        self.assertEqual(
            re.findall(r'\bText\(\s*"', section_text),
            [],
            f"{section_rel} must use Text(verbatim:) with zero bare localized Text(\"...\") calls",
        )

        command_rel = "App/MasterSevenDayLaunchCommandCenterView.swift"
        command_text = read_repo_file(command_rel)

        self.assertIn("isReady: Bool = false", command_text)
        self.assertIn('statusBadge: String = "NOT_VERIFIED"', command_text)
        self.assertIn("zeroGapCertificateIssued: Bool = false", command_text)
        self.assertIn("nativeSupersetPolicyEnforced: Bool = false", command_text)
        self.assertIn("public static let unverified = MasterSevenDayLaunchCommandSnapshot()", command_text)
        self.assertIn("public static let defaultReady = MasterSevenDayLaunchCommandSnapshot.unverified", command_text)
        self.assertIn("sevenDayEvaluation: SevenDayLaunchMilestoneEvaluation", command_text)
        self.assertEqual(
            re.findall(r'\bText\(\s*"', command_text),
            [],
            f"{command_rel} must use Text(verbatim:) with zero bare localized Text(\"...\") calls",
        )

    def test_pkg15_unit_tests_cover_fail_closed_and_sha_evidence_bindings(self):
        expected_test_markers = {
            "Tests/CoreTests/SevenDayLaunchCriticalPathMilestoneContractTests.swift": [
                "testMissingEvidenceDefaultsToNotVerified",
                "testNotRunResultIsNotVerified",
                "testNonFortyHexSHAIsRejected",
                "testExternalSignoffMissingOrFailedBlocksFullVerificationButNotCodeReadiness",
                "testExternalSignoffBoundToDifferentOrMissingSHAIsRejected",
                "testEvidenceFromDifferentCommitsOrUnexpectedSHAIsRejected",
            ],
            "Tests/CoreTests/FinalThreeDocumentAndSevenDayGoalCompletionGateTests.swift": [
                "XCTAssertFalse(entries[3].isCompliant)",
                "XCTAssertFalse(result.isGoal100PercentComplete)",
            ],
            "Tests/AppUnitTests/SevenDayLaunchCriticalPathSectionViewTests.swift": [
                "testSnapshotFromCoreContractIsFailClosedWithoutEvidence",
                "testSnapshotFromCoreContractRequiresShaBoundEvidenceAndSignoff",
            ],
            "Tests/AppUnitTests/MasterSevenDayLaunchCommandCenterViewTests.swift": [
                "testSevenDayPillarReadsFailClosedCoreResult",
                "XCTAssertFalse(snapshot.isCommandCenterLaunchReady)",
            ],
        }
        for rel, markers in expected_test_markers.items():
            text = read_repo_file(rel)
            for marker in markers:
                self.assertIn(marker, text, f"{rel} missing expected test marker: {marker}")


if __name__ == "__main__":
    unittest.main()
