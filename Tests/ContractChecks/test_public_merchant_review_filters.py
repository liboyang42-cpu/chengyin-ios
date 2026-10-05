"""Native structural contracts only; they do not execute Swift or establish UI parity."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PublicMerchantReviewFilterChecks(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_public_predicates_are_local_and_have_no_pending_mode(self):
        source = self.text('Core/PublicMerchantReviews.swift')
        enum = source.split('public enum PublicMerchantReviewFilter:')[1].split('@MainActor public protocol')[0]
        self.assertIn('case all, low, photos', enum)
        self.assertNotIn('pending', enum)
        self.assertIn('case .low: return item.rating <= 3', enum)
        self.assertIn('case .photos: return !item.imageUrls.isEmpty', enum)
        for forbidden in ['request', 'transport', 'execute', 'session', 'eligibility', 'canReply', 'canReport']:
            self.assertNotIn(forbidden, enum)

    def test_projection_preserves_loaded_offsets_photo_targets_and_report_pages(self):
        source = self.text('App/PublicMerchantReviewsView.swift')
        self.assertIn('items.enumerated().filter { reviewFilter.matches($0.element) }', source)
        self.assertIn('ForEach(visibleItems, id: \\.offset)', source)
        self.assertIn('RetainedPublicReviewImages(urls: item.imageUrls, reader: imageReader)', source)
        self.assertIn('if item.canReport, let writes, let page = itemPages[item.id]', source)
        self.assertIn('PublicMerchantReviewEditor(target: target, reportItem: item, page: page, context: writes)', source)
        self.assertIn('for item in result.items { itemPages[item.id] = page }', source)
        self.assertIn('items.append(contentsOf: result.items)', source)

    def test_empty_history_and_filtered_empty_are_distinct_and_do_not_gate_pagination(self):
        source = self.text('App/PublicMerchantReviewsView.swift')
        self.assertRegex(source, r'if items\.isEmpty \{\s*Text\("merchant.publicHome.noReviews"\)')
        self.assertRegex(source, r'else if visibleItems\.isEmpty \{\s*Text\("merchant.publicHome.noMatchingReviews"\)')
        self.assertIn('if snapshot.hasMore, failure == nil', source)
        self.assertIn('await load(page: snapshot.pageNum + 1)', source)
        self.assertIn('await load(page: failedPage)', source)
        self.assertNotIn('visibleItems.count', source)
        self.assertNotIn('items.count', source)

    def test_server_summary_eligibility_and_http_query_are_unchanged(self):
        view = self.text('App/PublicMerchantReviewsView.swift')
        self.assertIn('value: String(snapshot.total)', view)
        self.assertIn('if let rating = snapshot.averageRating', view)
        self.assertIn('if let writes, snapshot.eligibility.canCreate, let registration = snapshot.eligibility.registrationId', view)
        core = self.text('Core/PublicMerchantReviews.swift').split('public struct PublicMerchantReviewHTTPReader:')[1]
        self.assertEqual(re.findall(r'URLQueryItem\(name: "([^"]+)"', core), ['merchantRowId', 'pageNum', 'pageSize'])
        self.assertNotIn('PublicMerchantReviewFilter', core)
        self.assertNotIn('request.httpBody', core)

    def test_filters_reset_only_for_changed_target_scope_and_keep_existing_cancellation_fences(self):
        source = self.text('App/PublicMerchantReviewsView.swift')
        self.assertIn('let target: PublicMerchantReviewTarget; let scope: UUID', source)
        self.assertIn('.task(id: key) { await load(page: 1) }', source)
        self.assertIn('if loadedKey != current { reviewFilter = .all }', source)
        self.assertIn('if loadedKey == key, let snapshot', source)
        self.assertIn('if loading && loadedKey == key { return }', source)
        self.assertEqual(source.count('guard ticket == generation, current == key, !Task.isCancelled else { return }'), 3)
        self.assertIn('.onDisappear { generation += 1; loading = false }', source)
        self.assertNotIn('.onChange(of: reviewFilter)', source)

    def test_new_copy_is_bilingual_and_scope_is_honest(self):
        catalog = json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        keys = ['reviewFilter', 'reviewFilter.all', 'reviewFilter.low', 'reviewFilter.photos',
                'reviewFilterScope', 'clearReviewFilter', 'noMatchingReviews']
        for suffix in keys:
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(catalog['merchant.publicHome.' + suffix]['localizations'][locale]['stringUnit']['value'])
        scope = catalog['merchant.publicHome.reviewFilterScope']['localizations']['en']['stringUnit']['value']
        self.assertIn('loaded reviews', scope)
        self.assertIn('server results', scope)
        self.assertNotIn('merchant.publicHome.reviewFilter.pending', catalog)

    def test_authored_core_tests_cover_boundaries_loaded_pages_and_row_identity(self):
        source = self.text('Tests/CoreTests/PublicMerchantReviewFilterTests.swift')
        self.assertEqual(len(re.findall(r'\bfunc test\w+\(', source)), 7)
        for term in ['[1, 2, 3]', '[2, 21]', 'visible.map(\\.offset)', 'selected.imageUrls',
                     'selected.canReport', 'XCTAssertEqual(page, original)', 'XCTAssertNil(unknown.averageRating)']:
            self.assertIn(term, source)

    def test_fixture_is_opt_in_and_uses_real_public_reader_for_late_401(self):
        fixture = self.text('App/PublicMerchantReviewFilterFixtureView.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('PublicMerchantReviewHTTPReader', fixture)
        self.assertIn('return (Data(), 401)', fixture)
        self.assertIn('await withCheckedContinuation', fixture)
        self.assertNotIn('PublicMerchantReviewHTTPWriter', fixture)
        host = self.text('App/PublicMerchantHomeFixtureView.swift')
        self.assertIn('if scenario.hasPrefix("reviews-")', host)
        ui = self.text('Tests/AppUITests/PublicMerchantReviewFilterFlowTests.swift')
        self.assertEqual(len(re.findall(r'\bfunc test\w+\(', ui)), 5)
        for term in ['--public-merchant-home-fixture', 'reviews-late401', 'reviews-retry', 'reviews-empty',
                     'testPhotoCloseAndSameScopeDetailReturnKeepFilterWithoutGrantingActions', 'waitForReads(3, completed: 3, account: 9']:
            self.assertIn(term, ui)

if __name__ == '__main__':
    unittest.main()
