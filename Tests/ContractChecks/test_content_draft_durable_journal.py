"""Source-only durable W02 invariants; no Swift/OS/runtime proof."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ContentDraftDurableJournalSourceTests(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / 'Core/ContentDraftDurableJournal.swift').read_text()
        self.os = (ROOT / 'Core/ContentDraftSystemStorage.swift').read_text()
        self.coordinator = (ROOT / 'Core/VersionedContentDraftCoordinator.swift').read_text()

    def test_small_anchor_encrypted_bounded_blob(self):
        for token in ['bytes.count <= 8_192', 'maximumBlobBytes = 4_194_304', 'AES.GCM.seal', 'AES.GCM.open',
                      'authenticating: binding + Data', 'Data(SHA256.hash(data: plaintext)) == anchor.digest']:
            self.assertIn(token, self.core)
        anchor = self.core.split('private struct Anchor: Codable')[1].split('private let scope:')[0]
        self.assertNotIn('payloadJson', anchor)
        self.assertIn('SymmetricKey(size: .bits256)', self.core)

    def test_reservation_precedes_file_and_ready_cas(self):
        insert = self.core.split('func insert(_ pending:')[1].split('private func matching')[0]
        self.assertLess(insert.index('anchors.insert'), insert.index('ciphertexts.insert'))
        self.assertLess(insert.index('ciphertexts.insert'), insert.rindex('anchors.exchange'))
        self.assertIn('matchingTag: reserved.tag', insert)
        self.assertNotIn('remove', insert)

    def test_atomic_generation_predicates_no_upsert(self):
        for method in ['func exchange(', 'func remove(']:
            body = self.os.split(method, 1)[1].split('\n    }', 1)[0]
            self.assertIn('request[kSecAttrGeneric as String] = matchingTag', body)
            self.assertIn('errSecItemNotFound { return false }', body)
        self.assertIn('SecItemAdd(request as CFDictionary, nil)', self.os)
        self.assertIn('errSecDuplicateItem { return false }', self.os)
        self.assertEqual(self.os.count('SecItemUpdate('), 1)
        self.assertIn('value.generation = random()', self.core)
        self.assertIn('current.tag == expected.generation', self.core)

    def test_clear_tombstone_before_file_cleanup_and_conditional_remove(self):
        clear = self.core.split('func clear(matching pending:')[1]
        self.assertLess(clear.index('value.state = .clearing'), clear.index('anchors.exchange'))
        self.assertLess(clear.index('anchors.exchange'), clear.index('finishClear'))
        finish = self.core.split('private func finishClear')[1].split('private func readRecord')[0]
        self.assertLess(finish.index('ciphertexts.removeDurably'), finish.index('anchors.exchange'))
        self.assertIn('matchingTag: item.tag', finish)

    def test_full_mutation_and_bound_scope_bytes(self):
        for token in ['old.value.mutation == new.mutation', 'current.tag == expected.generation', 'try await load(value) == expected.value',
                      'let bytes = Data(field.utf8)', 'UInt32(bytes.count).bigEndian', 'value.binding == binding',
                      'identity.clientDraftKey.utf8.elementsEqual(scope.clientDraftKey.utf8)']:
            self.assertIn(token, self.core)
        initializer = self.core.split('init(scope: ContentDraftJournalScope, anchors:')[2].split('private func enter')[0]
        for token in ['scope.market.rawValue', 'scope.baseURL.absoluteString', 'scope.namespace', 'scope.accountID',
                      'scope.ownerMemberID', 'scope.businessType.rawValue', 'scope.clientDraftKey']:
            self.assertIn(token, initializer)
        for excluded in ['token', 'epoch', '.role', 'identity.scope']:
            self.assertNotIn(excluded, initializer)

    def test_no_plaintext_metadata_logging_defaults_or_ui_activation(self):
        for source in [self.core, self.os]:
            self.assertNotIn('UserDefaults', source)
            self.assertIsNone(re.search(r'(?<![\w])(?:print|debugPrint|NSLog|os_log)\s*\(', source))
            self.assertNotIn('kSecAttrAccessGroup', source)
        for path in ROOT.glob('App/*.swift'):
            if path.name != 'ContentDraftSystemStorage.swift':
                self.assertNotIn('ContentDraftJournalFactory.make', path.read_text())
        self.assertIn('journal: (any ContentDraftSecureJournal)? = nil', self.coordinator)

    def test_os_storage_protection_and_durable_exclusive_files(self):
        for token in ['kSecAttrAccessibleWhenUnlockedThisDeviceOnly', 'kSecUseDataProtectionKeychain as String: true',
                      'kSecAttrSynchronizable as String: false', 'kSecUseAuthenticationUIFail', 'O_EXCL', 'O_NOFOLLOW',
                      'mode_t(0o600)', '0o700', 'PROTECTION_CLASS_A', 'F_GETPROTECTIONCLASS', 'components.dropLast()', 'mkdirat(parent, leaf',
                      'fsync(', 'F_FULLFSYNC', 'info.st_size <= Int64(limit)', 'info.st_nlink == 1']:
            self.assertIn(token, self.os)
        self.assertNotIn('contentsOfDirectory', self.os)
        self.assertNotIn('.atomic', self.os)

    def test_storage_suspensions_are_fenced_and_busy_before_insert(self):
        confirm = self.coordinator.split('public func confirm()')[1].split('public func retryExact')[0]
        self.assertLess(confirm.index('phase = .sending'), confirm.index('await journal.insert'))
        for match in re.finditer(r'(?:try await journal\.(?:insert|replace|clear)\([^\n]*\)|guard try await journal\.read\(\) == [^\n]*\n)', self.coordinator):
            following = self.coordinator[match.end():].lstrip()
            self.assertTrue(following.startswith('guard gate(ticket)'), match.group(0))
        self.assertIn('guard gate(), !busy, let original = pending', self.coordinator)

    def test_marker_and_empty_anchor_preserve_missing_key_lock(self):
        self.assertIn('ciphertexts.createPresence(slot: slot)', self.core)
        self.assertIn('guard !present else', self.core)
        self.assertIn('state: .empty', self.core)
        self.assertNotIn('anchors.remove(', self.core)
        self.assertIn('currentAnchor.state == .empty', self.core)
        self.assertIn('return slot + ".presence"', self.os)
        self.assertIn('func make(scope: ContentDraftJournalScope) async throws', self.os)
        self.assertNotIn('appropriateFor: nil, create: true', self.os)

    def test_synthetic_test_matrix_and_platform_boundary_authored(self):
        tests = (ROOT / 'Tests/CoreTests/ContentDraftDurableJournalTests.swift').read_text()
        self.assertGreaterEqual(len(re.findall(r'func test\w+\(', tests)), 17)
        for term in ['Interrupted', 'ConcurrentDistinctWriters', 'SameOwnerRoleAliases', 'RawUnicodeBytes', 'ZeroHTTP', 'StaleGeneration', 'Tombstone']:
            self.assertIn(term, tests)
        platform = (ROOT / 'Tests/AppUnitTests/ContentDraftSystemStorageTests.swift').read_text()
        self.assertIn('#if targetEnvironment(simulator)', platform)
        self.assertIn('questify.tests.content-draft.', platform)
        self.assertIn('UUID().uuidString', platform)
        self.assertIn('guard added else { return }', platform)

if __name__ == '__main__': unittest.main()
