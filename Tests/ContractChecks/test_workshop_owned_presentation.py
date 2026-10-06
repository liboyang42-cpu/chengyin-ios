"""Queued/in-flight presentation source checks. Swift and actual hosted UI tests remain separate."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class WorkshopPresentationContracts(unittest.TestCase):
 def source(self,path):return (ROOT/path).read_text()
 def test_presentation_cannot_revive_and_action_is_single_use(self):
  s=self.source('Core/WorkshopOwnedPresentation.swift')
  for marker in ['func revoke() { isLive = false','guard isLive else { return nil }','currentAction?.revoke()','weak var presentation','func claim() -> Bool','!entered','presentation?.currentAction === self']:
   self.assertIn(marker,s)
  self.assertNotIn('isLive = true }',s)
 def test_core_rejects_offer_before_mutating_or_starting_service(self):
  for path,call in [('Core/WorkshopOwnedBrowser.swift','listPresentation === presentation'),('Core/WorkshopOwnedPackageBrowser.swift','presentation === permit')]:
   s=self.source(path);self.assertIn(call,s);self.assertIn('action.claim()',s);self.assertIn('WorkshopOwnedReadLifetime(action: action)',s)
   self.assertNotIn('func load()',s)
  s=self.source('Core/WorkshopOwnedService.swift');self.assertIn('guard action?.isLive != false',s);self.assertIn('try check(lifetime); onUnauthorized(lease.context)',s)
 def test_view_buttons_capture_rendered_presentation_before_scheduling(self):
  a=self.source('App/WorkshopOwnedLibraryView.swift');b=self.source('App/WorkshopOwnedPackageView.swift')
  for s in [a,b]:
   self.assertIn('let presentation = displayed.permit',s);self.assertIn('.refreshable { [permit = presentation]',s);self.assertNotIn('Task {',s)
  self.assertIn('scheduleList(presentation)',a);self.assertIn('scheduleDetail(presentation, claimId: claimId)',a);self.assertIn('schedulePackage(presentation, claimId: claimId)',b)
  self.assertIn('.onAppear { navigation.scheduleList(navigation.listViewAppeared(displayed)) }',a)
 def test_navigation_push_retires_actions_without_clearing_needed_rows(self):
  s=self.source('App/WorkshopOwnedNavigationState.swift')
  self.assertIn('browser.leaveList(permit, closing: false)',s);self.assertIn('browser.leaveDetail(permit, closing: false)',s)
  self.assertLess(s.index('browser.leaveList(permit, closing: false)'),s.index('selection = .init'))
  self.assertLess(s.index('browser.leaveDetail(permit, closing: false)'),s.index('showsPackage = true'))
  self.assertIn('listPermit === presentation',s);self.assertIn('detailPermit === presentation',s)
 def test_actions_are_offered_synchronously_before_task_and_passed_unchanged(self):
  s=self.source('App/WorkshopOwnedNavigationState.swift')
  for scope in ['List','Detail','Package']:
   self.assertIn('func offer'+scope,s);self.assertIn('func schedule'+scope,s)
  self.assertIn('guard let action = offerList(permit) else { return }; listTask?.cancel(); listTask = Task { await action() }',s)
  self.assertIn('await browser.load(action: action)',s);self.assertIn('await browser.open(claimId: claimId, action: action)',s)
 def test_actual_navigation_host_and_queued_service_regressions_are_authored(self):
  s=self.source('Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift')
  for marker in ['UIHostingController(rootView: NavigationStack','window.makeKeyAndVisible()','testHostedListDetailPackageBackAndReopenIssueFreshPermits','f.navigation.showsPackage = false','f.navigation.selection = nil']:
   self.assertIn(marker,s)
  s=self.source('Tests/CoreTests/WorkshopOwnedQueuedPresentationTests.swift')
  for marker in ['WorkshopOwnedService(', 'testQueuedListAfterBack','testQueuedDetailAfterBack','testQueuedPackageAfterBack','testNewOfferBeforeQueuedEntry','testQueuedActionAfterIdentityABA','testValidCurrentPresentation401']:
   self.assertIn(marker,s)
if __name__=='__main__':unittest.main()
