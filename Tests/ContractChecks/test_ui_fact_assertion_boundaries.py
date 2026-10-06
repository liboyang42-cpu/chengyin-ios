from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
class UIFactAssertionBoundaryChecks(unittest.TestCase):
 def test_reward_fields_assert_complete_native_label_unique_id_and_exact_value(self):
  ui=(ROOT/'Tests/AppUITests/NonCashRewardFlowTests.swift').read_text()
  strings=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
  values=[('contextId','example-map'),('seasonId','example-season')]
  for key,value in values:
   label=strings['rewards.read.'+key]['localizations']['en']['stringUnit']['value']
   self.assertIn('"'+label+', '+value+'"',ui)
  for key in ['eligibility','claimProgress','allocation']:
   label=strings['rewards.read.'+key]['localizations']['en']['stringUnit']['value']
   self.assertIn(f'("rewards.read.{key}.value", "{label}")',ui)
  self.assertIn('field + ", Not provided by this read contract"',ui)
  self.assertEqual(ui.count('XCTAssertEqual(query.count, 1)'),2)
  self.assertIn('XCTAssertFalse(app.buttons["Claim reward"].exists)',ui)
 def test_saved_message_is_revealed_then_checked_exactly_not_replaced_by_generic_status(self):
  s=(ROOT/'Tests/AppUITests/TemplateAuthoringFlowTests.swift').read_text()
  body=s.split('func testLocalSaveHasExplicitDeviceOnlyResult()',1)[1].split('    func test',1)[0]
  self.assertIn('tap("templateAuthor.saveLocal", in: app)',body)
  self.assertIn('matching(identifier: "templateAuthor.status")',body)
  self.assertIn('revealFixtureElement(status, in: app, maximumSwipes: 50, requiresHittable: false)',body)
  self.assertIn('XCTAssertEqual(query.count, 1)',body)
  self.assertIn('XCTAssertEqual(status.label, "Saved securely on this device for this account.")',body)
  self.assertNotIn('firstMatch',body)
if __name__=='__main__': unittest.main()
