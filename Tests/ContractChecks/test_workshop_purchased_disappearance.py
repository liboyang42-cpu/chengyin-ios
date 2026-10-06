from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PurchasedDisappearanceChecks(unittest.TestCase):
 def test_identity_is_checked_before_cancelling_current_task(self):
  s=(ROOT/'App/WorkshopPurchasedNavigationState.swift').read_text()
  for kind in ['list','detail']:
   body=s.split(f'func {kind}Disappeared(_ presentation:',1)[1].split('\n    }',1)[0]
   self.assertLess(body.index(f'{kind}Permit === presentation'),body.index(f'{kind}Task?.cancel()'))
   self.assertNotIn(f'if let permit = {kind}Permit',body)
 def test_actual_views_use_prebuilt_owned_appearance_and_captured_read_actions(self):
  s=(ROOT/'App/WorkshopPurchasedLibraryView.swift').read_text()
  self.assertNotIn('@State private var appearance',s)
  self.assertEqual(s.count('let displayed = navigation.'),2)
  self.assertEqual(s.count('let rendered = displayed.permit'),2)
  for kind in ['list','detail']:
   self.assertIn(f'navigation.{kind}ViewDisappeared(displayed)',s)
   self.assertNotIn(f'navigation.{kind}Disappeared()',s)
  owner=(ROOT/'App/WorkshopPurchasedNavigationState.swift').read_text()
  for kind in ['list','detail']: self.assertIn(f'if {kind}Appearance === displayed {{ {kind}Appearance = WorkshopPurchasedViewAppearance() }}',owner)
 def test_appearance_installs_synchronously_and_cannot_revive_after_close(self):
  s=(ROOT/'App/WorkshopPurchasedNavigationState.swift').read_text().split('final class WorkshopPurchasedViewAppearance',1)[1]
  self.assertIn('guard !closed else { return nil }',s)
  self.assertIn('permit = issue()',s)
  self.assertIn('closed = true; retire(permit)',s)
  self.assertNotIn('Task {',s)
 def test_real_navigation_and_transport_regressions_are_preserved(self):
  s=(ROOT/'Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift').read_text()
  for name in ['testLateOldListDisappearCannotCancelNewScheduledTransportRead','testLateOldDetailDisappearCannotCancelReopenedSameLicenseRead','testRealViewAppearanceBoxCapturesPermitBeforeFirstRedrawAndCannotReappearAfterClose','testOldListViewCallbackAfterPushBackAndNewAppearanceKeepsNewRows','testOldDetailViewCallbackCannotClearNewAppearanceOrItsOfferedRead','testCurrentCapturedDisappearStillBlocksLate401ForListAndDetail']:
   self.assertIn('func '+name,s)
  self.assertIn('await h.wire.waitForPending()',s)
  self.assertIn('h.wire.resume((Data(), 401))',s)
if __name__=='__main__':unittest.main()
