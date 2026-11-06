"""SwiftUI source invariants only; not a runtime lifecycle test."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
class GrowthBackgroundScopeChecks(unittest.TestCase):
 def setUp(self):self.s=(R/'App/GrowthCenterComponents.swift').read_text().split('struct GrowthCenterReadLifecycle:',1)[1].split('/// Keeps the original labels',1)[0]
 def test_scope_restart_defers_until_active(self):
  self.assertIn('.task(id: key) { await refreshWhenActive() }',self.s)
  body=self.s.split('private func refreshWhenActive() async {',1)[1]
  self.assertIn('guard !Task.isCancelled else { return }',body)
  self.assertIn('guard scenePhase == .active else { needsRefresh = true; return }',body)
  self.assertLess(body.index('guard scenePhase'),body.index('await refresh()'))
 def test_pull_requires_visible_and_same_active_gate(self):
  body=self.s.split('.refreshable {',1)[1].split('.onAppear',1)[0]
  self.assertIn('guard visible else { return }',body)
  self.assertIn('await refreshWhenActive()',body)
 def test_appearance_does_not_drop_deferred_work(self):
  self.assertIn('.onAppear { visible = true }',self.s)
  self.assertNotIn('.onAppear { visible = true; needsRefresh = false }',self.s)
 def test_foreground_consumes_pending_only_after_live_guard(self):
  body=self.s.split('else if phase == .active, visible, needsRefresh {',1)[1].split('private func refreshWhenActive',1)[0]
  self.assertLess(body.index('guard !Task.isCancelled, visible, scenePhase == .active'),body.index('needsRefresh = false'))
  self.assertLess(body.index('needsRefresh = false'),body.index('await refresh()'))
 def test_background_and_disappearance_still_cancel_both_tasks(self):
  self.assertEqual(self.s.count('foregroundRefresh?.cancel(); foregroundRefresh = nil'),2)
  self.assertIn('needsRefresh = true; cancel()',self.s)
  self.assertIn('visible = false',self.s)
if __name__=='__main__':unittest.main()
