"""Supplementary source contracts only; Swift/Apple behavior remains a separate gate."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class OwnedCouponLifecycleContracts(unittest.TestCase):
    def read(self, name):
        return (ROOT / name).read_text()

    def test_list_captures_accepted_owner_before_deferred_detail(self):
        model = self.read('App/OwnedCouponReadSupport.swift')
        self.assertIn('loadedRequest == request', model)
        self.assertIn('ownerScope: accepted.ownerScope', model)
        source = self.read('App/AccountCollectionCouponsView.swift')
        self.assertLess(source.index('let selection = selections[index]'), source.index('NavigationLink {'))
        self.assertIn('AccountCollectionCouponDetailView(selection: selection, reader: reader).id(selection.id)', source)
        self.assertNotIn('AccountCollectionCouponDetailView(id:', source)
        self.assertNotIn('AccountCollectionReadLifecycle', source)

    def test_retained_detail_code_destination_has_scope_before_factory(self):
        source = self.read('App/AccountCollectionCouponDetailView.swift')
        self.assertIn('let selection: OwnedCouponDetailSelection', source)
        self.assertIn('selection.ownerScope != reader.scope', source)
        self.assertLess(source.index('let destination = OwnedCouponCodeDestination(selection: selection)'), source.index('NavigationLink {'))
        self.assertIn('.id(destination.id)', source)
        support = self.read('App/OwnedCouponReadSupport.swift').split('func makeCoordinator', 1)[1]
        self.assertLess(support.index('reader.scope == selection.ownerScope'), support.index('factory(selection.historyID)'))
        self.assertLess(support.index('reader.isAuthenticated, reader.isConfigured'), support.index('factory(selection.historyID)'))

    def test_queued_actions_capture_lifetime_before_task_and_before_invalidation(self):
        source = self.read('App/OwnedCouponReadSupport.swift')
        offer = source.split('func offerRead(', 1)[1].split('private func accept', 1)[0]
        self.assertLess(offer.index('presentation === permit'), offer.index('cancelPending()'))
        self.assertIn('let read = OwnedCouponReadLifetime(ownerScope: request.ownerScope)', offer)
        self.assertIn('self.presentation === permit', offer)
        self.assertLess(offer.index('presentedRequest == request'), offer.index('cancelPending()'))
        self.assertLess(offer.index('reader.scope == request.ownerScope'), offer.index('cancelPending()'))
        self.assertIn('self.offer === read', offer)
        for call in ['reader.ownedCoupons(keyword: keyword, lifetime: read)', 'reader.ownedCoupon(id: selection.historyID, lifetime: read)']:
            self.assertIn(call, offer)
        schedule = source.split('func schedule(', 1)[1].split('func refresh(', 1)[0]
        self.assertLess(schedule.index('offerRead('), schedule.index('Task {'))
        self.assertIn('permit.invalidate(); presentation = nil; presentedRequest = nil; cancelPending(); return true', source)

    def test_real_reader_rejects_owner_or_lifetime_before_unauthorized_callback(self):
        source = self.read('Core/AccountCollectionReading.swift').split('private func read<T>', 1)[1].split('/// Each saved-post', 1)[0]
        self.assertLess(source.index('try lifetime?.check()'), source.index('operation(service, session.token)'))
        self.assertLess(source.index('expected != captured'), source.index('operation(service, session.token)'))
        catch = source.split('} catch {', 1)[1]
        self.assertLess(catch.index('lifetime?.isActive != false'), catch.index('onUnauthorized(session)'))
        self.assertLess(catch.index('!Task.isCancelled'), catch.index('onUnauthorized(session)'))
        self.assertLess(catch.index('currentSession() == session, scope == captured'), catch.index('onUnauthorized(session)'))

    def test_code_owner_is_frozen_at_construction_and_offers_are_one_use(self):
        source = self.read('Core/CouponCodePresentation.swift')
        self.assertIn('selectedOwner = currentSession()', source)
        self.assertIn('guard selectedOwner == currentSession()', source)
        self.assertIn('guard selectedOwner == session', source)
        self.assertIn('actionOffer === permit', source)
        self.assertIn('permit.active = false; actionOffer = nil', source)
        self.assertIn('foregroundOffer === permit', source)
        self.assertIn('foregroundOffer?.active = false; foregroundOffer = nil; suspended = true', source)
        self.assertIn('guard !usesPresentationLifecycle, !disposed', source)

    def test_code_view_freezes_confirmation_retry_and_foreground_before_tasks(self):
        source = self.read('App/CouponCodeView.swift')
        for offer, action in [('offerConfirmation', 'confirmPresentation'), ('offerRetry', 'retry'), ('offerResume', 'resume')]:
            self.assertLess(source.index('model.' + offer + '('), source.index('Task { await model.' + action + '(permit: offer)'))
        self.assertIn('let appearance = viewPresentation', source)
        self.assertIn('let presentation = appearance.permit', source)
        self.assertIn('model.endPresentation(presentation: permit)', source)
        self.assertNotIn('model.endPresentation()', source)
        self.assertIn('foregroundTask?.cancel()', source)
        self.assertNotIn('Task { await model.confirmPresentation() }', source)

    def test_code_dispatch_checks_current_approval_cancellation_and_presentation(self):
        source = self.read('Core/CouponCodePresentation.swift')
        for method, call in [('refresh', 'service.issue('), ('poll', 'service.status(')]:
            part = source.split('private func ' + method + '(', 1)[1].split('\n    private func ', 1)[0]
            for guard in ['owns(expected)', '!Task.isCancelled', '!suspended', 'guard service.enabled']:
                self.assertLess(part.index(guard), part.index(call))
        current = source.split('private func current(', 1)[1].split('private func refresh(', 1)[0]
        self.assertIn('service.enabled', current)
        self.assertIn('!disposed', current)

    def test_real_reader_and_composition_regressions_are_authored(self):
        core = self.read('Tests/CoreTests/OwnedCouponReadLifetimeTests.swift')
        app = self.read('Tests/AppUnitTests/OwnedCouponCompositionTests.swift')
        self.assertIn('AccountCollectionSessionReader(service: AccountCollectionService(', core)
        self.assertIn('AccountCollectionSessionReader(service: AccountCollectionService(', app)
        for name in ['testQueuedOfferAfterCloseHasZeroTransportRequests', 'testOldOfferCannotBorrowReopenOrCancelNewRead',
                     'testCloseDuringRealReaderSuppressesLate401BeforeSessionCallback', 'testCurrentRealReader401StillCallsUnauthorizedAndShowsLogin',
                     'testRetainedCodeDestinationCannotInvokeFactoryAfterOwnerSwitch', 'testNewerKeywordReadSuppressesOld401AndAcceptsOnlyNewRows']:
            self.assertIn('func ' + name + '(', app)
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 8)
        self.assertEqual(len(re.findall(r'func test\w+\(', app)), 24)

    def test_code_lifecycle_regressions_and_normal_offline_journey_are_authored(self):
        core = self.read('Tests/CoreTests/CouponCodePermitTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 20)
        for name in ['testConfirmationQueuedThenClosedCannotIssue', 'testOldConfirmationCannotBorrowReopenedPresentation',
                     'testQueuedForegroundCannotUndoLaterBackground', 'testQueuedRetryCannotDispatchAfterApprovalRevocation']:
            self.assertIn('func ' + name + '(', core)
        ui = self.read('Tests/AppUITests/OwnedCouponCodeJourneyUITests.swift')
        for step in ['accountCollection.openCoupons', 'accountCollection.coupon.701', 'couponCode.open', 'couponCode.review', 'couponCode.qr']:
            self.assertIn('"' + step + '"', ui)
        self.assertIn('app.sheets.buttons["Cancel"].tap()', ui)
        self.assertGreaterEqual(ui.count('assertIssues(0)'), 5)
        self.assertGreaterEqual(ui.count('assertIssues(1)'), 3)
        self.assertNotIn('XCTSkip', ui)

    def test_no_mutation_or_production_approval_is_added_to_metadata_or_fixture(self):
        service = self.read('Core/AccountCollectionService.swift')
        self.assertNotIn('api/coupon/qr-token', service); self.assertNotIn('api/coupon/verification', service)
        source = self.read('App/OwnedCouponReadSupport.swift')
        for forbidden in ['ProductionApproval', 'HTTPTransport', 'UserDefaults', 'Keychain', 'api/coupon', 'redeem(']:
            self.assertNotIn(forbidden, source)
        fixture = self.read('App/AccountCollectionFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('guard reader.scenario == .codePresentation else { return nil }', fixture)
        self.assertIn('SYNTHETIC-NOT-REDEEMABLE', fixture)
        self.assertNotIn('https://', fixture); self.assertNotIn('URLSession', fixture)

    def test_close_callbacks_capture_appearance_and_scoped_model_identity(self):
        for name in ['App/AccountCollectionCouponsView.swift', 'App/AccountCollectionCouponDetailView.swift', 'App/CouponCodeView.swift']:
            source = self.read(name)
            self.assertIn('let appearance = viewPresentation', source)
            self.assertIn('appearance.end(model: model)', source)
            self.assertIn('if viewPresentation === appearance', source)
            self.assertNotIn('model.endPresentation()', source)
        for name in ['App/OwnedCouponReadSupport.swift', 'Core/CouponCodePresentation.swift']:
            end = self.read(name).split('func endPresentation(', 1)[1].split('\n    }', 1)[0]
            self.assertLess(end.index('presentation === permit'), end.index('return true'))
        source = self.read('App/CouponCodeView.swift')
        self.assertIn('appearance.actionTask = Task', source)
        self.assertIn('appearance.foregroundTask = Task', source)
        self.assertIn('if appearance.end(model: model) { review = false }', source)
        self.assertNotIn('@State private var actionTask', source)

    def test_closed_view_appearances_cannot_reopen_and_nil_first_body_is_covered(self):
        for name, cls in [('App/OwnedCouponReadSupport.swift', 'OwnedCouponReadViewPresentation'), ('App/CouponCodeView.swift', 'CouponCodeViewPresentation')]:
            source = self.read(name).split('final class ' + cls, 1)[1]
            self.assertIn('guard !isClosed else { return nil }', source)
            self.assertIn('isClosed = true', source)
            self.assertIn('model.endPresentation(presentation: permit)', source)
        app = self.read('Tests/AppUnitTests/OwnedCouponCompositionTests.swift')
        for name in ['testLateCloseOfPriorViewCannotCancelReopenedRealDetailRead',
                     'testCurrentViewCloseBeforeFirstRedrawRevokesQueuedReadAndCannotBeReused',
                     'testCodeViewLateCloseKeepsNewConsentAndTasksButCurrentCloseCancelsOwnTask']:
            self.assertIn('func ' + name + '(', app)
