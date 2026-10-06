from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ClubStoryAdaptiveChapterScrollChecks(unittest.TestCase):
 def test_unique_enabled_whole_chapter_assertions_and_journey_remain(self):
  s=(ROOT/'Tests/AppUITests/ClubStoryFlowTests.swift').read_text()
  for marker in ['scrollers.count == 1','matches.count == 1','visible.contains(frame), button.isEnabled, button.isHittable','visible.minX - frame.minX + 8','visible.maxX - frame.maxX - 8','start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)','tap("club.story.chapter.2")','XCTAssertFalse(app.buttons["club.story.answer.3"].exists)']:
   self.assertIn(marker,s)
  self.assertNotIn('scroller.swipeLeft()',s);self.assertNotIn('scroller.swipeRight()',s)
 def test_observed_middle_chapter_converges_in_bounded_selector_geometry(self):
  # Tests the copied scalar formula, not UIKit behavior.
  for start in [-173.7,280.3]:
   x=start;left,right,width=40,380,257.7
   for _ in range(8):
    if left<=x and x+width<=right:break
    d=left-x+8 if x<left else right-x-width-8
    x+=min((right-left)*.35,max(-(right-left)*.35,d))
   self.assertGreaterEqual(x,left);self.assertLessEqual(x+width,right)
if __name__=='__main__':unittest.main()
