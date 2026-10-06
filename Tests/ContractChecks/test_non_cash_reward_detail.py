"""Source-only reward detail guards. Native XCTest/Apple runtime is separate evidence."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
class NonCashRewardDetailChecks(unittest.TestCase):
    def read(self, file): return (ROOT/file).read_text()
    def test_selection_is_captured_before_lazy_destination(self):
        view=self.read('App/NonCashRewardViews.swift')
        body=view.split('ForEach(model.state.visibleSelections(scope: key.scope))',1)[1].split('if model.state.isLoadingMore',1)[0]
        self.assertLess(body.index('let destination = NonCashRewardDetailDestination(selection: selection)'),body.index('NavigationLink {'))
        self.assertIn('.id(destination.id)',body)
        destination=body.split('NavigationLink {',1)[1].split('} label:',1)[0]
        self.assertNotIn('ownerScope:',destination);self.assertNotIn('key.scope',destination);self.assertNotIn('reader.scope',destination)
        collection=self.read('Core/NonCashRewardCollectionModel.swift')
        self.assertIn('ownerScope: loadedScope',collection)
        selection=self.read('Core/NonCashRewardDetailProjection.swift')
        self.assertIn('public let ownerScope: UUID',selection)
        for field in ['ownerScope','awardId','contextType','contextId','releaseId','instanceId','rulesVersion']:
            self.assertIn(field,selection.split('public struct Identity:',1)[1])
    def test_model_fences_owner_before_dispatch_and_keeps_accepted_terminal_reference(self):
        source=self.read('Core/NonCashRewardDetailModel.swift')
        self.assertLess(source.index('guard scope == selection.ownerScope'),source.index('try await reader.reward'))
        self.assertIn('latestReference = NonCashRewardReference(reward)',source)
        self.assertIn('let reference = latestReference',source)
        self.assertIn('scope == selection.ownerScope && loadedScope == scope',source)
        for required in ['activeRead?.invalidate()', 'captured == generation', 'reader.isAuthenticated, reader.isConfigured']:
            self.assertIn(required,source)
    def test_real_reader_lifetime_fences_precede_unauthorized_callback(self):
        source=self.read('Core/NonCashRewardReading.swift')
        private=source.split('private func read<T>',1)[1]
        self.assertIn('try lifetime?.check()',private)
        catch=private.split('} catch {',1)[1]
        self.assertLess(catch.index('lifetime?.isActive != false'),catch.index('onUnauthorized(session)'))
        self.assertIn('currentSession() == session, scope == captured',catch)
        self.assertIn('lifetime: NonCashRewardReadLifetime? = nil',private)
    def test_exact_frozen_terms_and_no_invented_facts(self):
        source=self.read('Core/NonCashRewardDetailProjection.swift')
        for field in ['awardId','contextType','contextId','releaseId','instanceId','rulesVersion','merchantId','storeId','rewardTitle','quantity','validFrom','validUntil','redemptionConditions','awardedAt']:
            self.assertIn('reward.'+field+' == old.'+field,source)
        for fact in ['qualification','claimProgress','allocation','sourceEvent']:
            self.assertIn('public let '+fact+': FactAvailability = .notProvided',source)
        self.assertIn('reward.asOf >= old.asOf',source);self.assertIn('old.state == .awarded || reward.state == old.state',source)
        self.assertIn('reward.asOf >= reward.validUntil ? .elapsed',source)
    def test_new_copy_is_bilingual_and_preserves_honest_read_boundary(self):
        catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        keys=[k for k in catalog if k.startswith('rewards.read.')]
        self.assertEqual(len(keys),19)
        for key in keys:
            for locale in ['en','zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][locale]['stringUnit']['value'])
        self.assertIn('not establish current eligibility',catalog['rewards.read.qualificationHint']['localizations']['en']['stringUnit']['value'])
        self.assertIn('Later merchant changes do not extend',catalog['rewards.read.frozenTerms']['localizations']['en']['stringUnit']['value'])
    def test_source_only_ui_preserves_live_default_and_presentation_grants(self):
        source=self.read('App/NonCashRewardViews.swift')
        self.assertIn('model.state.selection.ownerScope != key.scope',source)
        self.assertIn('reader.isAuthenticated, reader.isConfigured, reader.isOfflineExample',source)
        self.assertIn('private let nonCashRewardService: NonCashRewardService? = nil',self.read('App/AppSession.swift'))
        for file in ['Core/NonCashRewardDetailProjection.swift','Core/NonCashRewardDetailModel.swift','App/NonCashRewardDetailReadSupport.swift']:
            for forbidden in ['URLSession','POST','COUPON','SERVICE','CITY','redeem(', 'reserve(', 'issueReward(']:
                self.assertNotIn(forbidden,self.read(file))
    def test_real_lifecycle_and_deferred_destination_regressions_are_authored(self):
        lifetime=self.read('Tests/CoreTests/NonCashRewardDetailLifetimeTests.swift')
        self.assertIn('NonCashRewardSessionReader(service: NonCashRewardService(',lifetime)
        for name in ['testBackOrCloseInvalidatesLate401BeforeSessionCallback','testNewRefreshInvalidatesOlder401AndAcceptsOnlyCurrentResult','testTaskCancellationSuppressesLate401AndStopsLoading','testCurrent401StillExpiresOnlyTheCurrentSession','testInvalidatedReadDoesNotDispatchAndCollectionCallbackRemainsCompatible','testSessionSwitchWhilePushedSuppressesOld401WithoutNewDispatch']:
            self.assertIn(name,lifetime)
        app=self.read('Tests/AppUnitTests/NonCashRewardDetailCompositionTests.swift')
        self.assertIn('testAcceptedRowSelectionRetainedBeforeDestinationConstructionCannotRebindAccount',app)
        self.assertIn('testPushedScreenHidesOldScopeAndRefusesAnotherAccountRead',app)
        self.assertEqual(len(re.findall(r'func test\w+',lifetime)),8)
        self.assertEqual(len(re.findall(r'func test\w+',self.read('Tests/CoreTests/NonCashRewardDetailTests.swift'))),15)
        self.assertEqual(len(re.findall(r'func test\w+',app)),17)
    def test_project_registers_new_app_source_and_app_hosted_tests(self):
        project=self.read('Questify.xcodeproj/project.pbxproj')
        for file in ['Core/NonCashRewardDetailModel.swift','Core/NonCashRewardDetailProjection.swift','App/NonCashRewardDetailReadSupport.swift','Tests/AppUnitTests/NonCashRewardDetailCompositionTests.swift']:
            self.assertIn(file,project)
        ui=self.read('Tests/AppUITests/NonCashRewardFlowTests.swift')
        self.assertEqual(ui.count('func testDetailDisclosesFrozenTermsExactMapOriginAndUnavailableClaimFacts'),1)
        self.assertIn('480 seconds, unmeasured',ui)
        self.assertIn('XCTAssertFalse(app.buttons["Claim reward"].exists)',ui)

    def test_detail_owns_queued_task_and_offer_lifetime_before_dispatch(self):
        source=self.read('App/NonCashRewardViews.swift')
        detail=source.split('private struct NonCashRewardDetailView: View {',1)[1].split('private struct NonCashRewardDetailContent:',1)[0]
        self.assertNotIn('Task {',detail);self.assertNotIn('AccountCollectionReadLifecycle',detail)
        self.assertIn('appearance.begin(model: model, foreground: scenePhase == .active)',detail)
        self.assertIn('appearance.end(model: model)',detail)
        self.assertNotIn('model.endPresentation()',detail)
        support=self.read('App/NonCashRewardDetailReadSupport.swift')
        self.assertIn('task?.cancel()',support);self.assertIn('offeredRead?.invalidate()',support)
        schedule=support.split('func scheduleRefresh(reader:',1)[1].split('/// SwiftUI owns',1)[0]
        self.assertLess(schedule.index('offerRefresh(reader: reader, presentation: permit)'),schedule.index('Task {'))
        self.assertIn('offer.isActive, self.offeredRead === offer',support)
        tests=self.read('Tests/AppUnitTests/NonCashRewardDetailCompositionTests.swift')
        for name in ['testOfferedRefreshQueuedBeforeCloseCannotDispatchWhenExecutedLater','testCloseThenReopenDoesNotReactivateOldOfferButNewOfferWorks','testActualOwnedRetryTaskQueuedThenClosedDoesNotDispatch','testForegroundQueuedRefreshCannotRunAfterCloseOrBackground']:
            self.assertIn(name,tests)

    def test_same_offer_reaches_model_and_reader_and_checks_before_invalidation(self):
        support=self.read('App/NonCashRewardDetailReadSupport.swift')
        self.assertIn('state.refresh(reader: reader, offeredLifetime: offer)',support)
        model=self.read('Core/NonCashRewardDetailModel.swift').split('public func refresh(',1)[1]
        self.assertLess(model.index('offeredLifetime?.isActive != false'),model.index('invalidate()'))
        self.assertIn('let lifetime = offeredLifetime ?? NonCashRewardReadLifetime()',model)
        self.assertIn('reader.reward(reference, lifetime: lifetime)',model)
        tests=self.read('Tests/CoreTests/NonCashRewardDetailLifetimeTests.swift')
        self.assertIn('testRevokedOfferCannotStartActualSessionReaderAfterQueuedModelHandoff',tests)
        self.assertIn('testObsoleteOfferCannotInvalidateAReopenedCurrentRead',tests)

    def test_deferred_swiftui_closures_capture_presentation_before_execution(self):
        source=self.read('App/NonCashRewardViews.swift').split('private struct NonCashRewardDetailView:',1)[1].split('private struct NonCashRewardDetailContent:',1)[0]
        self.assertIn('let appearance = viewPresentation',source)
        self.assertIn('let presentation = appearance.permit',source)
        self.assertIn('model.refresh(reader: reader, presentation: presentation)',source)
        self.assertIn('model.setForeground(phase == .active, reader: reader, presentation: presentation)',source)
        support=self.read('App/NonCashRewardDetailReadSupport.swift')
        self.assertIn('permit.isActive, presentation === permit',support)
        self.assertIn('permit.isActive, self.presentation === permit',support)
        self.assertIn('permit.invalidate(); presentation = nil',support)
        self.assertIn('testOldDeferredPullRefreshCannotBorrowReopenedPresentation',self.read('Tests/AppUnitTests/NonCashRewardDetailCompositionTests.swift'))

    def test_fact_identifiers_keep_exact_labeled_values_and_header_leaves(self):
        facts=self.read('App/NonCashRewardDetailReadSupport.swift').split('struct NonCashRewardReadFactsView:',1)[1]
        self.assertNotIn('}.accessibilityIdentifier("rewards.read.origin")',facts)
        self.assertNotIn('}.accessibilityIdentifier("rewards.read.qualification")',facts)
        self.assertIn('Text("rewards.read.origin").accessibilityIdentifier("rewards.read.origin.header")',facts)
        self.assertIn('Text("rewards.read.qualification").accessibilityIdentifier("rewards.read.qualification.header")',facts)
        self.assertIn('Text(verbatim: value).accessibilityIdentifier(id)',facts)
        self.assertIn('.accessibilityElement(children: .contain)',facts)
        ui=self.read('Tests/AppUITests/NonCashRewardFlowTests.swift')
        self.assertIn('("rewards.read.contextId.value", "Context identifier, example-map")',ui)
        self.assertIn('("rewards.read.instanceId.value", "Season identifier, example-season")',ui)
        for kind in ['eligibility','claimProgress','allocation']:
            self.assertIn('rewards.read.'+kind+'.value',ui)
        self.assertIn('XCTAssertEqual(query.count, 1)',ui)
        self.assertNotIn('app.staticTexts["example-map"]',ui)
        self.assertNotIn('app.staticTexts["example-season"]',ui)

    def test_close_identity_is_checked_before_cancel_and_view_captures_first_frame_owner(self):
        support=self.read('App/NonCashRewardDetailReadSupport.swift')
        end=support.split('func endPresentation(',1)[1].split('\n    }',1)[0]
        self.assertLess(end.index('presentation === permit'),end.index('cancelPending()'))
        view=self.read('App/NonCashRewardViews.swift').split('private struct NonCashRewardDetailView:',1)[1]
        self.assertIn('if appearance.end(model: model) { presenting = false }',view)
        self.assertIn('if viewPresentation === appearance',view)
        owner=support.split('final class NonCashRewardDetailViewPresentation',1)[1]
        self.assertIn('guard !isClosed else { return nil }',owner)
        self.assertIn('model.endPresentation(presentation: permit)',owner)
        tests=self.read('Tests/AppUnitTests/NonCashRewardDetailCompositionTests.swift')
        self.assertIn('NonCashRewardSessionReader(service: NonCashRewardService(',tests)
        for name in ['testLateOldCloseCannotCancelReopenedScreenReadThroughRealReader',
                     'testCloseCapturedBeforeOnAppearStillClosesPermitBeforeFirstRedraw',
                     'testCurrentViewCloseAfterStaleCloseSuppressesLateReal401',
                     'testStaleCloseDoesNotSuppressCurrentReal401']:
            self.assertIn('func '+name+'(',tests)
