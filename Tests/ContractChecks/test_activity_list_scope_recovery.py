"""Source coverage only; normal Activities runtime/navigation requires Apple tests."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ActivityListScopeRecoveryContracts(unittest.TestCase):
    def read(self,p): return (ROOT/p).read_text()
    def test_bound_identity_and_actual_mount_keep_independent_detail_grant(self):
        reading=self.read('App/ActivityReading.swift')
        for marker in ['ObjectIdentifier(reader)','reader.activityPresentationIdentity','"\\(sessionRevision):\\(contentDetailRevision)"','activityListReadAvailability == .available','objectWillChange.eraseToAnyPublisher()']:
            self.assertIn(marker,reading)
        session=self.read('App/AppSession.swift').split('var activityListReadAvailability:',1)[1].split('var contentDetailReadAvailability:',1)[0]
        self.assertIn('composition.readAvailability(.home, identity: compositionTransport.current())',session)
        self.assertIn('activityService != nil',session)
    def test_public_read_fences_late_identity_and_cancellation_before_expiration(self):
        read=self.read('App/AppSession.swift').split('func activities(page:Int,keyword:String)',1)[1].split('func activityDetail',1)[0]
        self.assertNotIn('guard account != nil',read)
        self.assertEqual(read.count('viewerRevision == compositionViewerRevision'),2)
        catch=read.split('} catch {',1)[1]
        self.assertLess(catch.index('!Task.isCancelled'),catch.index('expireIfMatching'))
    def test_value_owned_route_survives_replaced_list_but_uses_same_detail(self):
        view=self.read('App/ActivityBrowserView.swift')
        for marker in ['NavigationStack(path: $path)','NavigationLink(value: ActivityListDestination(id: item.id))','.navigationDestination(for: ActivityListDestination.self)','ActivityDetailView(id:destination.id,reader:reader,playReaderForActivity:playReaderForActivity','registrationEnabled:registrationEnabled,peopleProfile:peopleProfile)']:
            self.assertIn(marker,view)
        self.assertNotIn('.id(identity)',view)
        self.assertIn('.onChange(of: ObjectIdentifier(reader)) { _, _ in path = [] }',view)
    def test_loader_keeps_query_paging_and_guards_both_success_and_failure(self):
        view=self.read('App/ActivityBrowserView.swift')
        for marker in ['appliedQuery = keyword','reader.activities(page: next, keyword: appliedQuery)','guard current()','catch { if current() { failed = true } }','hasMore = result.count >= 10','.task(id: identity)','.onDisappear { loads.cancel(); model.cancelPending() }']:
            self.assertIn(marker,view)
        self.assertNotIn('Task { await model.load',view)
    def test_authored_tests_preserve_guest_aba_late_401_and_active_detail_contract(self):
        tests=self.read('Tests/AppUnitTests/ActivityListScopeRecoveryTests.swift')
        for name in ['testAppliedQueryRawPagingAndReplacementViewerReset','testOldSuccessAnd401CannotReplaceLoadedNewViewerAfterABA','testDismissalCancelsOwnedReadWithoutDisplayingLate401','testReaderInstanceAndUnavailableGrantCannotReuseOldCache','testGuestLoginRoleABAAndLogoutKeepPublicListAuthority','testAuthenticationAndMountedServiceDoNotCreateListGrant','testRoleABAOwnerExitAndCancellationRejectLateSuccessAndBoth401Forms','testCurrentHTTPAndEnvelope401StillExpireCurrentOwner']:
            self.assertIn(name,tests)
        ui=self.read('Tests/AppUITests/SignedInContentDetailFlowTests.swift').split('func testActivityTopicRouteClearsOnRoleChangeAndSignOut()',1)[1].split('func testActivityTopicFailure',1)[0]
        self.assertLess(ui.index('Synthetic merchant route'),ui.index('app.navigationBars["Route details"].buttons.firstMatch.tap()'))
        self.assertIn('Synthetic merchant activity card',ui)
        self.assertIn('Sign-out must not dispatch a detail read',ui)
