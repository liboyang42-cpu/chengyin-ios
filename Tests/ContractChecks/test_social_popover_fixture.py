"""Native popover runtime remains Apple CI; source guard preserves strict outcomes."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class SocialPopoverFixtureTests(unittest.TestCase):
    def test_cancel_and_discard_use_the_observed_native_presentation(self):
        text=(ROOT/'Tests/AppUITests/SocialAccountFlowTests.swift').read_text()
        for value in ['dialogTitle: "Discard this draft?"', 'dialogTitle: "要放弃这份草稿吗？"',
                      'dismissFixtureConfirmationPopover(in: app)', 'tapFixtureSheetAction("Discard draft", in: discard, app: app)',
                      '!dialog.exists && editor.exists && editor.value as? String == expected',
                      'XCTAssertEqual(editor.value as? String, "")']:
            self.assertIn(value,text)
        self.assertEqual(text.count('func testDraftSurvivesNestedReviewAndCancelThenDiscardReopensEmpty'),1)
        self.assertEqual(text.count('func testChineseLargeTextDraftCancelKeepsTextAndKeyboardDismisses'),1)
if __name__=='__main__': unittest.main()
