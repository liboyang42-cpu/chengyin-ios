"""Structural/source boundaries; not Apple compiler or runtime evidence."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantReviewLoadedPagesChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_accumulator_is_read_only_and_separate_from_mutation_authority(self):
        core = self.read('Core/MerchantReviewLoadedPages.swift')
        for forbidden in ['execute(', 'prepare(', 'reserve(', 'complete(', 'FileManager', 'UserDefaults', 'confirmation', 'token:']:
            self.assertNotIn(forbidden, core)
        for required in ['next == page + 1', 'sourcePages[row.id] = next', 'rows.contains(row)', 'self.access == access', 'self.scope == scope', 'self.authorizationGeneration == authorizationGeneration']:
            self.assertIn(required, core)

    def test_original_page_is_fetched_in_separate_bound_host(self):
        app = self.read('App/MerchantBusinessViews.swift')
        self.assertIn('snapshot.document.rows.contains(row)', app)
        self.assertIn('MerchantBusinessPage(reader: reader, journal: journal, query: destination.query, reviewSource: destination)', app)
        self.assertIn('reviewSource?.matches(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration, snapshot: snapshot)', app)
        self.assertIn('String(id.rawValue) == reviewSource.reviewID', app)
        self.assertIn('guard sourcePageCanPrepare(mutation)', app)
        self.assertIn('if sourcePageCanPrepare(mutation) { model.prepare(mutation) }', app)
        self.assertIn('merchant.business.reviews.sourcePageMissing', app)
        self.assertIn('reviewSourceDestination = nil; selection = []; model.invalidate()', app)

    def test_load_more_is_independent_of_existing_page_navigation(self):
        app = self.read('App/MerchantBusinessViews.swift')
        for value in ['func loadMoreReviews()', 'appendReviews: true', 'if !appendReviews { reviewLoadedPages = nil }', 'Button("merchant.business.reviews.loadMore")', 'Button("merchant.business.next")', 'Button("merchant.business.previous")']:
            self.assertIn(value, app)
        self.assertIn('guard generation == loadGeneration else { return }', app)
        self.assertIn('scope == coordinator.reader.scope, authorization == coordinator.reader.authorizationGeneration', app)
        self.assertIn('reviewLoadedPages = nil; coordinator.invalidate()', app)

    def test_catalog_has_exact_bilingual_scope_and_source_page_messages(self):
        fragment = json.loads(self.read('Resources/MerchantBusinessLocalizations.fragment.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for suffix in ['filterScope', 'loadMore', 'reloadSourcePage', 'sourcePageNotice', 'sourcePageMissing']:
            key = 'merchant.business.reviews.' + suffix
            self.assertEqual(fragment[key], catalog[key])
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(fragment[key]['localizations'][locale]['stringUnit']['value'])
        self.assertIn('Next and Previous replace', fragment['merchant.business.reviews.filterScope']['localizations']['en']['stringUnit']['value'])

    def test_boundary_tests_cover_races_missing_target_and_unknown_intent(self):
        app = self.read('Tests/AppUnitTests/MerchantBusinessListModelTests.swift')
        core = self.read('Tests/CoreTests/MerchantReviewLoadedPagesTests.swift')
        for name in ['testReviewCancelledAppendCannotRestoreAccumulation', 'testReviewAuthorizationChangeDuringAppendDiscardsAllRows', 'testReviewRefreshDuringSuspendedAppendFencesOlderGeneration', 'testReviewRepeatedLoadMoreWhileBusyDoesNotReadOrAppendTwice', 'testReviewScopeChangeDuringAppendClearsOldAccountRows', 'testReviewMerchantAndPermissionChangesRejectAppend', 'testReviewOriginalPageUsesSeparateFreshCoordinatorAndKeepsUnknownJournal']:
            self.assertIn('func ' + name, app)
        self.assertIn('testMissingOriginalTargetNeverGainsAuthorityFromRetainedRow', core)
        self.assertIn('testAccumulatedRowNeverAuthorizesMutationAgainstLaterPage', core)
        self.assertIn('testDuplicateIdentityUpdatesInPlaceAndUsesLatestSourcePage', core)

    def test_existing_ui_baseline_is_unchanged(self):
        path = ROOT / 'Tests/AppUITests/MerchantBusinessFlowTests.swift'
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), '6f7abf0f8348ef9c53137270d0fdb3150a5e1cefb625710a218aa4b5c4aa305c')

if __name__ == '__main__':
    unittest.main()
