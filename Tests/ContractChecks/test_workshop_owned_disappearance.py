from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class WorkshopOwnedDisappearanceChecks(unittest.TestCase):
 def test_identity_guard_precedes_task_cancellation(self):
  source=(ROOT/'App/WorkshopOwnedNavigationState.swift').read_text()
  for scope in ['list','detail','package']:
   body=source.split('func '+scope+'Disappeared(',1)[1].split('    }',1)[0]
   self.assertLess(body.index(scope+'Permit === presentation'),body.index(scope+'Task?.cancel()'))
  self.assertIn('guard selection?.id == claimId, !showsPackage else',source)
  self.assertIn('guard selection?.id == claimId, showsPackage else',source)
 def test_real_views_capture_prebuilt_appearance_for_first_frame_and_late_closure(self):
  for file,scopes in [('WorkshopOwnedLibraryView.swift',['list','detail']),('WorkshopOwnedPackageView.swift',['package'])]:
   source=(ROOT/'App'/file).read_text()
   self.assertIn('let displayed = navigation.',source)
   self.assertIn('let presentation = displayed.permit',source)
   for scope in scopes:self.assertIn('navigation.'+scope+'ViewDisappeared(displayed)',source)
   self.assertIn('navigation.'+scopes[0]+'ViewAppeared(displayed',source)
 def test_real_reader_and_hosted_journey_assertions_remain(self):
  source=(ROOT/'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
  for marker in ['testHostedListDetailPackageBackAndReopenIssueFreshPermits','testOldListDisappearance','testOldDetailDisappearance','testOldPackageDisappearance','testVisibleAppearanceClosesBeforeFirstRedraw','testBackBindingRetiresQueuedDetailAndPackage','testCurrentDisappearanceSuppressesHeld401','file: StaticString = #filePath','0..<100','20_000_000']:
   self.assertIn(marker,source)
if __name__=='__main__':unittest.main()
