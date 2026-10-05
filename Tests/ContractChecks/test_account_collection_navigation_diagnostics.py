"""Diagnostic-only contract; not proof that the Apple navigation failure is fixed."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AccountCollectionNavigationDiagnosticChecks(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "Tests/AppUITests/AccountCollectionFlowTests.swift").read_text()

    def test_original_single_tap_and_wait_budgets_remain(self):
        helper = self.source.split("private func open(", 1)[1].split("// This module", 1)[0]
        self.assertEqual(helper.count("button.tap()"), 1)
        self.assertIn("button.waitForExistence(timeout: 10)", helper)
        self.assertLess(helper.index('"before single tap"'), helper.index("button.tap()"))
        self.assertLess(helper.index("button.tap()"), helper.index('"after single tap"'))
        self.assertNotIn("for ", helper)
        self.assertNotIn("sleep", helper)
        wait = self.source.split("private func assertChineseNavigation", 1)[1].split("private func reveal", 1)[0]
        self.assertEqual(wait.count("waitForExistence(timeout: 5)"), 1)
        self.assertIn("XCTAssertTrue(arrived, file: file, line: line)", wait)

    def test_original_chinese_destinations_and_back_navigation_remain(self):
        case = self.source.split("func testChineseFavoritesAndCouponNavigation()", 1)[1].split("func testLargeType", 1)[0]
        self.assertIn('launch(language: "zh-Hans")', case)
        for title in ["我的收藏", "我的优惠券", "优惠券详情"]:
            self.assertIn('assertChineseNavigation("' + title + '")', case)
        self.assertIn('app.navigationBars["我的收藏"].buttons.firstMatch.tap()', case)
        for target in ["accountCollection.openFavorites", "accountCollection.openCoupons", "accountCollection.coupon.701"]:
            self.assertIn('open("' + target + '", diagnoseNavigation: true)', case)
        self.assertNotIn("XCTSkip", case)

    def test_scoped_synthetic_logs_survive_image_only_export(self):
        logger = self.source.split("private func logNavigationBoundary", 1)[1].split("private func assertChineseNavigation", 1)[0]
        for field in ["identifier=", "type=", "exists=", "enabled=", "hittable=", "frame="]:
            self.assertIn(field, logger)
        self.assertIn('if exists { print("ACCOUNT_COLLECTION_TARGET_AX " + target.debugDescription) }', logger)
        self.assertIn('app.navigationBars.debugDescription', logger)
        self.assertNotIn('app.debugDescription', logger)
        self.assertNotIn('target.identifier', logger)
        self.assertIn('diagnoseNavigation: Bool = false', self.source)
        self.assertIn('attachFailureScreenshot(self, app: app)', self.source)

    def test_post_tap_diagnostics_never_resolve_the_departed_source_element(self):
        logger = self.source.split("private func logNavigationBoundary", 1)[1].split("private func assertChineseNavigation", 1)[0]
        guard = logger.split('if phase == "after single tap" {', 1)[1].split('\n        }', 1)[0]
        self.assertIn('targetLookup=omitted-after-navigation', guard)
        self.assertIn('app.navigationBars.debugDescription', guard)
        self.assertIn('return', guard)
        self.assertNotIn('target.', guard)
        self.assertLess(logger.index('return'), logger.index('let exists = target.exists'))
