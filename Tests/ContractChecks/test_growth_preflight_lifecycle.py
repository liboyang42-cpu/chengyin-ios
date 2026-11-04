"""Source-only race guards. Does not execute SwiftUI, Swift, or a real lifecycle."""
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[2]
class GrowthPreflightLifecycle(unittest.TestCase):
 def test_foreground_work_is_retained_and_checks_current_presentation(self):
  s=(R/'App/GrowthCenterComponents.swift').read_text()
  self.assertIn('@State private var foregroundRefresh: Task<Void, Never>?',s)
  self.assertIn('foregroundRefresh = Task { @MainActor in',s)
  self.assertIn('guard !Task.isCancelled, visible, scenePhase == .active else { return }',s)
  self.assertNotIn('Task { await refresh() }',s)
 def test_disappear_cancels_both_foreground_and_reader(self):
  s=(R/'App/GrowthCenterComponents.swift').read_text().split('.onDisappear {',1)[1].split('.onChange',1)[0]
  for t in ['visible = false','foregroundRefresh?.cancel(); foregroundRefresh = nil','cancel()']:self.assertIn(t,s)
 def test_background_cancels_both_foreground_and_reader(self):
  s=(R/'App/GrowthCenterComponents.swift').read_text().split('if phase == .background {',1)[1].split('else if',1)[0]
  for t in ['needsRefresh = true; cancel()','foregroundRefresh?.cancel(); foregroundRefresh = nil']:self.assertIn(t,s)
 def test_replaced_badge_postprocessing_is_cancelled_and_presentation_bound(self):
  s=(R/'App/GrowthCenterView.swift').read_text().split('private func readOverview() async {',1)[1].split('\n}\n',1)[0]
  self.assertIn('let captured = key, presentation = badgePresentationID',s)
  after=s.split('await model.load',1)[1]
  self.assertIn('guard !Task.isCancelled, captured == key, presentation == badgePresentationID',after)
  self.assertLess(after.index('presentation == badgePresentationID'),after.index('unlockTracker.observe'))
 def test_native_overlap_regression_is_present(self):
  s=(R/'Tests/CoreTests/GrowthNormalReadTransportTests.swift').read_text()
  self.assertIn('func testLateReplacedFailureCannotEraseNewReadback()',s)
  self.assertIn('continuation.resume(throwing: APIError.notConfigured)',s)
  self.assertIn('XCTAssertEqual(model.visibleValue(key: key), 42)',s)
if __name__=='__main__':unittest.main()
