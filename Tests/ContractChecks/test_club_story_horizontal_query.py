from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClubStoryHorizontalQuery(unittest.TestCase):
    def test_exact_chapter_controls_use_their_single_real_scroller(self):
        s = (ROOT / "Tests/AppUITests/ClubStoryFlowTests.swift").read_text()
        block = s.split("private func tapChapter(", 1)[1].split("private func gameplay", 1)[0]
        for required in ["app.scrollViews.allElementsBoundByIndex.filter", "scrollers.count == 1", "towardTop: true, requiresHittable: false", "0...8", "matches.count == 1", "visible.contains(frame)", "button.isEnabled", "button.isHittable", "visible.minX - frame.minX + 8", "visible.maxX - frame.maxX - 8", "start.press(forDuration: 0.05, thenDragTo: end)", "button.tap(); return", "XCTFail("]:
            self.assertIn(required, block)
        self.assertNotIn("button.coordinate(", block)
        self.assertNotIn("app.coordinate(", block)
        self.assertIn("scroller.coordinate(withNormalizedOffset: .zero)", block)
        self.assertNotIn(".firstMatch", block)
        self.assertIn('["club.story.chapter.0", "club.story.chapter.1", "club.story.chapter.2"].contains(id)', s)
    def test_original_chapter_switch_oracles_still_require_correct_independent_content(self):
        s = (ROOT / "Tests/AppUITests/ClubStoryFlowTests.swift").read_text()
        for expected in ['XCTAssertFalse(app.staticTexts["Lantern puzzle"].exists)', 'XCTAssertTrue(app.staticTexts["Library choices"].waitForExistence(timeout: 5))', 'XCTAssertEqual(app.buttons["club.story.expand"].label, "Read full story")', 'XCTAssertTrue(app.staticTexts["No gameplay in this chapter yet"].waitForExistence(timeout: 5))', 'XCTAssertTrue(app.staticTexts["这一章还没有玩法"].waitForExistence(timeout: 5))', 'XCTAssertFalse(app.buttons["club.story.template.3"].exists)', 'XCTAssertFalse(app.buttons["club.story.answer.3"].exists)']:
            self.assertIn(expected, s)
