from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PurchasedRouteReturnChecks(unittest.TestCase):
 def test_route_owner_rotates_appearance_before_old_callbacks(self):
  s=(ROOT/'App/WorkshopPurchasedNavigationState.swift').read_text()
  for x in ['listAppearance = WorkshopPurchasedViewAppearance()','detailAppearance = WorkshopPurchasedViewAppearance()','guard listAppearance === displayed','guard detailAppearance === displayed']:
   self.assertIn(x,s)
  v=(ROOT/'App/WorkshopPurchasedLibraryView.swift').read_text()
  for scope in ['list','detail']:
   self.assertIn('let displayed = navigation.'+scope+'Appearance',v)
   self.assertIn('navigation.'+scope+'ViewDisappeared(displayed)',v)
  self.assertNotIn('@State private var appearance',v)
 def test_normal_model_return_and_observation_regressions_exist(self):
  s=(ROOT/'Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift').read_text()
  self.assertIn('testRouteReturnBeforeOldDisappearHasFreshBoxAndCannotBeCancelledByOldPage',s)
  self.assertIn('testDefaultOffNormalAccountReadsDoNotEmitObservationChanges',s)
  self.assertIn('testRealInvalidationStillPublishesAndSubsequentDisabledReadsStayQuiet',s)
if __name__=='__main__':unittest.main()
