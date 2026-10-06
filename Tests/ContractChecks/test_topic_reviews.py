"""Topic review projection/source wiring only; not Apple runtime acceptance."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TopicReviewChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_summary_uses_loaded_detail_and_keeps_existing_composer_and_scope(self):
        model = self.read('Core/TopicContracts.swift')
        self.assertIn('public let reviews: TopicReviews', model)
        self.assertIn('reviews = try TopicReviews(from: decoder)', model)
        view = self.read('App/TopicDetailView.swift')
        self.assertEqual(view.count('TopicReviewsContent(reviews: value.reviews)'), 1)
        self.assertLess(view.index('Section("topic.comments")'), view.index('TopicReviewsContent('))
        self.assertIn('Button("context.review.title") { showsReview = true }', view)
        self.assertIn('ContextualReviewComposer(target: .topic(id)', view)
        self.assertNotIn('if value.comments.isEmpty', view)
        self.assertNotIn('if let rating = value.averageRating', view)
        for token in ['detail = nil; issue = nil; loadedKey = nil',
                      'guard operation == generation, captured == key, !Task.isCancelled else { return }',
                      'else if loading || loadedKey != key',
                      '.task(id: key)', '.onDisappear { loads.cancel(); generation += 1; loading = false }',
                      'if value.showStoryPaywall', 'ForEach(Array(value.chapters.enumerated())']:
            self.assertIn(token, view)

    def test_bounded_preview_is_not_total_rating_or_authority(self):
        model = self.read('Core/TopicReviews.swift')
        for token in ['case averageRating, commentCount, commentList',
                      'guard preview.count <= 5 else { throw APIError.malformedResponse }',
                      'commentCount == 0 && preview.isEmpty',
                      '$0.isFinite && (0...5).contains($0)',
                      '(1...5).contains($0)',
                      'case memberNickname, createTime, rating, contents']:
            self.assertIn(token, model)
        for token in ['commentCount = preview.count', 'reduce(', 'memberId', 'ownerId', '/api/',
                      'URLSession', 'token', 'phone', 'chaptersList', 'isSignUp', 'isOwner']:
            self.assertNotIn(token, model)

    def test_unknown_empty_and_plain_text_are_accessible_and_bilingual(self):
        view = self.read('App/TopicReviewsContent.swift')
        for token in ['if !reviews.hasConfirmedNoReviews', 'if let average = reviews.averageRating',
                      'if let count = reviews.commentCount', 'if reviews.preview.isEmpty',
                      'Text("topic.reviews.previewUnavailable")', 'Text("topic.reviews.empty")',
                      'Text(verbatim: contents)', 'Text(verbatim: name)', 'Text(verbatim: date)',
                      'ForEach(Array(reviews.preview.enumerated()), id: \\.offset)',
                      '.textSelection(.enabled)', '.fixedSize(horizontal: false, vertical: true)']:
            self.assertIn(token, view)
        for token in ['Button', 'NavigationLink', 'URLSession', '.task(', '@State', '.lineLimit(',
                      'Image(', 'AsyncImage', 'https://']:
            self.assertNotIn(token, view)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for suffix in ['average', 'total', 'rating', 'ratingUnknown', 'countUnknown',
                       'empty', 'previewUnavailable', 'previewHint', 'authorUnknown', 'textUnavailable']:
            self.assertEqual(set(catalog['topic.reviews.' + suffix]['localizations']), {'en', 'zh-Hans'})

    def test_unknown_rating_uses_exact_unique_native_combined_label(self):
        ui = self.read('Tests/AppUITests/TopicFlowTests.swift')
        method = ui.split('func testReviewSummaryKeepsServerTotalAcrossDifferentRoutesAndReopen()')[1].split('func testKnownEmptyTopicReviews')[0]
        self.assertIn('revealReview("topic.reviews.rating.1")', method)
        self.assertIn('matching(identifier: "topic.reviews.rating.1").count, 1', method)
        self.assertIn('XCTAssertEqual(unavailableRating.label, "Rating, Rating unavailable"', method)
        self.assertNotIn('revealReview("topic.reviews.ratingUnknown.1")', method)
        self.assertEqual(method.count('"Total reviews, 12"'), 2)
        for value in ['"Total reviews, 3"', '"Average rating, 4.2 / 5"', '"A different route review."', 'XCTAssertFalse(app.staticTexts["A useful route review."].exists)']:
            self.assertIn(value, method)

    def test_domain_and_ui_coverage_is_authored(self):
        tests = self.read('Tests/CoreTests/TopicReviewsTests.swift')
        for token in ['testReadsServerScoreAndTotalSeparatelyFromPreview',
                      'testMissingAndNullMetadataStayUnknown', 'testKnownZeroIsDistinctFromAnUnavailablePreview',
                      'testRatingsAndCountsAreValidatedWithoutCoercionOrClamping',
                      'testMalformedListsAndRowsCannotBecomeEmptySuccess',
                      'testPreviewIsBoundedToFiveRowsWithoutDeduplicatingUnnamedReviews',
                      'testBlankDisplayFieldsStayUnavailableAndRealTextIsPreserved',
                      'testReviewsCannotProvideStoryUnlockOrPublisherAuthority']:
            self.assertIn(token, tests)
        ui = self.read('Tests/AppUITests/TopicFlowTests.swift')
        for token in ['testReviewSummaryKeepsServerTotalAcrossDifferentRoutesAndReopen',
                      'testKnownEmptyTopicReviewsUseChineseEmptyStateWithoutZeroStars',
                      'testMissingTopicReviewMetadataStaysUnknownWithoutFalseEmpty']:
            self.assertIn(token, ui)
        fixture = self.read('App/TopicFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('reviews, reviewsEmpty, reviewsUnknown', fixture)
        self.assertNotIn('https://', fixture)


if __name__ == '__main__':
    unittest.main()
