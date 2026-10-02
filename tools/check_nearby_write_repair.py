#!/usr/bin/env python3
"""Supplementary source assertions only; no Swift/runtime/network execution."""
from pathlib import Path
import json
import unittest
R=Path(__file__).resolve().parents[1]
A=(R/'Core/NearbyTeamHTTPWriteAdapter.swift').read_text()
S=(R/'Core/NearbyTeamService.swift').read_text()
C=(R/'Core/NearbyTeamCoordinator.swift').read_text()
T=(R/'Tests/CoreTests/NearbyTeamHTTPWriteTests.swift').read_text()
class NearbyWriteRepairChecks(unittest.TestCase):
 def test_default_off(self):
  self.assertIn('approval: OperationEndpointApproval? = nil',A); self.assertIn('writeAdapter: (any NearbyTeamWriting)? = nil',S)
 def test_three_exact_paths_only(self):
  self.assertIn('["/api/team/apply", "/api/team/withdraw", "/api/team/handle"]',A)
  for path in ['/api/team/join-mode','/receipt','/reconcile','/api/team/join']: self.assertNotIn(path,A)
 def test_scoped_grant(self):
  for value in ['configuration: configuration, namespace: session.namespace, accountID: session.accountID','currentSession() == session','session.valid']: self.assertIn(value,A)
 def test_review_evidence(self):
  for value in ['team == review.team','applicant == review.applicant','application == review.application','team?.viewerStatus == .leader','team?.viewerHasTicket == true','expiry > now']: self.assertIn(value,A)
 def test_persist_before_dispatch(self):
  self.assertLess(A.index('record.phase = .dispatched; try journal.write(record)'),A.index('await transport.send(request)'))
  self.assertEqual(A.count('if try journal.read(owner: owner, target: target) != nil'),2)
 def test_inflight_and_restart(self):
  self.assertIn('!inFlight.contains(operationKey)',A);self.assertIn('phase: Phase = .prepared',A)
  self.assertIn('case prepared, dispatched, acknowledged',A)
 def test_outcomes_distinct(self):
  self.assertIn('synthetic ? .simulated(expiry: expiry) : .acknowledged(expiry: expiry)',S)
  self.assertIn('case .simulated(let expiry), .acknowledged(let expiry)',C)
  self.assertIn('nearby.acknowledged',C)
 def test_no_hidden_receipt_or_network(self):
  self.assertNotIn('URLSessionTransport()',A);self.assertNotIn('URLSession.shared',A)
  self.assertNotIn('idempotency',A.lower());self.assertNotIn('addingTimeInterval(86400)',A+S)
 def test_coordinator_passes_review(self):
  self.assertIn('service.submit(snapshot.action, session: capturedSession, review: snapshot)',C)
  self.assertIn('switch outcome { case .unknown: break; default: locks.remove',C)
 def test_authored_tests(self):
  self.assertEqual(T.count('    func test'),22)
  for value in ['testConcurrentAdapterInstancesCannotReplaySameReview','testEpochChangeAfterSendCannotClearUnknownLock','testDefaultsJournalSurvivesRecreationWithoutSecrets','testCoordinatorReportsAcknowledgmentAndServerExpiry']: self.assertIn(value,T)
 def test_localizations(self):
  strings=json.loads((R/'Resources/NearbyTeamWriteLocalizations.fragment.json').read_text())['strings'];self.assertEqual(len(strings),4)
  for value in strings.values():
   for lang in ['en','zh-Hans']: self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
 def test_default_host_grants_nil(self):
  text=(R/'tools/apply_nearby_write_host_patch.py').read_text()
  self.assertIn('writeApproval: OperationEndpointApproval? = nil',text);self.assertIn('writeEvidence: ((NearbyTeamReview) async throws -> NearbyTeamWriteEvidence)? = nil',text)
if __name__=='__main__': unittest.main(verbosity=2)
