"""Focused source wiring checks; not Swift, app-hosted, or UI runtime evidence."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
INSERTION = '''        if row.kind == .customer, compact {
            MerchantCustomerContactSummary(record: row, access: access)
        }
'''
BASE_VIEW_SHA256 = '5529cf635974fd7b82e79242ac426cd18bfa275bfb487250f87fe3017834bb05'


class MerchantCustomerContactContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_only_one_compact_customer_insertion_preserves_every_original_byte(self):
        current = self.read('App/MerchantBusinessRecordViews.swift')
        self.assertEqual(current.count(INSERTION), 1)
        original = current.replace(INSERTION, '', 1).encode()
        self.assertEqual(hashlib.sha256(original).hexdigest(), BASE_VIEW_SHA256)

    def test_projection_requires_customer_read_and_sensitive_permission_for_phone(self):
        source = self.read('Core/MerchantCustomerContactPresentation.swift')
        self.assertIn('guard record.kind == .customer, access.allows("merchant:crm:read") else { return nil }', source)
        self.assertIn('if access.allows("merchant:crm:sensitive:read")', source)
        self.assertIn('Self.isSourceMask(phone)', source)
        self.assertIn('self = .maskedPhone(phone)', source)
        self.assertIn('record.fields["contactHint"]', source)
        self.assertNotIn('role ==', source)

    def test_unrecognized_phone_is_not_remasked_or_made_callable(self):
        source = self.read('Core/MerchantCustomerContactPresentation.swift')
        self.assertIn('switch units.count', source)
        self.assertIn('case 6: prefix = 1', source)
        self.assertIn('case 8: prefix = 2', source)
        self.assertIn('case 11: prefix = 3', source)
        self.assertIn('default: return false', source)
        self.assertIn('units[prefix..<(prefix + 4)].allSatisfy { $0 == 42 }', source)
        self.assertNotIn('replacingOccurrences', source)

    def test_component_has_no_persistent_state_network_or_contact_actions(self):
        source = self.read('App/MerchantCustomerContactSummary.swift')
        self.assertIn('.init(record: record, access: access)', source)
        self.assertIn('Text(verbatim: phone)', source)
        self.assertIn('Text(verbatim: reason)', source)
        self.assertIn('.privacySensitive()', source)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', source)
        for forbidden in ['@State', '@AppStorage', 'Task {', 'URLSession', 'Button(', 'Link(', 'UIPasteboard', 'openURL', 'tel:', '.textSelection(']:
            self.assertNotIn(forbidden, source)

    def test_additive_fragment_does_not_require_overwriting_catalog(self):
        fragment = json.loads(self.read('Resources/MerchantCustomerContactLocalizations.fragment.json'))
        self.assertEqual(set(fragment), {'merchant.customerContact.maskedPhone', 'merchant.customerContact.unavailable'})
        for value in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'].strip())

    def test_authored_edge_and_permission_cases_remain_present(self):
        core = self.read('Tests/CoreTests/MerchantCustomerContactPresentationTests.swift')
        for name in ['testPlaintextAndUnexpectedMaskFormatsAreNeverDisplayedOrRemasked',
                     'testSourceContactReasonSurvivesWithoutAnySensitivePermission',
                     'testNoCRMReadPermissionReturnsNoPresentationEvenWithSensitivePermission',
                     'testRevokedSensitivePermissionCannotExposeRetainedPhoneField',
                     'testMissingNullBlankAndMalformedContactAreUnknownNotNoPhoneClaim',
                     'testRefreshReplacesContactRatherThanKeepingPriorCustomerState']:
            self.assertIn('func ' + name, core)
        app = self.read('Tests/AppUnitTests/MerchantCustomerContactSummaryTests.swift')
        self.assertIn('testRenderProjectionHidesPhoneImmediatelyWhenAccessIsReduced', app)
        self.assertIn('testUnexpectedCleartextRemainsUnavailableWithBothPermissions', app)


if __name__ == '__main__':
    unittest.main()
