"""Offline structure/localization guard only; Apple tests validate Swift types and UI."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class AccountCollectionStructureTests(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_exact_read_routes_and_no_mutations(self):
        service = self.text('Core/AccountCollectionService.swift')
        paths = set(re.findall(r'post\("(api/[^\"]+)"', service))
        self.assertEqual(paths, {'api/topic/like_list', 'api/coupon/myrecvlist'})
        for route in ['api/topic/like"', 'api/coupon/qr-token', 'api/coupon/verification',
                      'api/coupon/publish', 'api/coupon/stop', 'api/user/address/action']:
            self.assertNotIn(route, service)
        self.assertIn('try await coupons(token: token)', service)
        self.assertIn('matches.count == 1', service)

    def test_credentials_and_coupon_codes_are_not_display_models(self):
        contracts = self.text('Core/AccountCollectionContracts.swift')
        for declaration in ['let couponCode', 'let qrcodeUrl', 'let token', 'case couponCode', 'case qrcodeUrl']:
            self.assertNotIn(declaration, contracts)
        all_swift = '\n'.join(path.read_text() for folder in ['Core', 'App'] for path in (ROOT / folder).glob('AccountCollection*.swift'))
        for storage in ['UserDefaults', 'write(to:', 'FileManager', 'URLSession.shared', 'print(']:
            self.assertNotIn(storage, all_swift)

    def test_distinct_scoped_models_and_shared_photo_card(self):
        reading = self.text('Core/AccountCollectionReading.swift')
        self.assertIn('currentSession() == session, scope == captured', reading)
        self.assertIn('loadedScope == scope ? value : nil', reading)
        self.assertIn('loadedScope == scope ? pagination.rows : []', reading)
        favorite = self.text('App/AccountCollectionFavoritesView.swift')
        self.assertIn('QuestifyImageEntityCard(', favorite)
        self.assertIn('onOpenTopic(topic.id)', favorite)
        self.assertNotIn('.stroke', favorite)
        self.assertNotIn('minimumAmount', favorite)

    def test_catalog_is_complete_for_literal_and_computed_keys(self):
        rows = json.loads(self.text('docs/account-collection-localizations.json'))
        keys = [row['key'] for row in rows]
        self.assertEqual(len(keys), len(set(keys)))
        for row in rows:
            self.assertTrue(row['en']); self.assertTrue(row['zh-Hans'])
        sources = '\n'.join(path.read_text() for folder in ['Core', 'App'] for path in (ROOT / folder).glob('AccountCollection*.swift'))
        # Identifier-only strings are not localization lookups.
        literal = set(re.findall(r'(?:Text|Label|ProgressView|Button|Section|Picker|ContentUnavailableView|appNavigationTitle)\("(accountCollection\.[^"\\]+)"', sources))
        literal |= {'accountCollection.' + suffix for suffix in [
            'favorites.untitled', 'favorites.place', 'coupon.untitled', 'coupon.validFrom',
            'coupon.validUntil', 'coupon.received', 'coupon.used', 'signInRequired',
            'notConfigured', 'unavailable', 'network', 'failed']}
        literal = {key for key in literal if not key.endswith('.')}
        for stem, values in [('coupon.status.', ['unused','used','expired','invalid','unknown']),
                             ('coupons.filter.', ['all','unused','used','expired'])]:
            literal |= {'accountCollection.' + stem + value for value in values}
        self.assertTrue(literal <= set(keys), sorted(literal - set(keys)))
        self.assertNotRegex(sources, r'LocalizedStringKey\("[^"\n]*\\\(')

    def test_no_duplicate_address_domain_or_network_fixture(self):
        service = self.text('Core/AccountCollectionService.swift')
        self.assertNotIn('api/user/address', service)
        fixture = self.text('Core/AccountCollectionSyntheticFixtures.swift') + self.text('App/AccountCollectionFixtureSupport.swift')
        self.assertNotIn('https://', fixture)
        self.assertNotIn('URLSession', fixture)
        self.assertNotIn('mobilePhone', fixture)
        self.assertIn('#if DEBUG', fixture)


if __name__ == '__main__':
    unittest.main()
