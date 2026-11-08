"""Independent sign-in facts must match the selected owner read before dispatch/receipt."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class OwnedOrderSignedInCorrelationContracts(unittest.TestCase):
    def setUp(self):
        source = (ROOT / 'Core/OwnedOrderRead.swift').read_text()
        self.reader = source.split('public final class OwnedOrderSessionReader:', 1)[1].split('public enum OwnedOrderMoneyText', 1)[0]

    def test_identity_and_availability_require_matching_sign_in_facts(self):
        for fragment in ['guard let signed = validSignedInIdentity else { return nil }',
                         'Self.matches(signed: signed, selected: selected)',
                         'signed.accountID > 0', 'signed.accountID == selected.context.session.accountID',
                         'signed.epoch == selected.context.session.epoch',
                         'signed.viewerRevision == selected.viewerRevision']:
            self.assertIn(fragment, self.reader)
        self.assertIn('else { return signed }', self.reader)
        self.assertNotIn('current()?.identity ?? signedInIdentity()', self.reader)

    def test_dispatch_and_both_result_channels_recheck_current_sign_in(self):
        body = self.reader.split('private func read<Value>', 1)[1]
        self.assertIn('guard let signed = validSignedInIdentity else { throw APIError.unauthorized }', body)
        self.assertIn('let captured = current(), Self.matches(signed: signed, selected: captured)', body)
        self.assertLess(body.index('Self.matches(signed: signed, selected: captured)'), body.index('await operation(service, captured)'))
        self.assertEqual(body.count('current() == captured, matchesSignedIn(captured)'), 2)
        self.assertLess(body.rindex('matchesSignedIn(captured)'), body.index('onUnauthorized(captured)'))

    def test_sign_in_does_not_issue_or_substitute_an_approval(self):
        signed = self.reader.split('private var validSignedInIdentity:', 1)[1].split('private func read<Value>', 1)[0]
        self.assertNotIn('OwnedOrderReadApproval(', signed)
        self.assertNotIn('OwnedOrderReadSession(', signed)
        self.assertNotIn('approvalRevision:', signed)
        self.assertIn('expectedAccountID: $1.context.session.accountID', self.reader)

    def test_root_canonical_fields_and_closed_activation_remain_compatible(self):
        session = (ROOT / 'App/AppSession.swift').read_text()
        signed = session.split('private var ownedOrderSignedInIdentity:', 1)[1].split('lazy var ownedOrderReader', 1)[0]
        self.assertIn('accountID: account.id, epoch: gate.currentStamp, viewerRevision: compositionViewerRevision', signed)
        current = session.split('private var currentOwnedOrderSession:', 1)[1].split('private var ownedOrderSignedInIdentity:', 1)[0]
        self.assertIn('approval.matches(context)', current)
        self.assertIn('viewerRevision: compositionViewerRevision, approvalRevision: approval.revision', current)
        composition = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.assertIn('ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }', composition)

    def test_no_new_route_write_or_money_state_projection(self):
        for fragment in ['URLRequest', 'HTTPTransport', 'api/', 'submit(', 'execute(', 'refundAmount', 'payableAmount', 'UserDefaults']:
            self.assertNotIn(fragment, self.reader)
        service = (ROOT / 'Core/ProfileService.swift').read_text()
        for fragment in ['result.memberID != expectedAccountID', 'result.id == id', 'result.total == result.rows.count']:
            self.assertIn(fragment, service)
        self.assertIn('Production issuance remains blocked', (ROOT / 'Core/OwnedOrderRead.swift').read_text())


if __name__ == '__main__':
    unittest.main()
