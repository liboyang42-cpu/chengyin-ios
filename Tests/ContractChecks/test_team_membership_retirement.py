"""Read-only wiring checks; these do not execute Swift or prove server cancellation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TeamMembershipRetirementChecks(unittest.TestCase):
    def source(self):
        return (ROOT / "Core/TeamCoordinator.swift").read_text()

    def method(self, start, end):
        return self.source().split(start, 1)[1].split(end, 1)[0]

    def test_real_confirm_records_departure_after_persistence_before_dispatch(self):
        confirm = self.method("public func confirm(", "private func apply(")
        self.assertLess(confirm.index("try journal.write(record)"), confirm.index("rememberRetirement(value.action, record: record)"))
        self.assertLess(confirm.index("rememberRetirement(value.action, record: record)"), confirm.index("await service.submit"))
        remember = self.method("private func rememberRetirement(", "private func retireMembership(")
        self.assertIn("case .leave(let teamID), .disband(let teamID):", remember)
        self.assertIn("case .create, .join, .remove: break", remember)

    def test_both_success_kinds_clear_exact_journal_before_retirement(self):
        apply = self.method("private func apply(", "public func checkOutcome(")
        for label, end in [("case .simulated", "case .acknowledged"), ("case .acknowledged", "case .rejected, .notSent")]:
            branch = apply.split(label, 1)[1].split(end, 1)[0]
            for requirement in ["id == record.operationID", "expectedTeamID == teamID", "try journal.clear(record)"]:
                self.assertIn(requirement, branch)
            self.assertLess(branch.index("try journal.clear(record)"), branch.index("retireMembership(record: record, teamID: teamID)"))
            self.assertIn('catch { writeState = .unknown; messageKey = "team.unknown" }', branch)

    def test_unknown_or_unsuccessful_outcome_cannot_retire(self):
        apply = self.method("private func apply(", "public func checkOutcome(")
        unknown = apply.split("case .unknown:", 1)[1].split("case .simulated", 1)[0]
        for forbidden in ["journal.clear", "retireMembership", "detail = nil"]:
            self.assertNotIn(forbidden, unknown)
        rejected = apply.split("case .rejected, .notSent:", 1)[1]
        self.assertIn("retirementOperations[record.operationID] = nil", rejected)
        self.assertNotIn("retireMembership(", rejected)

    def test_retirement_removes_cached_authority_and_invalidates_old_work(self):
        body = self.method("private func retireMembership(", "public func confirm(")
        for requirement in ["operation.ownerKey == record.ownerKey", "operation.teamID == teamID",
                            "retiredMembershipsByOwner[record.ownerKey, default: []].insert(teamID)",
                            "generation &+= 1", "teams.removeAll { $0.id == teamID }",
                            "if detail?.team.id == teamID { detail = nil }", "review = nil",
                            "completedJoinID = nil", "retiredMembershipTeamID = teamID"]:
            self.assertIn(requirement, body)
        for forbidden in ['joined = false', 'status = .disbanded', 'URLRequest', 'UserDefaults', 'expiresAt']:
            self.assertNotIn(forbidden, body)

    def test_detail_and_list_calls_use_retirement_before_exposing_rows(self):
        detail = self.method("public func loadDetail(", "public func loadPostJoinDetail(")
        self.assertLess(detail.index("membershipRetired(teamID: id, session: session)"), detail.index("await service.detail"))
        self.assertLess(detail.index("membershipRetired(teamID: result.team.id, session: session)"), detail.index("detail = result"))
        listing = self.method("public func loadTeams(", "public func loadDetail(")
        self.assertIn("teams = rows.filter { !membershipRetired(teamID: $0.id, session: session) }", listing)
        self.assertIn("guard active(session, stamp) else { return }", detail)
        self.assertIn("guard active(session, stamp) else { return }", listing)

    def test_old_action_and_review_identity_are_both_blocked(self):
        prepare = self.method("public func prepare(", "public func cancelReview(")
        self.assertIn("membershipRetired(teamID: teamID, session: session)", prepare)
        confirm = self.method("public func confirm(", "private func apply(")
        self.assertIn("review == value", confirm)
        self.assertIn("membershipRetired(teamID: teamID, session: value.session)", confirm)
        self.assertLess(confirm.index("membershipRetired("), confirm.index("await service.detail"))

    def test_session_reset_clears_presentation_not_same_owner_retirement(self):
        reset = self.method("public func synchronizeSession(", "private func active(")
        self.assertIn("retiredMembershipTeamID = nil", reset)
        self.assertNotIn("retiredMembershipsByOwner =", reset)
        self.assertNotIn("retirementOperations =", reset)
        guard = self.method("private func membershipRetired(", "private func rememberRetirement(")
        self.assertIn("retiredMembershipsByOwner[session.ownerKey]", guard)

    def test_existing_app_route_shows_retired_state_and_hides_refresh(self):
        view = (ROOT / "App/TeamHomeView.swift").read_text()
        self.assertIn("if model.coordinator.retiredMembershipTeamID != nil", view)
        self.assertIn('Label("team.changed", systemImage:', view)
        self.assertIn('accessibilityIdentifier("teamMembershipRetired")', view)
        self.assertIn("lookup.isValid && model.coordinator.authenticated && model.coordinator.retiredMembershipTeamID == nil", view)
        self.assertIn("if let detail = model.coordinator.detail", view)

    def test_authored_swift_cases_cover_terminal_ambiguous_and_stale_paths(self):
        tests = (ROOT / "Tests/CoreTests/TeamCoordinatorTests.swift").read_text()
        for name in ["testLeaveAndDisbandRetireOnlyAfterMatchingTerminalResult",
                     "testRetiredMembershipRejectsOldProjectionAndEveryTeamAction",
                     "testFailedRefreshCannotReviveRetiredRosterOrReview",
                     "testUnknownWrongAndUnclearedResultsDoNotRetireMembership",
                     "testRejectedAndNotSentLeaveKeepMembershipAvailableForNewReview",
                     "testCorrelatedDepartureReceiptRetiresSameWorkflowWithoutResubmitting",
                     "testLateDetailAfterAcknowledgedDepartureCannotRestoreMembership",
                     "testInterruptedDepartureNeverRetiresUntilCorrelatedReceipt",
                     "testRetirementSurvivesSameWorkflowReauthenticationWithoutCrossAccountLeak",
                     "testRetirementDoesNotBlockAnotherTeamOrBecomeGlobalMembershipAuthority",
                     "testMemberRemovalAndJoinDoNotRetireOwnersMembership"]:
            self.assertIn("func " + name + "(", tests)


if __name__ == "__main__":
    unittest.main()
