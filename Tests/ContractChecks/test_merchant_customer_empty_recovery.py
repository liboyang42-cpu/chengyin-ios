"""Focused first-page recovery checks. Swift/runtime execution is separate."""
from pathlib import Path
import hashlib
import json
import unittest
from merchant_customer_empty_inverse import BASE_SHA256, POST_SHA256, BYTE_HUNKS, before_customer_empty_source

ROOT = Path(__file__).resolve().parents[2]

class MerchantCustomerEmptyRecoveryContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_exact_inverse_preserves_all_previous_product_bytes(self):
        source = self.read('App/MerchantBusinessViews.swift')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), POST_SHA256)
        restored = before_customer_empty_source(source)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), BASE_SHA256)
        self.assertNotIn('MerchantCustomerEmptyRecovery(', restored)

    def test_inverse_rejects_omission_duplication_and_unrelated_edits(self):
        raw = self.read('App/MerchantBusinessViews.swift').encode()
        offset, addition, _ = next(h for h in BYTE_HUNKS if h[1])
        for altered in [raw + b'\n', raw[:offset] + raw[offset + len(addition):],
                        raw[:offset] + addition + raw[offset:],
                        raw.replace(b'state.snapshot == snapshot', b'true', 1)]:
            with self.assertRaises(ValueError):
                before_customer_empty_source(altered.decode())

    def test_recovery_action_is_current_snapshot_and_draft_guarded_before_mutation(self):
        source = self.read('App/MerchantBusinessViews.swift')
        section = source.split('if let recovery = MerchantCustomerEmptyRecovery(document:', 1)[1].split('} else if query != .operators', 1)[0]
        mutation = section.index('keyword = next.keyword')
        for guard in ['state.isCurrent', '!state.isBusy', 'state.failureKey == nil', 'state.snapshot == snapshot',
                      'query == snapshot.document.query', 'recovery.matchesDraft', 'let next = recovery.recoveredQuery']:
            self.assertLess(section.index(guard), mutation)
        self.assertIn('Task { await reload() }', section)
        self.assertNotIn('execute(', section)
        self.assertIn('_keyword = State(initialValue: filter.keyword)', source)
        self.assertIn('_sourceStart = State(initialValue: filter.sourceStart ?? "")', source)

    def test_keyword_group_and_advanced_order_matches_source(self):
        source = self.read('Core/MerchantCustomerEmptyRecovery.swift')
        self.assertLess(source.index('if !query.keyword'), source.index('else if query.tagID'))
        self.assertLess(source.index('else if query.tagID'), source.index('else if query.segment'))
        self.assertLess(source.index('else if query.segment'), source.index('Self.count(document.summary'))
        self.assertIn('query.page == 1, document.rows.isEmpty', source)
        self.assertIn('result.keyword = ""', source)
        self.assertIn('result.segment = "all"', source)
        self.assertIn('result.tagID = nil; result.sourceType = nil; result.sourceStart = nil; result.sourceEnd = nil', source)
        self.assertIn('result.page = 1', source)

    def test_unknown_counts_do_not_become_zero_or_a_false_empty_claim(self):
        source = self.read('Core/MerchantCustomerEmptyRecovery.swift')
        self.assertIn('kind = .statisticsUnavailable; action = .retry', source)
        self.assertIn('kind = count > 0 ? .listUnavailable : .noCustomers', source)
        self.assertIn('default: return nil', source)
        self.assertIn('!result.isNaN, result >= 0', source)
        self.assertNotIn('?? 0', source.split('private static func count', 1)[1])

    def test_stateless_ui_has_real_recovery_and_no_new_io(self):
        source = self.read('App/MerchantCustomerEmptyRecoverySection.swift')
        self.assertIn('action: apply', source)
        self.assertIn('.disabled(!canApply)', source)
        self.assertIn('if hasUnsubmittedFilters', source)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', source)
        for forbidden in ['@State', 'URLSession', 'openURL', 'UIPasteboard', 'execute(', '.task(']:
            self.assertNotIn(forbidden, source)

    def test_independent_bilingual_fragment_covers_every_empty_kind_and_action(self):
        keys = json.loads(self.read('Resources/MerchantCustomerEmptyRecoveryLocalizations.fragment.json'))
        for kind in ['search', 'searchInGroup', 'advanced', 'group', 'statisticsUnavailable', 'listUnavailable', 'noCustomers']:
            for suffix in ['title', 'hint']:
                self.assertIn('merchant.customerEmpty.' + kind + '.' + suffix, keys)
        for action in ['clearSearch', 'allGroups', 'clearAdvanced', 'retry']:
            self.assertIn('merchant.customerEmpty.action.' + action, keys)
        for item in keys.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'].strip())

    def test_authored_cases_cover_preservation_drafts_and_refresh(self):
        source = self.read('Tests/CoreTests/MerchantCustomerEmptyRecoveryTests.swift')
        for name in ['testSearchInGroupShowsAllGroupsAndPreservesKeywordAndAdvancedFilters',
                     'testSearchInAllGroupsClearsOnlyKeyword',
                     'testAdvancedFilterEmptyDoesNotMisreportGlobalCountsOrClearGroup',
                     'testAbsentNullMalformedAndNegativeCountsRemainUnknownNotZero',
                     'testUnsubmittedDraftChangesCannotBeDiscardedByRecovery',
                     'testPopulatedOtherDomainAndLaterPagesDoNotUseFirstPageRecovery']:
            self.assertIn('func ' + name, source)

if __name__ == '__main__':
    unittest.main()
