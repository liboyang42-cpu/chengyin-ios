from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class TopicTemplateOversizedRow(unittest.TestCase):
    def test_only_exact_fixture_cards_can_use_visible_intersection(self):
        s=(ROOT/'Tests/AppUITests/TopicTemplateNameSearchFlowTests.swift').read_text()
        for text in ['["discovery.topic.801", "discovery.topic.802"].contains(id)','query.count == 1','query.count > 1',
                     'button.isEnabled && button.isHittable','frame.height > bounds.height','frame.intersection(bounds)',
                     'visible.width >= 44 && visible.height >= 44','(oversized || bounds.contains(frame))',
                     'keyboard.frame.minY - 4','bar.frame.maxY + 4','frame.minX >= bounds.minX && frame.maxX <= bounds.maxX']:
            self.assertIn(text,s)
    def test_tap_is_inside_exact_element_region_and_not_a_generic_fallback(self):
        s=(ROOT/'Tests/AppUITests/TopicTemplateNameSearchFlowTests.swift').read_text()
        self.assertIn('button.coordinate(withNormalizedOffset: .zero)',s)
        self.assertIn('visible.midX - frame.minX, dy: visible.midY - frame.minY',s)
        self.assertIn('for attempt in 0...12',s)
        self.assertIn('XCTFail("Exact topic card has no safe enabled visible region:',s)
    def test_search_scope_maximum_text_and_no_adoption_assertions_remain(self):
        s=(ROOT/'Tests/AppUITests/TopicTemplateNameSearchFlowTests.swift').read_text()
        for text in ['dynamicTypeSize: "accessibility5"','colorScheme: "dark"','--uitesting-reduce-motion',
                     'label == \'neighborhood\'','XCTAssertFalse(app.buttons["discovery.topic.802"].exists)',
                     'XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)',
                     'app.navigationBars.buttons.firstMatch.tap()','app.swipeDown()']:
            self.assertIn(text,s)
