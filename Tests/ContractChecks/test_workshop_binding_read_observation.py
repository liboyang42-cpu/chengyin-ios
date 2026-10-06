from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class WorkshopBindingObservationChecks(unittest.TestCase):
 def test_empty_invalidation_returns_before_any_observable_write(self):
  source=(ROOT/'App/WorkshopOwnedSessionBinding.swift').read_text().split('func invalidate()',1)[1]
  guard='guard browser != nil || captured != nil || revision != nil else { return }'
  self.assertIn(guard,source)
  self.assertLess(source.index(guard),source.index('browser?.invalidate()'))
  self.assertLess(source.index(guard),source.index('browser = nil'))
 def test_normal_session_observation_and_real_revocation_are_both_authored(self):
  source=(ROOT/'Tests/AppUnitTests/WorkshopOwnedNormalAccountTests.swift').read_text()
  for marker in ['testDefaultOffNormalAccountReadsDoNotEmitObservationChanges','testRealInvalidationStillPublishesAndSubsequentDisabledReadsStayQuiet','withObservationTracking { h.session.workshopOwnedBrowser }','changed.isInverted = true','XCTAssertEqual(original.phase, .invalidated)','XCTAssertFalse(original === replacement)']:
   self.assertIn(marker,source)
if __name__=='__main__':unittest.main()
