"""Source ordering guard only; the existing hosted XCTest still needs Apple execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WorkshopVisibleContentLifetimeChecks(unittest.TestCase):
    # Preserve the historical method ID. Permit retirement never changes view identity;
    # actual201 additionally requires a captured box per real navigation/visible visit.
    def test_real_visibility_callbacks_are_inside_keyed_content_and_navigation_host_stays_outside(self):
        library = (ROOT / 'App/WorkshopOwnedLibraryView.swift').read_text()
        package = (ROOT / 'App/WorkshopOwnedPackageView.swift').read_text()
        for source, screen in [(library.split('@MainActor struct WorkshopOwnedLibraryView:')[1].split('@MainActor struct WorkshopOwnedDetailView:')[0], 'list'),
                               (library.split('@MainActor struct WorkshopOwnedDetailView:')[1].split('private struct WorkshopOwnedScopeSection:')[0], 'detail'),
                               (package.split('@MainActor struct WorkshopOwnedPackageView:')[1].split('private struct PackageValueRow:')[0], 'package')]:
            with self.subTest(screen=screen):
                self.assertNotIn('.id(ObjectIdentifier(displayed))', source)
                if screen == 'list':
                    self.assertIn('.onAppear { routeVisibility.appear(); navigation.scheduleList(navigation.listViewAppeared(displayed)) }', source)
                elif screen == 'detail':
                    self.assertIn('guard navigation.isCurrentDetailVisit(routeID: routeID, visitID: visitID) else { return }', source)
                    self.assertIn('routeVisibility.appear(); navigation.scheduleDetail(navigation.detailViewAppeared(appearing.appearance, claimId: claimId), claimId: claimId)', source)
                else:
                    self.assertIn('guard navigation.isCurrentPackageVisit(route) else { return }', source)
                    self.assertIn('navigation.schedulePackage(navigation.packageViewAppeared(appearing.appearance, claimId: claimId), claimId: claimId)', source)
                if screen == 'list':
                    self.assertIn('.onDisappear { routeVisibility.disappear(); navigation.listViewDisappeared(displayed) }', source)
                else:
                    self.assertIn('guard let departing = callbacks.disappear() else { return }', source)
                    self.assertIn('navigation.' + screen + 'ViewDisappeared(departing.appearance)', source)
                if screen != 'package':
                    self.assertLess(source.index('.onDisappear {'), source.index('.navigationDestination('))
                if screen == 'list':
                    self.assertIn('let displayed = navigation.listAppearance', source)
                else:
                    self.assertIn('@State private var mount: WorkshopOwnedMountedAppearance', source)
                    self.assertIn('_mount = State(initialValue: WorkshopOwnedMountedAppearance(appearance: appearance))', source)
                    self.assertNotIn('let displayed = navigation.' + screen + 'Appearance', source)

        self.assertIn('WorkshopOwnedLibraryView(browser: browser).id(browser.identity)', library)
        self.assertIn('routeID: selection.routeID, visitID: navigation.detailVisitID, appearance: navigation.detailAppearance)', library)
        self.assertIn('.id(navigation.detailVisitID)', library)
        self.assertIn('route: route, appearance: navigation.packageAppearance).id(route.id)', library)
        self.assertNotIn('.id(selection.id)', library)

    def test_actual_hosted_back_assertions_and_original_wait_bound_remain(self):
        source = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        self.assertIn('for _ in 0..<100', source)
        self.assertIn('Task.sleep(nanoseconds: 20_000_000)', source)
        self.assertIn('f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil', source)
        self.assertIn('XCTAssertFalse(f.navigation.detailPermit === detailPermit)', source)
        self.assertIn('XCTAssertFalse(f.navigation.listPermit === listPermit)', source)
        self.assertIn('XCTAssertEqual(f.state.unauthorized,0)', source)
        self.assertIn('testBackBeforeOldDisappearanceUsesNewRouteBoxAndOldCallbacksCannotClearIt', source)
        self.assertIn('testHostedListManualRetirementDoesNotRemountOrReissuePermit', source)
        self.assertIn('testHostedDetailManualRetirementDoesNotRemountOrReissuePermit', source)
        self.assertIn('XCTAssertNil(inactive.permit); XCTAssertNil(f.navigation.detailPermit)', source)
        self.assertIn('XCTAssertNil(f.navigation.offerDetail(oldPermit, claimId: "synthetic-claim")); XCTAssertNil(f.browser.detail)', source)
        self.assertIn('real Back after manual detail retirement restores list', source)
        self.assertIn('testHostedPackageReopenAndManualRetirementKeepPermitsScopedWithoutRemount', source)
        self.assertIn('second hosted package ready with fresh permit', source)
        self.assertIn('XCTAssertTrue(f.navigation.packagePermit === secondPermit); XCTAssertTrue(secondPermit.isLive)', source)
        self.assertIn('XCTAssertNil(inactive.permit); XCTAssertNil(f.navigation.packagePermit)', source)
        self.assertIn('second package Back after retirement restores detail', source)
        self.assertIn('XCTAssertNil(inactive.permit); XCTAssertNil(f.navigation.listPermit)', source)

        for token in ['same hosted detail reopens with fresh permit',
                      'XCTAssertTrue(f.navigation.listPermit === returnedList); XCTAssertTrue(returnedList.isLive)',
                      'XCTAssertTrue(f.navigation.detailPermit === reopenedDetail); XCTAssertTrue(reopenedDetail.isLive)',
                      'XCTAssertTrue(f.navigation.listAppearance === inactiveBox)',
                      'XCTAssertNil(f.navigation.listPermit); XCTAssertEqual(f.recorder.paths.count,calls)',
                      'XCTAssertFalse(inactiveBox === retiringBox); XCTAssertFalse(retiringPermit.isLive)']:
            self.assertIn(token, source)

    def test_back_diagnostics_are_debug_only_bounded_and_opted_in_by_two_existing_hosts(self):
        for family, limit in [('Owned', 48), ('Purchased', 24)]:
            source = (ROOT / ('App/Workshop' + family + 'NavigationState.swift')).read_text()
            self.assertIn('syntheticTraceCount < ' + str(limit), source)
            self.assertIn('@ObservationIgnored var syntheticTrace: ((SyntheticSnapshot) -> Void)? = nil', source)
            for token in ['displayedAppeared', 'displayedClosed', 'currentAppeared', 'currentClosed', 'eligible',
                          'selectionChanged', 'detailAppearReturned', 'detailDisappearReturned']:
                self.assertIn(token, source)
            self.assertIn('var syntheticAppeared: Bool { appeared }', source)
            self.assertIn('var syntheticClosed: Bool { closed }', source)
            self.assertIn('guard !closed else { return nil }', source)
            self.assertIn('closed = true; retire(permit)', source)
        owned = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        purchased = (ROOT / 'Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift').read_text()
        self.assertEqual(owned.count('.syntheticTrace = '), 1)
        self.assertEqual(purchased.count('.syntheticTrace = '), 1)
        self.assertIn('WORKSHOP_SYNTHETIC_OWNED', owned)
        self.assertIn('WORKSHOP_SYNTHETIC_PURCHASED', purchased)
        self.assertIn('for _ in 0..<100', purchased)
        self.assertIn('Task.sleep(nanoseconds:20_000_000)', purchased)
        self.assertIn('navigation.listPermit != nil && browser.phase == .ready', purchased)

    def test_route_return_supplements_only_real_visible_false_to_true_transition(self):
        owned = (ROOT / 'App/WorkshopOwnedLibraryView.swift').read_text()
        purchased = (ROOT / 'App/WorkshopPurchasedLibraryView.swift').read_text()
        self.assertIn('guard isVisible, !wasEligible, isEligible else { return }', owned)
        self.assertIn('mutating func appear() { isVisible = true }', owned)
        self.assertIn('mutating func disappear() { isVisible = false }', owned)
        for source, count in [(owned, 2), (purchased, 1)]:
            self.assertEqual(source.count('@State private var routeVisibility = WorkshopVisibleRouteReturn()'), count)
            self.assertEqual(source.count('routeVisibility.appear();'), count)
            self.assertEqual(source.count('routeVisibility.disappear()'), count)
            self.assertEqual(source.count('routeVisibility.returned(wasEligible: wasEligible, isEligible: isEligible)'), count)
            self.assertEqual(source.count('displayed.permit == nil else { return }'), count)
            self.assertNotIn('.onChange(of: ObjectIdentifier(', source)
            self.assertIn('.onChange(of: navigation.selection == nil)', source)
        self.assertIn('.onChange(of: navigation.selection?.id == claimId && !navigation.showsPackage)', owned)
        owned_tests = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        purchased_tests = (ROOT / 'Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift').read_text()
        for token in ['testRouteReturnRequiresRealVisibilityAndFalseToTrueEligibility',
                      'testVisibleRouteBackWithoutAnotherAppearanceIssuesFreshPermitsAndRejectsOldCallbacks',
                      'manual retirement cannot resume', 'hidden list cannot resume']:
            self.assertIn(token, owned_tests)
        for token in ['testVisiblePurchasedBackWithoutAnotherAppearanceResumesOnlyFreshCurrentList',
                      'manual retirement cannot resume', 'hidden purchased list cannot resume']:
            self.assertIn(token, purchased_tests)

    def test_route_occurrence_bindings_are_captured_and_manual_retirement_cannot_remount(self):
        source = (ROOT / 'App/WorkshopOwnedNavigationState.swift').read_text()
        for token in ['let routeID = UUID()', 'struct PackageRoute: Hashable, Identifiable',
                      'let expected = selection', 'self.selection == expected',
                      'let expected = packageRoute', 'self.isCurrentPackageVisit(expected)',
                      'self.isCurrentDetailVisit(routeID: detailRouteID, visitID: visitID)',
                      'let expected, self.selection == expected else { return }',
                      'packageRoute = .init(id: UUID(), detailRouteID: selection.routeID, claimId: selection.id)']:
            self.assertIn(token, source)
        for scope in ['list', 'detail', 'package']:
            body = source.split('func ' + scope + 'ViewDisappeared(', 1)[1].split('    }', 1)[0]
            self.assertNotIn('detailVisitID =', body)
            self.assertNotIn('packageRoute =', body)
        tests = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        for token in ['testSameClaimReopenHasDistinctRouteAndOldSelectionBindingCannotReadOrCloseIt',
                      'testPackageReturnCreatesDetailVisitAndOldPackageBindingsCannotReadOrCloseReopen',
                      'XCTAssertNotEqual(first.routeID, second.routeID)',
                      'XCTAssertNotEqual(returnedVisit, firstVisit)',
                      'XCTAssertNil(firstBinding.wrappedValue); XCTAssertNil(emptyBinding.wrappedValue)',
                      'XCTAssertEqual(f.navigation.packageRoute, secondRoute)']:
            self.assertIn(token, tests)

    def test_real_retained_hide_is_the_only_box_replacement_boundary(self):
        source = (ROOT / 'App/WorkshopOwnedNavigationState.swift').read_text()
        helper = source.split('final class WorkshopOwnedMountedAppearance', 1)[1]
        for token in ['let id: UUID', 'let appearance: WorkshopOwnedViewAppearance',
                      'if didDisappear {', 'cycle = .init(id: UUID(), appearance: current)',
                      'guard isVisible, cycle.id == captured.id, cycle.appearance === captured.appearance',
                      'isVisible = false; didDisappear = true']:
            self.assertIn(token, helper)
        for path in ['App/WorkshopOwnedLibraryView.swift', 'App/WorkshopOwnedPackageView.swift']:
            body = (ROOT / path).read_text()
            self.assertIn('let callbacks = mount.callbacks()', body)
            self.assertIn('let displayed = mount.cycle.appearance', body)
            self.assertIn('guard let departing = callbacks.disappear() else { return }', body)
        tests = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        for token in ['testMountedCycleRejectsOldDisappearanceAndOnlyRealHideAllowsFreshBox',
                      'testHostedRetainedTabReturnsToSameDetailAndPackageVisitWithFreshPermits',
                      'tabs.selectedIndex = 1', 'tabs.selectedIndex = 0',
                      'XCTAssertFalse(mount.disappear(firstCycle))',
                      'XCTAssertEqual(repeated.id, firstCycle.id)']:
            self.assertIn(token, tests)

    def test_first_frame_callbacks_pair_actual_cycle_without_old_pair_adoption(self):
        source = (ROOT / 'App/WorkshopOwnedNavigationState.swift').read_text()
        pair = source.split('final class Callbacks', 1)[1].split('func callbacks()', 1)[0]
        for token in ['owner.cycle.id == captured.id', 'owner.cycle.appearance === captured.appearance',
                      'let appearing = owner.appear(current: current)', 'captured = appearing',
                      'owner.disappear(captured)', 'return captured']:
            self.assertIn(token, pair)
        self.assertLess(pair.index('owner.cycle.id == captured.id'), pair.index('owner.appear(current: current)'))
        tests = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        for token in ['testSameRenderedCallbacksRetireReturnedFirstFrameAndOldPairCannotAdoptIt',
                      'XCTAssertNil(oldPair.appear(current: f.navigation.detailAppearance))',
                      'XCTAssertNil(oldPair.disappear())',
                      'XCTAssertEqual(immediateDeparture.id, returned.id)']:
            self.assertIn(token, tests)
