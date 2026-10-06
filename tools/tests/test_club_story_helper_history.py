import hashlib
from pathlib import Path
import unittest
from tools.tests.club_story_helper_history import before_horizontal_chapter_query, OLD_HELPER_SHA256, CURRENT_HELPER_SHA256, PREVIOUS_HELPER_SHA256
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
        previous=(ROOT/'tools/tests/fixtures/run114_published_sources/ClubStoryFlowTests.swift.txt').read_text()
        previous=previous[previous.index('    private var app:'):previous.index('    func test')]
        self.assertEqual(hashlib.sha256(previous.encode()).hexdigest(), PREVIOUS_HELPER_SHA256)
        # Original reviewed swipe negative controls remain against their original bytes.
        for old, new in [('visible.contains(frame)', 'visible.intersects(frame)'), ('matches.count == 1', 'matches.count >= 1'), ('scroller.swipeRight()', 'scroller.swipeLeft()')]:
            self.assertIn(old, previous)
            with self.assertRaises(AssertionError): before_horizontal_chapter_query(previous.replace(old,new))
        # New adaptive implementation must retain exact geometry and actual gesture.
        for old,new in [('visible.contains(frame)','visible.intersects(frame)'),('matches.count == 1','matches.count >= 1'),('start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)','start.tap()'),('withVelocity: .slow','withVelocity: .fast'),('thenHoldForDuration: 0.2','thenHoldForDuration: 0'),('visible.minX - frame.minX + 8','0'),('max(abs(delta), 32)','abs(delta)'),('min(visible.width * 0.35, oppositeEdgeSpace)','visible.width * 0.35'),('progress > 0.5','true')]:
            self.assertIn(old, source)
            with self.assertRaises(AssertionError):before_horizontal_chapter_query(source.replace(old,new))
