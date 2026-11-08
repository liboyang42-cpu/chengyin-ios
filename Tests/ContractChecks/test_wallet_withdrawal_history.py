"""Source integration and root handoff checks; no Apple runtime claim."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WalletWithdrawalHistoryContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/WalletWithdrawalHistoryView.swift').read_text()
        self.core = (ROOT / 'Core/WalletWithdrawalHistoryPresentation.swift').read_text()
        self.handoff = json.loads((ROOT / 'Tests/ContractChecks/fixtures/wallet_withdrawal_history_registration.json').read_text())

    def test_read_uses_original_nonpaged_source_without_financial_mutation(self):
        self.assertIn('reader.read { try await $0.withdrawals(token: $1) }', self.core)
        for value in ['URLRequest', 'HTTPTransport', 'execute(', 'submit(', 'checkout(', 'afterPoints',
                      'afterBalance', 'pointBalance', '.sorted', 'pageNum', 'pageSize']:
            self.assertNotIn(value, self.core)
        self.assertNotIn('wallet.loadMore', self.view)
        service = (ROOT / 'Core/WalletCommerceService.swift').read_text().split('public func withdrawals(', 1)[1].split('private static func validProduct', 1)[0]
        self.assertIn('path: "api/withdrawal/list", fields: [:], token: token, body: false', service)
        self.assertNotIn('pageNum', service)

    def test_every_status_amount_and_account_is_a_record_fact(self):
        self.assertIn('WalletWithdrawalHistoryEntry(record: record)', self.view)
        for value in ['entry.amount.text', 'entry.currency ?? appLocalized("wallet.currencyUnknown", locale: locale)',
                      'entry.statusKey', 'entry.recordedTime', 'entry.maskedAccount']:
            self.assertIn(value, self.view)
        for forbidden in ['bankAccount', 'wallet.pointsBalance', 'wallet.available', '.reduce', 'UserDefaults']:
            self.assertNotIn(forbidden, self.view)
        self.assertIn('bank.withdrawal.historyNotice', self.view)
        self.assertIn('withdrawalHistory.statusFact', self.view)

    def test_owner_masks_data_errors_and_loading_before_new_task(self):
        for value in ['model.snapshot(for: owner)', 'snapshot.page', 'snapshot.isLoading',
                      'snapshot.failure == .login', 'snapshot.failure == .unavailable',
                      '.task(id: owner)', 'model.activate(reader: reader); await load()',
                      '.onDisappear { model.deactivate() }', '.refreshable { await load() }']:
            self.assertIn(value, self.view)

    def test_limited_empty_batch_and_missing_fields_are_explicit(self):
        self.assertIn('if snapshot.sourceLimited { Text("withdrawalHistory.emptyBatch"', self.view)
        for value in ['withdrawalHistory.timeUnknown', 'withdrawalHistory.accountUnknown', 'wallet.sourceLimited']:
            self.assertIn(value, self.view)
        self.assertIn('Set(page.rows.map(\\.id)).count == page.rows.count', self.core)
        self.assertIn('page.total.map({ $0 >= 0 }) ?? true', self.core)

    def test_bilingual_catalog_has_exact_keys_used_by_dedicated_table(self):
        catalog = json.loads((ROOT / 'Resources/WalletWithdrawalHistory.xcstrings').read_text())['strings']
        used = set(re.findall(r'"(withdrawalHistory\.[A-Za-z]+)"', self.view))
        self.assertEqual(set(catalog), used)
        for key, item in catalog.items():
            self.assertIn('"' + key + '", tableName: "WalletWithdrawalHistory"', self.view)
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})

    def test_root_handoff_contains_only_expected_precise_edits(self):
        expected = {'Questify.xcodeproj/project.pbxproj', 'App/WalletCommerceViews.swift', 'Tests/ContractChecks/test_wallet_points_ledger.py'}
        self.assertEqual({x['path'] for x in self.handoff['targets']}, expected)
        patch = self.handoff['patch']
        self.assertEqual(hashlib.sha256(patch.encode()).hexdigest(), self.handoff['patch_sha256'])
        self.assertIn('var body: some View { WalletWithdrawalHistoryView(reader: reader) }', patch)
        for path in ['Core/WalletWithdrawalHistoryPresentation.swift', 'App/WalletWithdrawalHistoryView.swift', 'Resources/WalletWithdrawalHistory.xcstrings']:
            self.assertIn(path, patch)
        for forbidden in ['AppSession', 'Runtime', 'Composition', 'WalletCommerceService.swift']:
            self.assertNotIn(forbidden, patch)


if __name__ == '__main__':
    unittest.main()
