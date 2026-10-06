from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PlayExperienceReturnMountChecks(unittest.TestCase):
 def test_same_owner_return_does_not_drop_free_host_and_current_mode_still_fences(self):
  s=(ROOT/'App/PlayExperienceView.swift').read_text()
  self.assertIn('.task(id: PlayExperiencePresentationKey(model: model))',s)
  self.assertIn('if presentationMount.enter(model) { selectedNode = nil; presentedMode = nil }',s)
  self.assertIn('model !== next || session != next.identity',s)
  self.assertIn('private var model: PlayExperienceCoordinator?',s)
  self.assertIn('(model.snapshot == nil && presentedMode == .freeExploration)',s)
  self.assertIn('if let mode, mode != .cityOrientation { selectedNode = nil; confirmEnd = false }',s)
 def test_disabled_identifier_stays_on_leaf_instead_of_parent_override(self):
  s=(ROOT/'App/PlayExperienceView.swift').read_text()
  self.assertIn('Text("playx.disabled").accessibilityIdentifier("playx.disabled")',s)
  self.assertIn('ProgressView("playx.loading").accessibilityIdentifier("playMode.loading")',s)
  self.assertNotIn('.padding().accessibilityIdentifier("playMode.loading")',s)
 def test_original_real_ui_journeys_remain(self):
  s=(ROOT/'Tests/AppUITests/PlayExperienceFlowTests.swift').read_text()
  self.assertIn('XCTAssertTrue(store.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["playx.run.resume"].exists)',s)
  self.assertIn('XCTAssertTrue(app.staticTexts["playx.disabled"].waitForExistence(timeout: 5))',s)
  self.assertIn('XCTAssertFalse(app.buttons["playx.node.701"].exists); XCTAssertEqual(app.alerts.count, 0)',s)
if __name__=='__main__':unittest.main()
