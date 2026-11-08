"""Entry recovery integration; source assertions do not establish Apple runtime behavior."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WalletAssetsEntryRecoveryContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/WalletCommerceViews.swift').read_text()
        self.view = self.source.split('@MainActor struct WalletAssetsView: View {', 1)[1].split('@MainActor private final class WalletPagerScreen:', 1)[0]
        self.core = (ROOT / 'Core/WalletAssetsReadPresentation.swift').read_text()

    def test_previously_delivered_ledger_segment_remains_exact(self):
        begin = self.source.index('@MainActor struct WalletLedgerView: View {')
        end = self.source.index('@MainActor struct WalletIncomeView: View {', begin)
        self.assertEqual(hashlib.sha256(self.source[begin:end].encode()).hexdigest(), 'df559d0d7f1aa720fb365110d03c3277668b94a0e576477b024e4480bc885977')

    def test_money_and_points_keep_their_existing_routes_and_meanings(self):
        for route in ['NavigationLink("wallet.balanceLedger") { WalletLedgerView(reader: reader, kind: .balance) }',
                      'NavigationLink("wallet.pointsLedger") { WalletLedgerView(reader: reader, kind: .assetPoints) }']:
            self.assertIn(route, self.view)
        self.assertIn('try await reader.read { try await $0.stages(token: $1) }', self.core)
        self.assertNotIn('pointBalance', self.core)
        self.assertNotIn('afterPoints', self.core)
        self.assertNotIn('WalletAmount(0)', self.core)
        self.assertNotIn('XP', self.view)
        self.assertIn('!value.amountsKnown', self.view)
        self.assertIn('format.amount(value.withdrawable, currency: value.currency)', self.view)

    def test_error_loading_and_data_are_all_from_current_owner_snapshot(self):
        self.assertIn('funds.snapshot(for: owner)', self.view)
        self.assertIn('if let value = snapshot.stages', self.view)
        self.assertIn('else if let failure = snapshot.failure', self.view)
        self.assertIn('requiresLogin: failure == .login', self.view)
        self.assertIn('unavailable: failure == .unavailable', self.view)
        self.assertIn('snapshot.isLoading', self.view)
        self.assertIn('else { Button("wallet.retry")', self.view)
        self.assertNotIn('funds.loadedScope', self.view)

    def test_task_identity_and_visibility_control_source_activation(self):
        for value in ['.task(id: owner)', 'guard !Task.isCancelled else { return }',
                      'funds.activate(reader: reader); await load()', '.onDisappear { funds.deactivate() }',
                      '.refreshable { await load() }', 'await funds.reload(reader: reader)']:
            self.assertIn(value, self.view)

    def test_original_reader_and_request_boundaries_remain_exact(self):
        for path, digest in {
            'Core/WalletCommerceService.swift': '58ee2f3bbb849d54d1c7eb9f03470bdc6c33fb2bf93baa1e9d0ce5494732e0ab',
            'Core/WalletCommerceSafety.swift': '66188645f55d549b3833ffba560f1256c47377f2936e64d32c12c7dc894ab6ed',
            'Core/WalletPointsLedgerPresentation.swift': 'f7efeef848377ec20c15c53f09cb66dc665a9a7825186cb81cea7279211e5532',
        }.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)
        for forbidden in ['URLRequest', 'HTTPTransport', 'execute(', 'checkout(', 'UserDefaults', 'api/']:
            self.assertNotIn(forbidden, self.core)

    def test_registration_handoff_has_only_new_core_membership(self):
        handoff = json.loads((ROOT / 'Tests/ContractChecks/fixtures/wallet_assets_entry_registration.json').read_text())
        self.assertEqual(handoff['target'], 'Questify.xcodeproj/project.pbxproj')
        self.assertEqual(hashlib.sha256(handoff['patch'].encode()).hexdigest(), handoff['patch_sha256'])
        self.assertIn('Core/WalletAssetsReadPresentation.swift', handoff['patch'])
        for forbidden in ['Runtime', 'AppSession', 'Composition', 'Resources/', 'WalletCommerceService']:
            self.assertNotIn(forbidden, handoff['patch'])


if __name__ == '__main__':
    unittest.main()
