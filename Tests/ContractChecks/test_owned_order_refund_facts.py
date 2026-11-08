"""Read-only refund projection and narrow integration handoff. Apple runtime unverified."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class OwnedOrderRefundFactsContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/ProfileOrderRefundReadSection.swift').read_text()
        self.core = (ROOT / 'Core/ProfileOrderRefundReadFacts.swift').read_text()
        self.handoff = json.loads((ROOT / 'Tests/ContractChecks/fixtures/owned_order_refund_facts_registration.json').read_text())

    def test_only_original_owned_detail_fields_are_projected(self):
        for field in ['order.refundAmount', 'order.refundApplicationStatus', 'order.refundPayoutStatus',
                      'order.manualRefundCaseStatus', 'order.refundDeadlineDisplay', 'order.memberID',
                      'reader.identity', 'reader.isConfigured']:
            self.assertIn(field, self.view)
        for field in ['payableAmount', 'wechatPaymentAmount', 'pointPaymentAmount', 'ownerID']:
            self.assertNotIn(field, self.view)

    def test_expansion_is_local_without_read_or_transaction_capability(self):
        self.assertIn('DisclosureGroup', self.view)
        for text in ['.task(', 'Task {', 'profileOrder(', 'submit(', 'execute(', 'refund(', 'URLRequest',
                     'HTTPTransport', 'UserDefaults', 'openURL', 'OrderLifecycleCoordinator']:
            self.assertNotIn(text, self.view + self.core)
        self.assertIn('ProfileOrderRefundReadFacts.matchesAccount', self.view)

    def test_unknown_and_exact_amount_do_not_become_arrival_or_inferred_currency(self):
        for text in ['facts.amountText', 'orderRefundRead.amountUnknown', 'activity.currencyUnconfirmed',
                     'profile.orders.unknown', 'orderRefundRead.caution', 'orderRefundRead.notProvided']:
            self.assertIn(text, self.view)
        self.assertIn('NSDecimalNumber(decimal: amount).stringValue', self.core)
        for text in ['Double(', '/ 100', 'NumberFormatter', 'Date()', '.refundable', 'paymentStatus']:
            self.assertNotIn(text, self.core)
        self.assertIn('case 1, 4: self = .recordedComplete', self.core)
        self.assertIn('default: self = .unknown', self.core)

    def test_server_text_is_literal_and_deadline_is_not_a_local_eligibility_rule(self):
        self.assertIn('Text(verbatim: manualCase)', self.view)
        self.assertIn('Text(verbatim: deadline)', self.view)
        self.assertNotIn('TimeZone', self.core)
        self.assertNotIn('timeInterval', self.core)

    def test_complete_bilingual_dedicated_catalog(self):
        catalog = json.loads((ROOT / 'Resources/OrderRefundRead.xcstrings').read_text())['strings']
        expected = set(re.findall(r'"(orderRefundRead\.[A-Za-z]+)"', self.view))
        expected.update('orderRefundRead.payout.' + x for x in ['processing', 'recordedComplete', 'manualPending', 'manualReview', 'queued', 'dispatching', 'unknown'])
        self.assertEqual(set(catalog), expected)
        for item in catalog.values():
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})
            for localized in item['localizations'].values():
                self.assertTrue(localized['stringUnit']['value'])

    def test_handoff_only_adds_section_inside_existing_fresh_order_detail(self):
        self.assertEqual({x['path'] for x in self.handoff['targets']}, {'Questify.xcodeproj/project.pbxproj', 'App/ProfileOrdersView.swift'})
        self.assertEqual(hashlib.sha256(self.handoff['patch'].encode()).hexdigest(), self.handoff['patch_sha256'])
        patch = self.handoff['patch'].split('--- a/App/ProfileOrdersView.swift\n', 1)[1]
        additions = [line for line in patch.splitlines() if line.startswith('+') and not line.startswith('+++')]
        self.assertEqual(additions, ['+                ProfileOrderRefundReadSection(order: order, requestedID: id, reader: reader)'])
        self.assertNotIn('\n- ', patch)
        self.assertIn('requestID: id, load: { try await reader.profileOrder(id: id) }', (ROOT / 'App/ProfileOrdersView.swift').read_text())
        self.assertIn('model.snapshot(for: readKey)', (ROOT / 'App/ProfileReadScreen.swift').read_text())


if __name__ == '__main__':
    unittest.main()
