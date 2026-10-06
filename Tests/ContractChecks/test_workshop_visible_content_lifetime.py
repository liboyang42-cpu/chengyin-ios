"""Source ordering guard only; the existing hosted XCTest still needs Apple execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WorkshopVisibleContentLifetimeChecks(unittest.TestCase):
    def test_real_visibility_callbacks_are_inside_keyed_content_and_navigation_host_stays_outside(self):
        library = (ROOT / 'App/WorkshopOwnedLibraryView.swift').read_text()
        package = (ROOT / 'App/WorkshopOwnedPackageView.swift').read_text()
        for source, screen in [(library.split('@MainActor struct WorkshopOwnedLibraryView:')[1].split('@MainActor struct WorkshopOwnedDetailView:')[0], 'list'),
                               (library.split('@MainActor struct WorkshopOwnedDetailView:')[1].split('private struct WorkshopOwnedScopeSection:')[0], 'detail'),
                               (package.split('@MainActor struct WorkshopOwnedPackageView:')[1].split('private struct PackageValueRow:')[0], 'package')]:
            with self.subTest(screen=screen):
                self.assertEqual(source.count('.id(ObjectIdentifier(displayed))'), 1)
                self.assertLess(source.index('.onAppear {'), source.index('.id(ObjectIdentifier(displayed))'))
                self.assertLess(source.index('.onDisappear { navigation.' + screen + 'ViewDisappeared(displayed) }'), source.index('.id(ObjectIdentifier(displayed))'))
                if screen != 'package':
                    self.assertLess(source.index('.id(ObjectIdentifier(displayed))'), source.index('.navigationDestination('))
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
