"""Supplementary source/catalog checks; Apple execution is a separate gate."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class RetainedImageLocalizationTests(unittest.TestCase):
    def test_production_review_paths_use_catalog_interpolation(self):
        for filename in ["RetainedImageSelectionView.swift", "MerchantGalleryBatchView.swift"]:
            source = (ROOT / "App" / filename).read_text()
            self.assertIn(r'Text("image.retained.byteCount \(review.selection.jpeg.count)")', source)
            self.assertNotIn(r'Text("\(review.selection.jpeg.count) bytes")', source)
            self.assertIn('Text(verbatim: review.scope.realm)', source)

    def test_byte_count_is_bilingual_and_fragment_matches_shipped_catalog(self):
        catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        fragment = json.loads((ROOT / "Resources/RetainedImagesLocalizations.fragment.json").read_text())["strings"]
        key = "image.retained.byteCount %lld"
        self.assertEqual(catalog[key], fragment[key])
        for language, expected in [("en", "Upload size (bytes): %lld"), ("zh-Hans", "上传大小（字节）：%lld")]:
            unit = catalog[key]["localizations"][language]["stringUnit"]
            self.assertEqual(unit, {"state": "translated", "value": expected})
            for count in [0, 1, 2, 1024]:
                self.assertIn(str(count), unit["value"].replace("%lld", str(count)))

    def test_batch_counts_use_count_neutral_english_and_matching_placeholders(self):
        strings = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        for key, expected in [("image.galleryBatch.remaining %lld", "Images remaining: %lld"),
                              ("image.galleryBatch.applied %lld", "Images added to local draft: %lld")]:
            self.assertEqual(strings[key]["localizations"]["en"]["stringUnit"]["value"], expected)
            for language in ["en", "zh-Hans"]:
                self.assertEqual(strings[key]["localizations"][language]["stringUnit"]["value"].count("%lld"), 1)

    def test_ui_regression_preserves_explicit_preference_across_relaunch(self):
        source = (ROOT / "Tests/AppUITests/RetainedImageUITests.swift").read_text()
        self.assertIn('let systemLanguage = language == "en" ? "zh-Hans" : "en"', source)
        self.assertIn('app.launchArguments = ["--retained-images-fixture", "success"] + arguments', source)
        self.assertIn('count.label.hasPrefix(prefix)', source)
        self.assertIn('XCTAssertEqual(app.staticTexts["region.market.value"].label, "US")', source)
