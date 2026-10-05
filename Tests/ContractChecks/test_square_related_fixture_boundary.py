from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class SquareRelatedFixtureBoundary(unittest.TestCase):
    def test_single_row_query_requires_exact_unique_entire_native_frame(self):
        s=(ROOT/'Tests/AppUITests/SquareFlowTests.swift').read_text()
        a=s.split('private func tapRelatedFixturePost',1)[1].split('private func tapRelatedFixtureAccountSwitch',1)[0]
        for text in ['matching(identifier: "fixture.relatedPost")','query.count == 1','button.isEnabled && button.isHittable','frame.minY >= bar.frame.maxY',
                     'self.app.frame.contains(frame)','frame.maxY <= self.app.frame.maxY - 40','keyboards.allElementsBoundByIndex','query.element(boundBy: 0).tap()']:
            self.assertIn(text,a)
        self.assertNotIn('revealFixtureElement',a)
    def test_account_control_is_scoped_to_real_navigation_bar(self):
        s=(ROOT/'Tests/AppUITests/SquareFlowTests.swift').read_text()
        self.assertIn('app.navigationBars.buttons.matching(identifier: "fixture.relatedTopic.switchAccount")',s)
        self.assertIn('self.app.navigationBars.element(boundBy: 0).frame.contains(frame)',s)
        self.assertIn('tapRelatedFixtureAccountSwitch()',s)
    def test_exact_topics_back_retry_missing_link_checks_remain(self):
        s=(ROOT/'Tests/AppUITests/SquareFlowTests.swift').read_text()
        for text in ['"Synthetic linked topic 31"','"Synthetic linked topic 32"','"此路线暂不可查看"',
                     'XCTAssertFalse(app.buttons["square.openRelatedTopic"].exists)',
                     'reveal(retry)','app.navigationBars["Post details"].buttons.firstMatch.tap()']:
            self.assertIn(text,s)
