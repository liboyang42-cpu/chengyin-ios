from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class MerchantClubAccessibleControls(unittest.TestCase):
    def test_unavailable_title_does_not_override_retry_identifier(self):
        s=(ROOT/'App/ClubHomeView.swift').read_text()
        self.assertIn('Label("club.locality.unavailable", systemImage: "exclamationmark.triangle")\n                        .accessibilityIdentifier("club.home.locality.unavailable")',s)
        self.assertNotIn('}.accessibilityIdentifier("club.home.locality.unavailable")',s)
        self.assertIn('.accessibilityIdentifier("club.home.locality.retry")',s)
    def test_header_controls_use_exact_unique_visible_enabled_native_query(self):
        s=(ROOT/'Tests/AppUITests/MerchantClubDiscoveryFlowTests.swift').read_text()
        for ident in ['toggleLocalityRole','switchMerchant','locality.release','locality.fail']:
            self.assertIn('tapFixedFixtureControl("club.fixture.'+ident+'", app: app)',s)
        for text in ['allowed.contains(identifier)','query.count == 1','button.isEnabled && button.isHittable','app.frame.contains(frame)',
                     'frame.minY >= notice.frame.maxY','frame.maxY <= bar.frame.minY','query.element(boundBy: 0).tap()']:
            self.assertIn(text,s)
    def test_old_401_player_rows_and_retry_semantics_remain_asserted(self):
        s=(ROOT/'Tests/AppUITests/MerchantClubDiscoveryFlowTests.swift').read_text()
        for text in ['pending(2, app: app)','pending(1, app: app)','pending(0, app: app)',
                     'XCTAssertFalse(app.buttons["club.home.locality.retry"].exists)',
                     'element("club.home.owned.81", app: app)','element("club.home.joined.82", app: app)',
                     'XCTAssertFalse(element("club.home.nearby.83", app: app).exists)',
                     'XCTAssertFalse(element("club.home.nearby.84", app: app).exists)',
                     'tap("club.home.locality.retry", app: app, towardTop: true)']:
            self.assertIn(text,s)

        self.assertEqual(s.count('tap("club.home.locality.retry", app: app, towardTop: true)'), 2)
