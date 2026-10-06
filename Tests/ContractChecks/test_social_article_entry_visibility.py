"""Source guards for the one clipped Social article reopen journey; Apple remains required."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SocialArticleEntryVisibilityChecks(unittest.TestCase):
    def test_both_exact_article_taps_require_unique_enabled_complete_rows(self):
        source = (ROOT / 'Tests/AppUITests/SocialAccountFlowTests.swift').read_text()
        method = source.split('func testHTMLArticleIsReadableInertAndReopensAfterBack()')[1].split('func testChineseLargeTextArticleReplacesOldContentAfterAccountSwitch()')[0]
        self.assertEqual(method.count('app.buttons.matching(identifier: "social.information.91").count, 1'), 2)
        self.assertEqual(method.count('revealFixtureElement(row, in: app)'), 2)
        self.assertEqual(method.count('XCTAssertTrue(row.isEnabled'), 2)
        self.assertEqual(method.count('row.tap()'), 2)
        self.assertNotIn('reveal(row)', method)
        self.assertEqual(method.count('Synthetic article heading'), 2)
        for exact in ['Readable bold text & 中文.', 'First instruction', 'Second instruction',
                      'Inert article link', 'XCTAssertEqual(app.webViews.count, 0)',
                      'XCTAssertFalse(app.links["Inert article link"].exists)',
                      'FORBIDDEN_SCRIPT_TEXT', '<h2>', 'social.article.limited',
                      'app.navigationBars.buttons["Play guide"].tap()']:
            self.assertIn(exact, method)

    def test_existing_viewport_helper_keeps_its_full_visibility_and_overlay_guards(self):
        helper = (ROOT / 'Tests/AppUITests/FailureScreenshot.swift').read_text().split('func revealFixtureElement(')[1].split('func tapFixtureNativeSwitch(')[0]
        for exact in ['frame.minY >= bounds.minY', 'frame.maxY <= bounds.maxY',
                      'navigationBar.frame.maxY + 4', 'app.frame.maxY - 40',
                      'toolbar.frame.minY - 4', 'keyboard.frame.minY - 4',
                      'element.isHittable', 'attempt < maximumSwipes']:
            self.assertIn(exact, helper)


if __name__ == '__main__':
    unittest.main()
