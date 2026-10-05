from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class PostJoinNavigationTests(unittest.TestCase):
    def test_direct_join_provenance_is_outside_shared_apply(self):
        s=(ROOT/'Core/TeamCoordinator.swift').read_text()
        confirm=s.split('public func confirm(',1)[1].split('private func apply(',1)[0]
        self.assertIn('if case .join(let teamID, _) = value.action',confirm)
        self.assertLess(confirm.index('apply(result, record: persisted'),confirm.index('completedJoinID = teamID'))
        self.assertIn('pending == nil, completedTeamID == teamID',confirm)
        self.assertNotIn('completedJoinID',s.split('private func apply(',1)[1])
    def test_navigation_evidence_is_session_target_and_terminal_scoped(self):
        s=(ROOT/'Core/TeamCoordinator.swift').read_text().split('public var postJoinDetailID:',1)[1].split('public var authenticated:',1)[0]
        for part in ['currentSession() == capturedSession','capturedSession != nil','!busy','pending == nil','writeState == .acknowledged || writeState == .simulated','case .invitation = activeLookup','detail?.team.id == id']:
            self.assertIn(part,s)
    def test_readonly_coordinator_blocks_all_mutations_and_receipt_clearing(self):
        s=(ROOT/'Core/TeamCoordinator.swift').read_text()
        self.assertIn('readOnlyDetail = true; review = nil',s)
        self.assertIn('await loadDetail(.id(teamID), requireMembership: true)',s)
        for name in ['prepare(', 'confirm(', 'checkOutcome(']:
            body=s.split('public func '+name,1)[1].split('\n    }',1)[0]
            self.assertIn('guard !readOnlyDetail',body)
    def test_separate_readonly_route_does_not_weaken_action_lock(self):
        ui=(ROOT/'App/TeamHomeView.swift').read_text()
        self.assertIn('requiresMembership: true, readOnly: true)',ui)
        self.assertIn('loadPostJoinDetail(teamID: teamID)',ui)
        self.assertIn('if !readOnly, action.isAllowed(detail: detail)',ui)
        self.assertIn('remove: !readOnly && action.isAllowed(detail: detail)',ui)
        self.assertIn('if !readOnly, model.coordinator.pending != nil',ui)
        model=(ROOT/'App/TeamComponents.swift').read_text()
        self.assertIn('coordinator.writeState == .simulated || coordinator.writeState == .acknowledged || coordinator.writeState == .blocked',model)
    def test_authored_behavior_covers_failure_and_navigation(self):
        core=(ROOT/'Tests/CoreTests/TeamCoordinatorTests.swift').read_text()
        for name in ['testDirectJoinCompletionAllowsOnlyReadOnlyFreshDetail','testAcknowledgedJoinRequiresMatchingReceiptAndSuccessfulJournalClear','testOtherTerminalActionsNeverCreateJoinContinuation','testUnknownJoinAndLaterReceiptNeverCreateDirectContinuation','testJoinContinuationInvalidatesOnSessionOrTargetChange','testReadOnlyContinuationKeepsPendingJournalAndRejectsRevocation']:
            self.assertIn(name,core)
        self.assertIn('testPostJoinOpensReadOnlyDetailBackAndReopens',(ROOT/'Tests/AppUITests/TeamFlowTests.swift').read_text())
