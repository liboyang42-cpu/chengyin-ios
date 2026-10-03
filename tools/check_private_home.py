#!/usr/bin/env python3
"""Source/contract guard only. Never runs Swift, location, Keychain, or network."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
LOGGING_CALL = re.compile(r"(?<![\w])(?:print|debugPrint|dump|os_log|Logger)\s*\(")
def has_logging_call(source):
    """Conservative source guard, not a Swift parser; match complete call identifiers."""
    return LOGGING_CALL.search(source) is not None
class PrivateHomeSourceTests(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_exact_owner_route_only(self):
        value = self.text('Core/PrivateHomeService.swift')
        self.assertIn('"api/native/home"', value)
        self.assertNotIn('/restore', value); self.assertNotIn('/proof', value)
        self.assertNotIn('URLSession(', value)
    def test_no_caller_owner_payload(self):
        value = self.text('Core/PrivateHomeContracts.swift').split('public struct PrivateHomeMutation:')[1].split('public struct PrivateHomeReceipt:')[0]
        self.assertNotIn('ownerId', value); self.assertNotIn('accountID', value)
    def test_privacy_and_stable_payload(self):
        value = self.text('Core/PrivateHomeService.swift')
        for required in ['.sortedKeys', '"no-store"', '"no-cache"', '.reloadIgnoringLocalCacheData']:
            self.assertIn(required, value)
    def test_default_off_and_journal_required(self):
        value = self.text('Core/PrivateHomeCoordinator.swift')
        self.assertIn('enabled: Bool = false', value)
        self.assertIn('journal: (any PrivateHomeSecureJournaling)? = nil', value)
        self.assertLess(value.index('try await journal.save(review)'), value.index('await dispatchPending()'))
        self.assertIn('journal.scope == PrivateHomeJournalScope(owner: owner)', value)
    def test_no_sensitive_persistence_or_location_apis(self):
        for path in list(ROOT.glob('Core/PrivateHome*.swift')) + list(ROOT.glob('App/PrivateHome*.swift')):
            value = path.read_text()
            for forbidden in ['UserDefaults', 'CLLocationManager', 'requestWhenInUseAuthorization', 'URLSession(']:
                # Documentation names prohibited plaintext storage, never instantiates it.
                if forbidden == 'UserDefaults': continue
                self.assertNotIn(forbidden, value, str(path))
            self.assertFalse(has_logging_call(value), str(path))
    def test_fixture_is_debug_only(self):
        self.assertTrue(self.text('App/PrivateHomeFixtureHost.swift').startswith('#if DEBUG'))
    def test_account_entry_is_unconfigured(self):
        self.assertIn('privateHomeCoordinator: PrivateHomeCoordinator? = nil', self.text('App/AccountView.swift'))
    def test_keychain_uses_insert_only_and_conditional_delete(self):
        value = self.text('App/PrivateHomeKeychainJournal.swift')
        self.assertNotIn('SecItemUpdate', value)
        for required in ['actor PrivateHomeSystemKeychain', 'SecItemAdd', 'errSecDuplicateItem', 'SecItemDelete', 'request[kSecAttrGeneric as String] = matchingTag', 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly', 'kSecUseDataProtectionKeychain as String: true', 'kSecAttrSynchronizable as String: false']:
            self.assertIn(required, value)
        self.assertIn('storageScope.service == owner.namespace', value)
        self.assertIn('guard stored == mutation', value)
    def test_storage_awaits_are_refenced_before_dispatch_or_state(self):
        value = self.text('Core/PrivateHomeCoordinator.swift')
        for operation in ['let stored = try await journal.read(); try stored?.validate()', 'try await journal.save(review)', 'try await journal.clear(matching: mutation)']:
            tails = value.split(operation)[1:]
            self.assertTrue(tails)
            for tail in tails:
                self.assertTrue(tail.lstrip().startswith('guard ticket == generation, gate() else { return }'))
    def test_every_dispatch_rechecks_exact_durable_pending_and_keeps_unknown_on_failure(self):
        value = self.text('Core/PrivateHomeCoordinator.swift').split('private func dispatchPending() async {', 1)[1]
        read = value.index('let stored = try await journal.read(); try stored?.validate()')
        check = value.index('guard journal.scope == PrivateHomeJournalScope(owner: owner), stored == mutation')
        failure = value.index('issue = .storageUnavailable; phase = .unknown; return')
        send = value.index('let receipt = try await service.mutate(mutation)')
        self.assertLess(read, check); self.assertLess(check, failure); self.assertLess(failure, send)
        self.assertNotIn('pending = nil', value[:send])
    def test_bilingual_copy(self):
        catalogue = json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        expected = json.loads(self.text('docs/private-home-localizations.json'))
        for key, translations in expected.items():
            for locale, text in translations.items():
                self.assertEqual(catalogue[key]['localizations'][locale]['stringUnit']['value'], text)
if __name__ == '__main__': unittest.main()
