"""C3 anniversary -> current route -> return source contracts.

Static only: these checks do not compile Swift or run the app. They pin the
entry-to-result chain across the three Roam views owned by this lane; the
production SessionRoam host injection is deliberately NOT applied here.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class RoamAnniversaryNavigationContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = read('Core/RoamAnniversaryNavigation.swift')
        cls.views = read('App/RoamPassportToolsViews.swift')
        cls.home = read('App/RoamHomeTabsView.swift')
        cls.hub = read('App/RoamExperienceHubView.swift')

    def test_both_production_entries_forward_a_destination(self):
        self.assertIn('RoamPassportToolsSection(reader: toolsReader, routeDestination: anniversaryRouteDestination)', self.home)
        self.assertIn('var anniversaryRouteDestination: ((String) -> AnyView)? = nil', self.home)
        self.assertIn('RoamPassportToolsSection(reader: toolsReader, routeDestination: anniversaryRouteDestination, privateTools: privateToolsReader)', self.hub)
        self.assertIn('var anniversaryRouteDestination: ((String) -> AnyView)? = nil', self.hub)
        self.assertIn('anniversaryRouteDestination: anniversaryRouteDestination).id(reader.identity)', self.hub)

    def test_cards_resolve_real_topic_id_and_report_unavailable(self):
        self.assertIn('RoamAnniversaryRouteAvailability.resolve(memory: item, hasDestination: routeDestination != nil)', self.views)
        self.assertIn('RoamAnniversaryRouteHost(presentation: navigation.openedPresentation, owner: reader?.identity', self.views)
        self.assertIn('navigation.open(target, memory: item, currentRows: rows, owner: reader?.identity)', self.views)
        self.assertIn('destination(presentation.target.topicID)', self.views)
        self.assertIn('"topic.unavailable"', self.views)
        self.assertIn('roam.tools.anniversary.routeUnavailable', self.views)
        # Invalid ids are value-checked in Core, never derived from the memory id.
        self.assertIn('String(value) == text', self.core)
        self.assertIn('case invalidTopicID', self.core)
        self.assertIn('case noDestination', self.core)

    def test_return_keeps_date_and_refreshes_once_and_identity_clears(self):
        # The true pop is the anniversary screen reappearing, carrying the lease.
        self.assertIn('navigation.completeReturn(presentation: lease, owner: reader?.identity)', self.views)
        self.assertIn('if let lease = navigation.openedPresentation,', self.views)
        self.assertIn('navigation.bind(to: newOwner)', self.views)
        self.assertIn('rows = []; page = nil; error = nil; selected = nil', self.views)
        self.assertIn('navigation.invalidate()', self.views)
        # Existing late-result fencing stays: generation ticket + owner equality.
        self.assertIn('guard ticket == generation, owner == reader.identity else { return }', self.views)

    def test_return_callbacks_carry_the_lease_and_disappear_is_not_return(self):
        # Every completion path is lease-checked in Core; owner-only callbacks are gone.
        self.assertIn('public struct RoamAnniversaryRoutePresentation', self.core)
        self.assertIn('openedPresentation == presentation', self.core)
        self.assertIn('func completeReturn(presentation: RoamAnniversaryRoutePresentation?,', self.core)
        self.assertIn('func noteCovered(_ presentation: RoamAnniversaryRoutePresentation?,', self.core)
        for gone in ('markReturned', 'consumeReturnRefresh', 'returnRefreshPending'):
            self.assertNotIn(gone, self.core)
            self.assertNotIn(gone, self.views)
        # RouteHost disappearance only notes a cover (child drill-down), never returns.
        host = self.views.split('struct RoamAnniversaryRouteHost', 1)[1]
        self.assertIn('.onDisappear { navigation.noteCovered(presentation, owner: owner) }', host)
        self.assertNotIn('completeReturn', host)
        self.assertNotIn('onReturn', host)

    def test_no_play_start_or_new_api_or_permission(self):
        for source in (self.core, self.views, self.home, self.hub):
            for banned in ('startRoam', 'continueRoam', 'makeRoamLiveSessionController',
                           'requestWhenInUseAuthorization', 'CLLocationManager'):
                self.assertNotIn(banned, source)
        self.assertNotIn('api/', self.core)


if __name__ == '__main__':
    unittest.main()
