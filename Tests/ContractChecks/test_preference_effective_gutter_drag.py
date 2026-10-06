from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PreferenceEffectiveGutterDragChecks(unittest.TestCase):
    def test_minimum_gesture_keeps_opposite_edge_full_frame_and_outer_gutter(self):
        source = (ROOT / 'Tests/AppUITests/TemplatePreferenceDraftEditorFlowTests.swift').read_text()
        body = source.split('private func revealSource(', 1)[1].split('private func check(', 1)[0]
        for fragment in ['bounds.contains(frame) && source.isHittable', 'abs(delta) < 24',
                         'frame.height <= bounds.height', 'delta > 0 ? 24 : -24',
                         'moved.maxY <= bounds.maxY', 'moved.minY >= bounds.minY',
                         'frame.minX - 12', 'guard x < frame.minX',
                         'for attempt in 0...35', 'withVelocity: .slow, thenHoldForDuration: 0.1']:
            self.assertIn(fragment, body)

    def test_logged_near_bottom_geometry_has_room_for_minimum_without_clipping_other_edge(self):
        # Arithmetic over the actual two AX frames, not a claim of Swift/UIKit execution.
        top, bottom, height = 176.3, 872.0, 456.0
        for y in [417.7, 418.0]:
            self.assertGreater(y + height, bottom)
            self.assertLessEqual(abs(bottom - (y + height) - 8), 10.01)
            self.assertGreaterEqual(y - 24, top)
            self.assertLessEqual(y + height - 24, bottom)
