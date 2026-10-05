import hashlib
from pathlib import Path
import unittest
from tools.tests.club_story_helper_history import before_horizontal_chapter_query, OLD_HELPER_SHA256, CURRENT_HELPER_SHA256
ROOT = Path(__file__).resolve().parents[2]
class ClubStoryHelperHistory(unittest.TestCase):
    def helper(self, case):
        s = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
        return s[s.index('    private var app:'):s.index('    func test')]
    def test_exact_current_helper_reverses_to_original_unchanged_navigation_helper(self):
        current = self.helper('ClubStoryFlowTests')
        original = self.helper('ClubStoryNavigationFlowTests')
        self.assertEqual(hashlib.sha256(current.encode()).hexdigest(), CURRENT_HELPER_SHA256)
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), OLD_HELPER_SHA256)
        self.assertEqual(before_horizontal_chapter_query(current), original)
        self.assertEqual(before_horizontal_chapter_query(original), original)
    def test_weakened_visibility_duplicate_query_or_removed_swipe_is_rejected(self):
        source = self.helper('ClubStoryFlowTests')
        for old, new in [('visible.contains(frame)', 'visible.intersects(frame)'), ('matches.count == 1', 'matches.count >= 1'), ('scroller.swipeRight()', 'scroller.swipeLeft()')]:
            self.assertIn(old, source)
            with self.assertRaises(AssertionError): before_horizontal_chapter_query(source.replace(old, new))
