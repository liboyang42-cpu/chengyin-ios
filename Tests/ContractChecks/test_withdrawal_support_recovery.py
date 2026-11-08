"""Read-only support-page integration; no claim of Apple compilation or device execution."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WithdrawalSupportRecoveryContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/WithdrawalSupportLandingView.swift').read_text()
        self.core = (ROOT / 'Core/WithdrawalSupportReadPresentation.swift').read_text()

    def test_both_sections_use_the_current_owner_snapshot(self):
        for value in ['model.snapshot(for: owner)', 'snapshot.balanceLoading', 'snapshot.balance',
                      'snapshot.stagesLoading', 'snapshot.stages', 'issue(snapshot.balanceFailure)',
                      'issue(snapshot.stagesFailure)']:
            self.assertIn(value, self.view)
        for old in ['loadedScope', 'balanceFailed', 'stagesFailed', '@State private var generation']:
            self.assertNotIn(old, self.view)

    def test_lifecycle_and_contact_sheet_are_exact_reader_owned(self):
        for value in ['.task(id: owner)', 'guard !Task.isCancelled else { return }',
                      'model.activate(reader: reader); await load()', '.onChange(of: owner)',
                      '.onDisappear { model.deactivate(); showContact = false; contactOwner = nil }',
                      'guard currentOwner == owner, model.isActive(for: currentOwner)',
                      'contactOwner == owner, model.isActive(for: owner)', '.refreshable { await load() }']:
            self.assertIn(value, self.view)

    def test_original_read_contracts_and_routes_are_used(self):
        self.assertIn('reader.read { try await $0.withdrawalBalance(memberID: scope.accountID, token: $1) }', self.core)
        self.assertIn('reader.read { try await $0.stages(token: $1) }', self.core)
        self.assertIn('if let bankDestination { bankDestination() } else { BankWithdrawalView(reader: reader) }', self.view)
        self.assertIn('NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }', self.view)
        self.assertIn('WithdrawalSupportContactView()', self.view)
        # Semantic boundary checks tolerate unrelated, additive cache protections.
        service = (ROOT / 'Core/WalletCommerceService.swift').read_text()
        self.assertIn('path: "api/user/info", fields: ["member_id": String(memberID)]', service)
        self.assertIn('path: "api/wallet/stages", fields: [:], token: token, json: true', service)

    def test_login_unavailable_and_retry_are_distinct(self):
        self.assertIn('reader.scope == nil || failure == .login', self.view)
        self.assertIn('!reader.isConfigured || failure == .unavailable', self.view)
        self.assertIn('failure == .retryable', self.view)
        self.assertIn('Button("wallet.retry")', self.view)
        self.assertEqual(self.core.count('if issue == .login { deny(.login); return }'), 2)

    def test_no_balance_inference_mutation_or_new_contact_contract(self):
        for forbidden in ['WalletAmount(0)', 'afterPoints', 'pointBalance', 'URLRequest', 'HTTPTransport',
                          'UserDefaults', 'execute(', 'submit(', 'contactForCopy', 'api/']:
            self.assertNotIn(forbidden, self.core)
        self.assertIn('if !stages.amountsKnown', self.view)
        self.assertIn('currency ?? appLocalized("wallet.currencyUnknown", locale: locale)', self.view)

    def test_registration_is_a_hash_checked_handoff_only(self):
        handoff = json.loads((ROOT / 'Tests/ContractChecks/fixtures/withdrawal_support_recovery_registration.json').read_text())
        self.assertEqual(handoff['target'], 'Questify.xcodeproj/project.pbxproj')
        self.assertEqual(hashlib.sha256(handoff['patch'].encode()).hexdigest(), handoff['patch_sha256'])
        self.assertIn('Core/WithdrawalSupportReadPresentation.swift', handoff['patch'])


if __name__ == '__main__':
    unittest.main()
