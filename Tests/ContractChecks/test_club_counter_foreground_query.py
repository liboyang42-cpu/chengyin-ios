"""Recorded run108 query mismatch. This does not substitute for an Apple rerun."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ClubCounterForegroundContracts(unittest.TestCase):
    def test_counter_prefers_toolbar_leaf_without_weakening_visibility_or_uniqueness(self):
        source=(ROOT/'Tests/AppUITests/ClubOperationsFlowTests.swift').read_text()
        counter=source.split('private var visibleWriteCounters:',1)[1].split('private var writeCounter:',1)[0]
        self.assertIn('app.toolbars.staticTexts.matching(identifier: "club.ops.writeCount")',counter)
        self.assertIn('if presented.count > 0 { return visible(presented.allElementsBoundByIndex) }',counter)
        self.assertIn('$0.exists && $0.isHittable && !$0.frame.isEmpty && app.frame.contains($0.frame)',counter)
        self.assertIn('counters.count == 1 && counters[0].label == String(value)',source)
        self.assertIn('account=702;finished=1',source)
        self.assertIn('XCTAssertFalse(element("club.ops.acknowledged").exists); count(1)',source)
        self.assertIn('XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists); count(1)',source)
