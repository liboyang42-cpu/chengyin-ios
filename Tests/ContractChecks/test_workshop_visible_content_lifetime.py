"""Source ordering guard only; the existing hosted XCTest still needs Apple execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WorkshopVisibleContentLifetimeChecks(unittest.TestCase):
    # Preserve the historical method ID; assertions below enforce the repaired outer lifetime.
    def test_real_visibility_callbacks_are_inside_keyed_content_and_navigation_host_stays_outside(self):
        library = (ROOT / 'App/WorkshopOwnedLibraryView.swift').read_text()
        package = (ROOT / 'App/WorkshopOwnedPackageView.swift').read_text()
        for source, screen in [(library.split('@MainActor struct WorkshopOwnedLibraryView:')[1].split('@MainActor struct WorkshopOwnedDetailView:')[0], 'list'),
                               (library.split('@MainActor struct WorkshopOwnedDetailView:')[1].split('private struct WorkshopOwnedScopeSection:')[0], 'detail'),
                               (package.split('@MainActor struct WorkshopOwnedPackageView:')[1].split('private struct PackageValueRow:')[0], 'package')]:
            with self.subTest(screen=screen):
                self.assertEqual(source.count('.id(ObjectIdentifier(displayed))'), 1)
                self.assertLess(source.index('.id(ObjectIdentifier(displayed))'), source.index('.onAppear {'))
                self.assertLess(source.index('.id(ObjectIdentifier(displayed))'), source.index('.onDisappear { ' + ('routeVisibility.disappear(); ' if screen != 'package' else '') + 'navigation.' + screen + 'ViewDisappeared(displayed) }'))
                if screen != 'package':
                    self.assertLess(source.index('.onDisappear {'), source.index('.navigationDestination('))
                self.assertIn('let displayed = navigation.' + screen + 'Appearance', source)

    def test_actual_hosted_back_assertions_and_original_wait_bound_remain(self):
        source = (ROOT / 'Tests/AppUnitTests/WorkshopOwnedNavigationPresentationTests.swift').read_text()
        self.assertIn('for _ in 0..<100', source)
        self.assertIn('Task.sleep(nanoseconds: 20_000_000)', source)
        self.assertIn('f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil', source)
        self.assertIn('XCTAssertFalse(f.navigation.detailPermit === detailPermit)', source)
        self.assertIn('XCTAssertFalse(f.navigation.listPermit === listPermit)', source)
        self.assertIn('XCTAssertEqual(f.state.unauthorized,0)', source)
        self.assertIn('testBackBeforeOldDisappearanceUsesNewRouteBoxAndOldCallbacksCannotClearIt', source)

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
            self.assertEqual(source.count('routeVisibility.disappear();'), count)
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
