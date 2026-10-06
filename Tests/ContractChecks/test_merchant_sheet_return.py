from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class MerchantSheetReturnChecks(unittest.TestCase):
 def test_complete_unknown_outcome_ledger_survives_transition_wait(self):
  source=(ROOT/'Tests/AppUITests/MerchantContentFlowTests.swift').read_text()
  body=source.split('func testUnknownMutationLocksReloadAndDuplicateSubmission()',1)[1].split('    func ',1)[0]
  self.assertIn('app.navigationBars.count == 1 && !app.buttons["merchant.content.confirm"].exists',body)
  self.assertLess(body.index('XCTWaiter.wait(for: [returned], timeout: 5)'),body.index('revealFixtureElement(issue'))
  for text in ['tap("merchant.content.reload", in: app)','tap("merchant.content.withdraw", in: app)','XCTAssertFalse(app.buttons["merchant.content.confirm"].exists)','XCTAssertEqual(issue.label, unknownMessage)']:
   self.assertIn(text,body)
if __name__=='__main__':unittest.main()
