import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class Batch24ToBatch27ThreeDocsFullClosureTests(unittest.TestCase):
    def test_all_36_opt_packages_and_11_ext_and_10_decisions_exist(self):
        opt_files = [
            "Core/UnifiedOPT001To003FoundationAnd509DefectTriageContract.swift",
            "Core/UnifiedOPT010To014CommerceCartRefundAndLedgerContract.swift",
            "Core/UnifiedOPT020To023PrivacyModerationTrustAndChainContract.swift",
            "Core/UnifiedOPT030To033AuthorDraftEndingVersionAndCreatorContract.swift",
            "Core/UnifiedOPT040To043PlayRecoveryGPSAudioAndPassportContract.swift",
            "Core/UnifiedOPT050To053ClubMembershipScheduleLeadAndBroadcastContract.swift",
            "Core/UnifiedOPT060To062MerchantClaimAggregateAndCRMContract.swift",
            "Core/UnifiedOPT070To072ReceiptCapabilitiesMigrationAndTraceContract.swift",
            "Core/UnifiedOPT080To082AIGatewaySafetyUsageAndDraftAssistContract.swift",
            "Core/UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract.swift",
        ]
        combined = ""
        for rel in opt_files:
            path = ROOT / rel
            self.assertTrue(path.exists(), f"Missing {rel}")
            combined += path.read_text(encoding="utf-8")

        expected_opts = [
            "OPT-001", "OPT-002", "OPT-003",
            "OPT-010", "OPT-011", "OPT-012", "OPT-013", "OPT-014",
            "OPT-020", "OPT-021", "OPT-022", "OPT-023",
            "OPT-030", "OPT-031", "OPT-032", "OPT-033",
            "OPT-040", "OPT-041", "OPT-042", "OPT-043",
            "OPT-050", "OPT-051", "OPT-052", "OPT-053",
            "OPT-060", "OPT-061", "OPT-062",
            "OPT-070", "OPT-071", "OPT-072",
            "OPT-080", "OPT-081", "OPT-082",
            "OPT-090", "OPT-091", "OPT-092",
        ]
        self.assertEqual(len(expected_opts), 36)
        for opt_id in expected_opts:
            self.assertIn(f'"{opt_id}"', combined, f"Missing {opt_id}")

        for i in range(1, 12):
            ext_id = f"EXT-{i:02d}"
            self.assertIn(f'"{ext_id}"', combined, f"Missing {ext_id}")

        for i in range(1, 11):
            d_id = f"D-{i:02d}"
            self.assertIn(f'"{d_id}"', combined, f"Missing {d_id}")

    def test_legacy_52_tickets_and_mp01_to_mp21_slices_exist(self):
        path = ROOT / "Core/Legacy52TicketsAndMP01To21SliceParityContract.swift"
        self.assertTrue(path.exists())
        text = path.read_text(encoding="utf-8")
        for i in range(1, 22):
            self.assertIn(f'"MP-{i:02d}"', text)
        self.assertEqual(text.count("LegacyBusinessTicketMapping(ticketID:"), 52)

    def test_wave2_all_partial_and_missing_closures_and_plan_i_merged(self):
        w2_path = ROOT / "Core/Wave2AllPartialAndMissingRowsClosureCoordinator.swift"
        self.assertTrue(w2_path.exists())
        w2_text = w2_path.read_text(encoding="utf-8")
        for i in range(1, 22):
            self.assertIn(f'"w2-{i:02d}"', w2_text)
        self.assertTrue((ROOT / "Core/OpsDegradedState.swift").exists())
        self.assertTrue((ROOT / "docs/plan-progress/I-20261019.md").exists())


if __name__ == "__main__":
    unittest.main()
