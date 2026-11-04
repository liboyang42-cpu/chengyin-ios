#!/usr/bin/env python3
"""Source-only regression: terminal receipt may resolve one failed stop only after durable removal.
This does NOT execute Swift, XCTest, the app, or a mirrored business-state model.
"""
import argparse
from pathlib import Path
import unittest
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a,_=p.parse_known_args()
s=(a.root/'Core/PersonalLocationShareCoordinator.swift').read_text()
class TerminalStopSourceRegression(unittest.TestCase):
 def test_cleanup_only_after_validated_terminal_and_successful_durable_remove(self):
  accept=s.split('private func accept(',1)[1].split('// Floating-point rounding',1)[0]
  terminal=accept.split('if receipt.state.isTerminal {',1)[1].split('        try journal.put(record, scope: scope);',1)[0]
  self.assertIn('unpersistedStopKeys.remove(requestKey)',terminal)
  self.assertLess(terminal.index('try journal.remove(requestKey: requestKey, scope: scope)'),terminal.index('unpersistedStopKeys.remove(requestKey)'))
  self.assertNotIn('unpersistedStopKeys.removeAll()',accept)
  self.assertNotIn('journalHealthy = true',terminal)
  self.assertNotIn('stopFence.remove',terminal)
 def test_original_receipt_identity_and_unknown_guards_preserved(self):
  accept=s.split('private func accept(',1)[1].split('// Floating-point rounding',1)[0]
  for marker in ['receipt.requestKey == requestKey','receipt.known == (receipt.state != .notFound)','receipt.requestHash != old','grant.matches(record.request, ownerId: scope.accountId)','receipt.grant == nil, receipt.requestHash == nil']:
   self.assertIn(marker,accept)
  self.assertNotIn('unpersistedStopKeys.remove(requestKey)',accept.split('if receipt.state.isTerminal {',1)[0])
 def test_readback_still_fenced_against_stale_account_or_generation(self):
  read=s.split('public func readback(',1)[1].split('public func stop(',1)[0]
  self.assertIn('guard canRead, let service, pending.contains',read)
  self.assertLess(read.index('guard live(captured), pending.contains'),read.index('try accept('))
 def test_explicit_recovery_gates_are_not_bypassed(self):
  restore=s.split('public func restoreOriginalRequests()',1)[1].split('public func readback(',1)[0]
  self.assertIn('journalHealthy = unpersistedStopKeys.isEmpty',restore)
  gate=s.split('public var canConfirm:',1)[1].split('public var visibleLocations:',1)[0]
  for marker in ['journalHealthy','unpersistedStopKeys.isEmpty','pending.isEmpty','acknowledgements == Set(PersonalLocationShareDisclosure.allCases)']:
   self.assertIn(marker,gate)
if __name__=='__main__':
 print('SOURCE ONLY: Swift/XCTest/App NOT_RUN.',flush=True)
 unittest.main(argv=[__file__],verbosity=2)
