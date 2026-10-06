from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PreferenceSourceEdgeScrollChecks(unittest.TestCase):
 def test_gutter_full_visibility_and_exact_byte_oracles_remain(self):
  s=(ROOT/'Tests/AppUITests/TemplatePreferenceDraftEditorFlowTests.swift').read_text()
  for marker in ['bounds.contains(frame) && source.isHittable','frame.minX - 12','guard x < frame.minX','bounds.minY - frame.minY + 8','bounds.maxY - frame.maxY - 8','withVelocity: .slow, thenHoldForDuration: 0.1','actual.map { Array($0.utf8) }','assertBytes(current.replacingOccurrences(of: insertion, with: ""), equal: original)','XCTAssertFalse(button.isEnabled, identifier)']:
   self.assertIn(marker,s)
 def test_three_recorded_source_frames_converge_without_relaxing_full_visibility(self):
  # Exact scalar formula, not a UIKit execution claim.
  top,bottom,height=176.3,872,456
  for start in [526.3,627,507.3]:
   y=start
   for _ in range(35):
    if top<=y and y+height<=bottom:break
    delta=top-y+8 if y<top else bottom-y-height-8
    y+=min((bottom-top)*.25,max(-(bottom-top)*.25,delta))
   self.assertGreaterEqual(y,top);self.assertLessEqual(y+height,bottom)
if __name__=='__main__':unittest.main()
