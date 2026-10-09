"""Focused request, pagination and local-draft source checks; not Apple execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantFeaturedActivityPickerContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_existing_owned_activity_read_has_exact_scope_and_pagination(self):
        service = self.read('Core/MerchantOperationsService.swift')
        block = service.split('public func featuredActivities(', 1)[1].split('public func document(', 1)[0]
        self.assertIn('guard access.allows(.decor)', block)
        self.assertIn('"api/activity/list"', block)
        self.assertIn('["is_my": "1", "pageNum": String(page), "pageSize": String(MerchantFeaturedActivityPage.pageSize)]', block)
        for forbidden in ['merchantId', 'ownerMemberId', 'memberId', 'latitude', 'longitude', '.save(']: self.assertNotIn(forbidden, block)

    def test_reader_reauthorizes_and_uses_existing_cancellation_and_identity_wrapper(self):
        source = self.read('Core/MerchantOperationsReading.swift')
        block = source.split('public func featuredActivities(', 1)[1].split('public func document(', 1)[0]
        self.assertIn('return try await read { service, token in', block)
        self.assertLess(block.index('service.access(token: token)'), block.index('service.featuredActivities('))
        self.assertIn('!Task.isCancelled, expected == currentSession()', block)
        wrapper = source.split('private func read<Value>', 1)[1].split('public struct MerchantOperationsConfirmation', 1)[0]
        catch = wrapper.split('} catch {', 1)[1]
        self.assertLess(catch.index('!Task.isCancelled, currentSession() == session, captured == scope'), catch.index('onUnauthorized(session)'))

    def test_unknown_totals_and_duplicate_pages_never_imply_complete_coverage(self):
        source = self.read('Core/MerchantFeaturedActivityOptions.swift')
        for token in ['pageSize = 20', 'total = nil', 'Set(rows.map(\\.id)).count == rows.count',
                      'Set(combined.map(\\.id)).count == combined.count', 'total.map({ $0 >= combined.count })']:
            self.assertIn(token, source)
        app = self.read('App/MerchantFeaturedActivityPicker.swift')
        self.assertIn('total.map { rows.count < $0 } ?? false', app)
        self.assertIn('await load(page: loadedPage + 1)', app)
        self.assertIn('merchant.featuredPicker.unknownTotal', app)
        self.assertIn('merchant.featuredPicker.originalRetained', app)

    def test_apply_changes_only_two_fields_after_original_context_check(self):
        source = self.read('App/MerchantFeaturedActivityPicker.swift')
        for token in ['!consumed', 'owner.isCurrent', '!owner.isBusy', '!owner.isLocked', 'owner.confirmation == nil',
                      'owner.reader.scope == scope', 'owner.draftIdentity == identity', 'owner.draft == .decor(original)',
                      'guard canApply, let selectedID', 'rows.contains { $0.id == id }',
                      'var edited = original; edited.featuredType = 1; edited.featuredID = selectedID']:
            self.assertIn(token, source)
        self.assertEqual(source.count('document.edit('), 1)
        self.assertNotIn('saveReviewed(', source)
        self.assertNotIn('document.confirm(', source)

    def test_dismiss_and_reload_cancel_owned_request_and_drop_late_results(self):
        source = self.read('App/MerchantFeaturedActivityPicker.swift')
        self.assertIn('request?.cancel(); generation += 1', source)
        self.assertIn('ticket == generation, isCurrent', source)
        self.assertIn('if value == nil { picker?.cancel() }', source)
        self.assertIn('.onDisappear { picker.cancel() }', source)
        self.assertIn('onChange(of: document.coordinator.draft)', source)
        reader_tests = self.read('Tests/CoreTests/MerchantFeaturedActivityOptionsTests.swift')
        self.assertIn('testRoleReplacementBeforeLate401CannotExpireReplacementSession', reader_tests)
        self.assertIn('testCancelledReadBeforeLate401CannotExpireCurrentSession', reader_tests)

    def test_frozen_review_and_unique_bilingual_keys(self):
        source = self.read('App/MerchantOperationsEditor.swift')
        self.assertIn('MerchantFeaturedActivityPicker(document: model)', source)
        self.assertIn('confirmation.draft, value.featuredType == 1, let id = value.featuredID', source)
        self.assertIn('merchant.featuredPicker.finalValidation', source)
        fragment = json.loads(self.read('Resources/MerchantFeaturedActivityLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 13)
        self.assertEqual({key: json.loads(self.read('Resources/Localizable.xcstrings'))['strings'][key] for key in fragment}, fragment)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
