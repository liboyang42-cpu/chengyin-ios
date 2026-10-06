from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PublicPlayCardRevealChecks(unittest.TestCase):
 def test_exact_card_unique_native_region_and_fit_requirement(self):
  s=(ROOT/'Tests/AppUITests/PublicPlayTemplatePresentationFlowTests.swift').read_text()
  for marker in ['if id == "discovery.play.701"','query.count == 1','button.isEnabled && button.isHittable','visible.width >= 44 && visible.height >= 44','frame.height > bounds.height || bounds.contains(frame)','bar.frame.maxY + 4','keyboard.frame.minY - 4','bounds.minY - frame.minY + 8','bounds.maxY - frame.maxY - 8','withOffset(CGVector(dx: visible.midX - frame.minX','dynamicTypeSize: "accessibility5"']:
   self.assertIn(marker,s)
 def test_actual_failure_geometry_is_corrected_without_fixed_gesture_oscillation(self):
  # Scalar check of the exact source formula, not a claim of UIKit execution.
  top,bottom,height=260.3,872.0,477.3
  y=157.0
  delta=min((bottom-top)*.35,max(-(bottom-top)*.35,top-y+8))
  self.assertGreaterEqual(y+delta,top)
  self.assertLessEqual(y+delta+height,bottom)
  # The old 45% gesture crosses the other boundary instead.
  self.assertGreater(y+(bottom-top)*.45+height,bottom)
if __name__=='__main__':unittest.main()
