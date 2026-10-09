"""Native structural guards only. Swift/XCTest behavior is verified separately on Apple CI."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantListToolsTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_loaded_aftercare_scope_and_empty_clear_states_are_bilingual(self):
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        fragment = json.loads(self.read('Resources/MerchantBusinessLocalizations.fragment.json'))
        keys = ['aftercare.search', 'aftercare.searchScope', 'aftercare.clearSearch', 'aftercare.loadMore', 'aftercare.noMatches',
                'reviews.filter', 'reviews.filter.all', 'reviews.filter.pending',
                'reviews.filter.low', 'reviews.filter.photos', 'reviews.filterScope',
                'reviews.clearFilter', 'reviews.summaryScope', 'list.noMatches',
                'field.pendingReplyCount', 'field.monthNewCount', 'field.replyRatePct',
                'field.customerNickname', 'field.activityTitle']
        for suffix in keys:
            key = 'merchant.business.' + suffix
            self.assertEqual(catalog[key], fragment[key])
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][locale]['stringUnit']['value'].strip())
        self.assertIn('across loaded pages in this status', catalog['merchant.business.aftercare.searchScope']['localizations']['en']['stringUnit']['value'])
        self.assertNotIn('30', catalog['merchant.business.field.averageRating']['localizations']['en']['stringUnit']['value'])

    def test_filters_are_presentation_only_and_pagination_is_unfiltered(self):
        app = self.read('App/MerchantBusinessViews.swift')
        core = self.read('Core/MerchantBusinessDocuments.swift')
        query = self.read('Core/MerchantBusinessQuery.swift')
        self.assertIn('model.visibleRows(in: section, query: document.query)', app)
        self.assertIn('snapshot.document.hasMore || query.page > 1', app)
        self.assertIn('.disabled(!snapshot.document.hasMore)', app)
        for binding in ['$model.listFilters.review', '$model.listFilters.aftercareKeyword']:
            self.assertIn(binding, app)
        filters = core.split('public struct MerchantBusinessListFilters')[1].split('public struct MerchantBusinessDocument')[0]
        self.assertNotIn('request(', filters)
        self.assertNotIn('summary', filters)
        self.assertIn('case .aftercare(let bucket, _): return .query("api/merchant/aftercare/list", ["bucket": bucket.rawValue, "pageNum": String(page), "pageSize": "20"])', query)
        self.assertIn('case .reviews: return .query("api/merchant/reviews/manage", ["pageNum": String(page), "pageSize": "20"])', query)

    def test_accumulation_is_read_only_and_generation_fenced(self):
        app = self.read('App/MerchantBusinessViews.swift')
        core = self.read('Core/MerchantBusinessDocuments.swift')
        self.assertIn('guard generation == loadGeneration else { return }', app)
        self.assertIn('authorization == coordinator.reader.authorizationGeneration', app)
        self.assertIn('if !appendAftercare { aftercareLoadedPages = nil }', app)
        self.assertIn('query = requested.paged(1)', app)
        self.assertIn('aftercareLoadedPages = nil; reviewLoadedPages = nil; coordinator.invalidate()', app)
        self.assertIn('pages.matches(scope:', app)
        self.assertIn('try pages.append(snapshot, scope:', app)
        self.assertIn('self.bucket == bucket, hasMore, page == self.page + 1', core)
        self.assertIn('self.access == access', core)
        accumulator = core.split('public struct MerchantAftercareLoadedPages')[1].split('public struct MerchantBusinessDocument')[0]
        for forbidden in ['execute(', 'prepare(', 'reserve(', 'complete(', 'UserDefaults', 'FileManager']:
            self.assertNotIn(forbidden, accumulator)
        self.assertIn('Button("merchant.business.aftercare.loadMore")', app)
        self.assertIn('case .refund: return (Int(id).flatMap { try? MerchantRefundID($0) }).map(MerchantBusinessQuery.refund)', core)

    def test_metrics_are_server_values_and_unknown_is_not_zero(self):
        core = self.read('Core/MerchantBusinessDocuments.swift')
        self.assertIn('let value = object[key] ?? .null', core)
        self.assertIn('summary[key] = value', core)
        self.assertIn('key != "replyRatePct" || count <= 100', core)
        fields = self.read('App/MerchantBusinessRecordViews.swift')
        self.assertIn('else if value == .null', fields)
        self.assertIn('else if key == "replyRatePct" { Text("\\(raw)%")', fields)

    def test_scope_and_merchant_identity_clear_local_filters(self):
        app = self.read('App/MerchantBusinessViews.swift')
        self.assertIn('private var filterMerchantID: Int?', app)
        self.assertIn('if filterScope != coordinator.reader.scope { listFilters = .init(); filterMerchantID = nil }', app)
        self.assertIn('if let filterMerchantID, filterMerchantID != currentMerchant { listFilters = .init() }', app)
        self.assertIn('coordinator.invalidate(); listFilters = .init(); filterScope = nil; filterMerchantID = nil', app)

    def test_ui_exercises_features_and_fixtures_remain_opt_in(self):
        ui = self.read('Tests/AppUITests/MerchantBusinessFlowTests.swift')
        for name in ['testReviewFiltersUseCurrentPageAndKeepServerMetrics', 'testChineseAftercareSearchSpansLoadedPages']:
            self.assertEqual(ui.count('func ' + name), 1)
        self.assertIn('let app = launch("listTools", language: "zh-Hans")', ui)
        fixture = self.read('App/MerchantBusinessFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('scenario == .listTools', fixture)
        self.assertIn('--uitesting-merchant-business-scenario', fixture)
        model_tests = self.read('Tests/AppUnitTests/MerchantBusinessListModelTests.swift')
        for name in ['testMerchantChangeAfterFailedLoadStillClearsPriorMerchantFilter',
                     'testOlderLoadCannotRestoreMerchantRowsOrOverwriteNewFilter',
                     'testInvalidationClearsFiltersAndDataButPreservesUnknownIntent']:
            self.assertIn('func ' + name, model_tests)

if __name__ == '__main__':
    unittest.main()
