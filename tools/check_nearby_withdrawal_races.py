#!/usr/bin/env python3
"""Supplementary source regression checks. Does not compile or execute Swift."""
from pathlib import Path
import os
import unittest

ROOT = Path(os.environ.get("NEARBY_WITHDRAWAL_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
C = (ROOT / "Core/NearbyTeamCoordinator.swift").read_text()
T_PATH = ROOT / "Tests/CoreTests/NearbyTeamWithdrawalRaceTests.swift"
T = T_PATH.read_text() if T_PATH.exists() else ""
S = (ROOT / "Core/NearbyTeamService.swift").read_text()
A = (ROOT / "Core/NearbyTeamHTTPWriteAdapter.swift").read_text()


def section(start, end):
    return C.split(start, 1)[1].split(end, 1)[0] if start in C else ""


class NearbyWithdrawalSourceChecks(unittest.TestCase):
    def test_nearby_read_projects_barrier_after_generation_validation(self):
        body = section("public func loadNearby", "public func loadMine")
        self.assertIn("teams = rows.map(applyingWithdrawalBarrier)", body)
        self.assertLess(body.index("guard valid(session, generation)"), body.index("teams = rows.map"))

    def test_mine_read_filters_only_same_team_pending(self):
        body = section("public func loadMine", "public func loadApplicants")
        self.assertIn("!(withdrawnApplications.contains($0.id) && $0.status == .pending)", body)
        self.assertIn("[.pending, .rejected].contains($0.status)", body)
        self.assertIn("seen.insert($0.id).inserted", body)

    def test_ambiguous_pending_is_unverified_not_invented_none(self):
        body = section("private func applyingWithdrawalBarrier", "private func recordApplicationReceipt")
        self.assertIn("guard withdrawnApplications.contains(row.id), row.viewerStatus == .pending else { return row }", body)
        self.assertIn("row.patch(status: .unknown, replaceExpiry: true)", body)
        self.assertNotIn("status: NearbyViewerStatus.none", body)

    def test_both_read_paths_request_state_review_for_ambiguous_pending(self):
        for start, end, field in [("public func loadNearby", "public func loadMine", "viewerStatus"), ("public func loadMine", "public func loadApplicants", "status")]:
            body = section(start, end)
            self.assertIn(f'withdrawnApplications.contains($0.id) && $0.{field} == .pending', body)
            self.assertIn('messageKey = "nearby.stale"', body)

    def test_binding_fence_resets_on_rebind_but_not_navigation(self):
        body = section("public func bind", "public func resume")
        self.assertIn("bindingGeneration &+= 1", body)
        self.assertIn("withdrawnApplications = []", body)
        leave = section("public func leave", "public func resume")
        self.assertNotIn("bindingGeneration", leave)
        self.assertNotIn("withdrawnApplications", leave)

    def test_only_positive_receipts_record_in_same_binding(self):
        body = section("if session == capturedSession, bindingGeneration == capturedBindingGeneration", "guard valid(capturedSession, capturedGeneration)")
        self.assertIn("case .simulated, .acknowledged:", body)
        self.assertIn("recordApplicationReceipt(snapshot.action)", body)
        self.assertIn("default: break", body)
        self.assertEqual(C.count("recordApplicationReceipt(snapshot.action)"), 1)

    def test_late_receipt_cannot_clear_newer_busy_state(self):
        body = section("let outcome = await service.submit", "busy = false; revision &+= 1")
        self.assertIn("recordApplicationReceipt(snapshot.action)", body)
        self.assertLess(body.index("recordApplicationReceipt"), body.index("guard valid(capturedSession, capturedGeneration)"))
        helper = section("private func recordApplicationReceipt", "private func failure")
        self.assertNotIn("busy =", helper)

    def test_late_apply_clears_only_barrier_without_overwriting_authority(self):
        helper = section("private func recordApplicationReceipt", "private func failure")
        apply = helper.split("case .apply(let id):", 1)[1].split("case .handle", 1)[0] if "case .apply(let id):" in helper else ""
        self.assertIn("withdrawnApplications.remove(id)", apply)
        self.assertNotIn(".patch(", apply)
        self.assertNotIn("teams[", apply)
        confirm = section("public func confirm", "private func applyingWithdrawalBarrier")
        self.assertLess(confirm.index("guard valid(capturedSession, capturedGeneration)"), confirm.index("teams[index].patch(status: .pending"))

    def test_withdrawal_receipt_does_not_hide_nonpending_authority(self):
        helper = section("private func recordApplicationReceipt", "private func failure")
        self.assertIn("withdrawnApplications.insert(id)", helper)
        self.assertIn("teams[index].viewerStatus == .pending", helper)
        self.assertIn("myApplications.removeAll { $0.id == id && $0.status == .pending }", helper)

    def test_unknown_outcome_and_durable_replay_guards_are_retained(self):
        self.assertIn("switch outcome { case .unknown: break; default: locks.remove", C)
        self.assertIn("!settledActions.contains(.init(action))", C)
        self.assertNotIn("settledActions.remove", C)
        self.assertEqual(A.count("if try journal.read(owner: owner, target: target) != nil"), 2)
        self.assertIn("case prepared, dispatched, acknowledged", A)

    def test_rejected_apply_pending_projection_respects_existing_barrier(self):
        body = section("case .rejected(let code, let message):", "case .simulated(let expiry)")
        self.assertIn("teams[index] = applyingWithdrawalBarrier(teams[index])", body)

    def test_no_new_persistence_transport_or_authority_contract(self):
        helper = section("private func applyingWithdrawalBarrier", "private func failure")
        for forbidden in ["UserDefaults", "URLSession", "journal.", "joinedCount", "receiptID", "applicationID"]:
            self.assertNotIn(forbidden, helper)
        self.assertIn("writeAdapter: (any NearbyTeamWriting)? = nil", S)
        self.assertIn("approval: OperationEndpointApproval? = nil", A)

    def test_authored_async_matrix_uses_deterministic_fake_suspensions(self):
        self.assertEqual(T.count("    func test"), 23)
        for term in ["withCheckedContinuation", "write.complete", "read.complete", "Task.yield()", "0..<1_000"]:
            self.assertIn(term, T)
        for forbidden in ["Task.sleep", "URLSession", "https://", "usleep("]:
            self.assertNotIn(forbidden, T)

    def test_authored_matrix_covers_required_edges(self):
        for name in [
            "testAcknowledgedWithdrawSuppressesRepeatedPendingReadsAndActiveCount",
            "testUnsuccessfulWithdrawalNeverCreatesBarrier",
            "testDifferentTeamAndNonPendingAuthorityRemainVisible",
            "testExplicitNewApplyAcknowledgmentClearsOnlyMatchingBarrier",
            "testNewApplyDoesNotClearAnotherTeamsBarrier",
            "testConcurrentDuplicateConfirmDispatchesOneWithdrawal",
            "testLateWithdrawalAckBeforeNewReadDoesNotClearItsBusyOrRestorePending",
            "testLateApplyAckCannotDowngradeNewerJoinedOrLeaderRead",
            "testLateAckCannotImportBarrierAfterLogoutAndSameSessionRebind",
            "testCoordinatorRecreationDoesNotPretendToHaveServerWithdrawalAuthority",
            "testKnownReplayBoundaryIsNotSilentlyRemovedForApplyWithdrawApplyCycle",
        ]:
            self.assertIn("func " + name, T)


if __name__ == "__main__":
    print("SOURCE CHECKS ONLY: Swift compile/runtime and Apple tests are NOT_RUN.", flush=True)
    unittest.main(verbosity=2)
