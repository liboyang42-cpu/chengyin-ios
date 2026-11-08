"""Source integration checks; these do not claim Apple compilation or UI execution."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WalletPointsLedgerContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/WalletCommerceViews.swift').read_text()
        self.view = self.source.split('@MainActor struct WalletLedgerView: View {', 1)[1].split('@MainActor struct WalletIncomeView: View {', 1)[0]
        self.core = (ROOT / 'Core/WalletPointsLedgerPresentation.swift').read_text()

    def test_only_owned_view_segment_changed(self):
        before, tail = self.source.split('@MainActor struct WalletLedgerView: View {', 1)
        after = '@MainActor struct WalletIncomeView: View {' + tail.split('@MainActor struct WalletIncomeView: View {', 1)[1]
        self.assertEqual(hashlib.sha256(before.encode()).hexdigest(), '5482b6f1909c03c28b15a83ad2489a6f7da1a8a3dcbca54d4eff1c20a7c3f64a')
        self.assertEqual(hashlib.sha256(after.encode()).hexdigest(), '7543e4b594cf8287d1b8fe2f677855fd036b22e704225553c17de1b288da92a3')

    def test_points_facts_are_per_row_and_unknowns_explicit(self):
        self.assertNotIn('rows.first', self.view)
        self.assertNotIn('wallet.pointsBalance', self.view)
        for value in ['WalletPointsLedgerEntry(row: row)', 'format.points(entry.afterPoints)',
                      'entry.recordedTime', 'entry.signedChange', 'entry.reason',
                      'pointsLedger.reasonUnknown', 'pointsLedger.timeUnknown', 'pointsLedger.afterPoints']:
            self.assertIn(value, self.view)
        entry = self.core.split('public struct WalletPointsLedgerEntry', 1)[1].split('/// Presentation lifetime', 1)[0]
        self.assertNotIn('changeBalance', entry)
        self.assertNotIn('afterBalance', entry)
        self.assertNotIn('assetDirection', entry)

    def test_filter_applies_to_loaded_rows_and_unknown_direction_is_reachable(self):
        self.assertIn('snapshot.rows.filter', self.view)
        self.assertIn('rowDirection($0).rawValue == direction', self.view)
        self.assertIn('Text("wallet.direction.unknown").tag("unknown")', self.view)
        self.assertIn('pointsLedger.filterEmpty', self.view)
        self.assertIn('snapshot.hasMore', self.view)
        self.assertNotIn('filtered.count', self.core)
        self.assertNotIn('changeType:', self.core)

    def test_masks_errors_rows_and_controls_before_task_and_retires_on_disappear(self):
        self.assertIn('model.snapshot(for: owner)', self.view)
        self.assertIn('.task(id: owner)', self.view)
        self.assertIn('.onDisappear { model.cancel() }', self.view)
        self.assertIn('.refreshable { await load(refresh: true) }', self.view)
        self.assertIn('requiresLogin: snapshot.failure == .login', self.view)
        self.assertIn('unavailable: snapshot.failure == .unavailable', self.view)
        self.assertIn('snapshot.failure == nil && snapshot.loaded && snapshot.hasMore', self.view)

    def test_existing_reader_and_nonpaged_asset_contract_are_preserved(self):
        self.assertIn('reader.read { try await $0.ledger(kind, page: pageNumber, token: $1) }', self.core)
        for path, digest in {
            'Core/WalletCommerceService.swift': '58ee2f3bbb849d54d1c7eb9f03470bdc6c33fb2bf93baa1e9d0ce5494732e0ab',
            'Core/WalletCommerceSafety.swift': '66188645f55d549b3833ffba560f1256c47377f2936e64d32c12c7dc894ab6ed',
        }.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)
        self.assertIn('value.assets = true', (ROOT / 'App/SessionWalletCommerceView.swift').read_text())
        self.assertIn('NavigationLink("wallet.pointsLedger") { WalletLedgerView(reader: reader, kind: .assetPoints) }', self.source)
        for forbidden in ['HTTPTransport', 'URLRequest', 'execute(', 'checkout(', 'WalletCommerceDormantAdapter']:
            self.assertNotIn(forbidden, self.core)

    def test_catalog_is_dedicated_and_complete(self):
        catalog = json.loads((ROOT / 'Resources/WalletPointsLedger.xcstrings').read_text())
        expected = {'pointsLedger.rowFacts', 'pointsLedger.filterEmpty', 'pointsLedger.reasonUnknown',
                    'pointsLedger.afterPoints', 'pointsLedger.timeUnknown'}
        self.assertEqual(set(catalog['strings']), expected)
        for key, item in catalog['strings'].items():
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})
            self.assertIn('"' + key + '", tableName: "WalletPointsLedger"', self.view)
            for translated in item['localizations'].values():
                self.assertTrue(translated['stringUnit']['value'])


if __name__ == '__main__':
    unittest.main()
