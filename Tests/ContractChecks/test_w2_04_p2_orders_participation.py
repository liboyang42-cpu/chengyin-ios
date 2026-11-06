"""Source contracts only: not compiled Swift or UI execution."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class W204P2OrdersParticipationChecks(unittest.TestCase):
    def setUp(self):
        self.env = read('App/RootTabSwitchEnvironment.swift')
        self.orders = read('App/ProfileOrdersView.swift')
        self.journey = read('App/PlayerJourneyViews.swift')

    def test_root_tab_switch_default_is_inert(self):
        self.assertIn('static let defaultValue = RootTabSwitch.unavailable', self.env)
        self.assertIn('private init() { isAvailable = false; select = { _ in } }', self.env)
        self.assertEqual(read('App/QuestifyApp.swift').count('.environment(\\.rootTabSwitch, RootTabSwitch { selectedTab = $0 })'), 1)

    def test_discover_cta_prefers_closure_then_root_switch_to_home(self):
        self.assertIn('@Environment(\\.rootTabSwitch) private var rootTabSwitch', self.orders)
        empty = self.orders.split('if let discoverRoutes {', 1)[1].split('TimelineView(', 1)[0]
        self.assertIn('} else if rootTabSwitch.isAvailable {', empty)
        self.assertIn('rootTabSwitch(.home)', empty)
        self.assertEqual(self.orders.count('.accessibilityIdentifier("profile.orders.discover")'), 2)

    def test_order_detail_support_is_read_only_navigation(self):
        detail = self.orders.split('struct ProfileOrderDetailView', 1)[1].split('struct ProfileOrderTicketScheduleRows', 1)[0]
        self.assertIn('NavigationLink { ParticipationSupportView() }', detail)
        self.assertIn('"profile.orderP2.supportSection.free" : "profile.orderP2.supportSection"', detail)
        self.assertIn('.accessibilityIdentifier("profile.order.detail.support")', detail)
        support = detail.split('profile.orderP2.supportSection', 1)[1].split('profile.readOnly', 1)[0]
        for forbidden in ['Task {', 'transport.send', '.submit(', 'cancel-refund']:
            self.assertNotIn(forbidden, support)

    def test_start_falls_back_to_ticket_wallet_route(self):
        self.assertIn('verification, support, ticketWallet }', self.journey)
        self.assertIn('Button("playerJourney.start", systemImage: "ticket") { open(.ticketWallet) }', self.journey)
        self.assertIn('TicketWalletView(reader: session.ticketWalletReader, orderLifecycleCoordinator: session.orderLifecycleCoordinator)', self.journey)
        self.assertLess(self.journey.index('if let target = detail.record.playEntry {'), self.journey.index('open(.ticketWallet)'))

    def test_row_cover_uses_https_only_artwork_or_placeholder(self):
        row = self.journey.split('private struct ParticipationRow', 1)[1].split('private struct ParticipationCoverPlaceholder', 1)[0]
        self.assertIn('if let url = QuestifyCardArtwork.safeURL(record.cover) {', row)
        self.assertIn('ParticipationCoverPlaceholder()', row)
        self.assertIn('parts.scheme == "https"', read('App/QuestifyMotionComponents.swift'))

    def test_fragment_keys_bilingual_and_merged(self):
        fragment = json.loads(read('Resources/W204P2OrdersLocalizations.fragment.json'))['strings']
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        for key, entry in fragment.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            self.assertEqual(catalog[key], entry)
        self.assertEqual(fragment['profile.orderP2.contactSupport']['localizations']['zh-Hans']['stringUnit']['value'], '联系客服')


if __name__ == '__main__':
    unittest.main()
