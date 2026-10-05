"""Observable account-read presentation and cancellation wiring; Apple UI is separate."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class SocialPresentationRevisionContracts(unittest.TestCase):
    def read(self,p): return (ROOT/p).read_text()
    def test_production_and_fixture_identity_are_observable_without_changing_read_authority(self):
        core=self.read('Core/SocialAccountReading.swift')
        self.assertIn('import Observation',core)
        self.assertIn('@MainActor @Observable public final class SocialAccountSessionReader',core)
        self.assertIn('public private(set) var presentationRevision: UInt64 = 0',core)
        self.assertIn('public func invalidatePresentation() { presentationRevision &+= 1 }',core)
        self.assertIn('public var presentationRevision: UInt64 { 0 }',core)
        self.assertIn('@MainActor @Observable final class SocialAccountFixtureReader',self.read('App/SocialAccountFixtureSupport.swift'))
        self.assertIn('operation(service, snapshot.token)',core)
        self.assertNotIn('Approval(',core)
    def test_existing_session_owner_notifies_after_identity_revision_changes(self):
        session=self.read('App/AppSession.swift')
        block=session.split('let identityChanged =',1)[1].split('let oldAccount =',1)[0]
        for identity in ['entryObservedStamp','entryObservedAccountID','entryObservedToken','entryObservedRole']:
            self.assertIn(identity,block)
        self.assertIn('compositionViewerRevision &+= 1\n            socialAccountReader.invalidatePresentation()',block)
    def test_reader_fences_presentation_revision_before_current_401_side_effect(self):
        core=self.read('Core/SocialAccountReading.swift')
        self.assertIn('let snapshot = currentSession(), revision = presentationRevision',core)
        self.assertEqual(core.count('presentationRevision == revision'),2)
        catch=core.split('} catch {',1)[1]
        self.assertLess(catch.index('presentationRevision == revision'),catch.index('onUnauthorized(snapshot)'))
        self.assertIn('!Task.isCancelled',catch)
    def test_screen_never_reuses_obsolete_key_and_owns_every_reload(self):
        screen=self.read('App/SocialAccountComponents.swift')
        for marker in ['ObjectIdentifier(reader)','revision = reader.presentationRevision','loadedKey != key || busy',
                       '.task(id: key) { await loads.run { await reload() } }',
                       'loads.start { await reload() }','loads.cancel(); generation += 1',
                       'guard generation == run, key == captured','if !Task.isCancelled, generation == run, key == captured']:
            self.assertIn(marker,screen)
        self.assertNotIn('Task { await reload() }',screen)
    def test_existing_old_content_assertions_are_retained_and_new_tests_cover_real_reader(self):
        ui=self.read('Tests/AppUITests/SocialAccountFlowTests.swift')
        scenario=ui.split('func testChineseLargeTextArticleReplacesOldContentAfterAccountSwitch()',1)[1].split('func testArticleRemoved',1)[0]
        self.assertEqual(scenario.count('XCTAssertFalse(text("示例正文标题").exists)'),2)
        self.assertIn('text("替换正文标题").waitForExistence(timeout: 5)',scenario)
        core=self.read('Tests/CoreTests/SocialPresentationRevisionTests.swift')
        for marker in ['withObservationTracking','testAccountRoleTokenLogoutAndRevisionABARejectLateSuccessAndBoth401Forms',
                       'testCancelledReadCannotExpireCurrentViewerWhenTransportIgnoresCancellation',
                       'testCurrent401StillExpiresSignedInViewerButPublicGuestReadHasNoCredential']:
            self.assertIn(marker,core)
        self.assertIn('testNormalSessionLoginRoleABAAndLogoutInvalidateSameSocialReaderWithoutGrantingReads',self.read('Tests/AppUnitTests/SocialPresentationIdentityAppTests.swift'))
