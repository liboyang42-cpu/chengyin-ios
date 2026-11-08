"""Owner-bound Profile order reading, with no backend activation or transaction change."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class OwnedOrderReadPresentationContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/ProfileReadScreen.swift').read_text()
        self.core = (ROOT / 'Core/ProfileReadPresentation.swift').read_text()

    def test_orders_detail_request_id_is_explicit_and_list_remains_list(self):
        orders = (ROOT / 'App/ProfileOrdersView.swift').read_text()
        self.assertIn('accessibilityPrefix: "profile.order.detail", requestID: id, load: { try await reader.profileOrder(id: id) }', orders)
        self.assertIn('accessibilityPrefix: "profile.orders", load: { try await reader.profileOrders() }', orders)
        self.assertIn('requestID: Int? = nil', self.view)

    def test_content_error_loading_and_toolbar_share_current_owner_snapshot(self):
        for fragment in ['.init(reader: reader, identity: reader.identity, configured: reader.isConfigured,',
                         'surface: accessibilityPrefix, requestID: requestID)', 'model.snapshot(for: readKey)',
                         'snapshot.error.map(ProfileLoadIssue.init)', 'snapshot.isLoading', 'snapshot.value',
                         '.task(id: readKey)', 'model.activate(owner: readKey, source: reader)']:
            self.assertIn(fragment, self.view)
        self.assertNotIn('.task(id: reader.identity)', self.view)
        self.assertNotIn('@State private var value:', self.view)

    def test_actual_task_owner_and_list_navigation_preservation_remain(self):
        for fragment in ['loadOwner.start { await reload() }', 'loadOwner.run { await reload() }',
                         'loadOwner.deactivate(); model.suspend()', 'currentOwner: { readKey }']:
            self.assertIn(fragment, self.view)
        suspend = self.core.split('public func suspend()', 1)[1].split('public func load(', 1)[0]
        self.assertNotIn('value = Snapshot()', suspend)
        self.assertIn('active = false', suspend)

    def test_original_owner_reader_and_activation_blocker_are_preserved(self):
        reader = (ROOT / 'Core/OwnedOrderRead.swift').read_text()
        self.assertIn('Production issuance remains blocked', reader)
        self.assertIn('current() == captured', reader)
        self.assertIn('expectedAccountID: $1.context.session.accountID', reader)
        composition = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.assertIn('ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }', composition)
        service = (ROOT / 'Core/ProfileService.swift').read_text()
        for fragment in ['result.total == result.rows.count', '$0.memberID == expectedAccountID', 'result.id == id']:
            self.assertIn(fragment, service)
        for fragment in ['URLRequest', 'HTTPTransport', 'UserDefaults', 'submit(', 'execute(', 'payableAmount', 'refundAmount', 'api/']:
            self.assertNotIn(fragment, self.core)

    def test_existing_literal_error_provenance_and_currency_facts_remain(self):
        self.assertIn('Text(verbatim: message)', self.view)
        self.assertIn('message = failure?.message.flatMap', self.view)
        self.assertIn('canRetry = false', self.view)
        orders = (ROOT / 'App/ProfileOrdersView.swift').read_text()
        for fragment in ['OwnedOrderMoneyText.string(amount)', 'profile.orders.moneyFactsHint', 'profile.orders.paymentCode', 'profile.orders.refundCode']:
            self.assertIn(fragment, orders)

    def test_core_registration_handoff_is_exact_and_does_not_edit_runtime(self):
        handoff = json.loads((ROOT / 'Tests/ContractChecks/fixtures/owned_order_read_presentation_registration.json').read_text())
        self.assertEqual(handoff['target'], 'Questify.xcodeproj/project.pbxproj')
        self.assertEqual(hashlib.sha256(handoff['patch'].encode()).hexdigest(), handoff['patch_sha256'])
        self.assertIn('Core/ProfileReadPresentation.swift', handoff['patch'])
        for fragment in ['AppSession', 'Runtime', 'Composition', 'ProfileService.swift']:
            self.assertNotIn(fragment, handoff['patch'])


if __name__ == '__main__':
    unittest.main()
