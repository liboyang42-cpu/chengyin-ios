"""Source-only UI52 regression and negative mutations; no Swift runtime claim."""
from pathlib import Path
import json
import re
import tempfile
import unittest

from tools import run138_ui52_driver_inverse as driver

ROOT = Path(__file__).resolve().parents[2]


class UI52DriverCandidateTests(unittest.TestCase):
    def setUp(self):
        self.c = driver.contract(ROOT)

    def current(self, relative):
        return (ROOT / relative).read_bytes()

    def original(self, relative):
        return driver.original_source(relative, self.current(relative), ROOT)

    def test_isolated_candidate_and_all_protected_original_bytes(self):
        result = driver.validate_current(ROOT)
        self.assertEqual(result["new_wait_allowance_seconds"], 35)

    def test_both_whole_files_restore_to_exact_published_preimages(self):
        for relative, row in self.c["files"].items():
            restored = self.original(relative)
            self.assertEqual(driver.digest(restored), row["before_sha256"])
            current = self.current(relative).decode()
            for hunk in reversed(row["hunks"]):
                self.assertEqual(current.count(hunk["after"]), 1)
                current = current.replace(hunk["after"], hunk["before"], 1)
            self.assertEqual(current.encode(), restored)

    def test_non_test_helpers_and_other_methods_are_byte_identical(self):
        approved = {
            driver.MARKETING: "testNormalMerchantWorkbenchOpensDormantMarketingInBothLanguages",
            driver.STORY: "testChosenStoryImageAppliesOnlyAfterUploadAndRestoresIntoExactPreparedOrder",
        }
        for relative, method in approved.items():
            pattern = r"(?m)^    func " + re.escape(method) + r"\b[\s\S]*?^    }"
            before = self.original(relative).decode()
            after = self.current(relative).decode()
            self.assertEqual(len(re.findall(pattern, before)), 1)
            self.assertEqual(len(re.findall(pattern, after)), 1)
            self.assertEqual(re.sub(pattern, "", before), re.sub(pattern, "", after))

    def test_marketing_verifies_selected_value_title_and_closed_menu_after_single_tap(self):
        hunk = self.c["files"][driver.MARKETING]["hunks"][0]
        text = hunk["after"]
        self.assertTrue(text.startswith('                options.element(boundBy: options.count - 1).tap()'))
        for required in ("picker.label == expectedPickerLabel",
                         '(picker.value as? String) == section',
                         "picker.isHittable", "app.navigationBars[section].exists",
                         "!app.menus.firstMatch.exists",
                         'language == "en" ? "Section" : "栏目"',
                         '"MARKETING_SECTION_TRANSITION expected='):
            self.assertIn(required, text)
        self.assertLess(text.index("selectionSettled"), text.index('app.staticTexts["merchantMarketing.error"]'))
        self.assertEqual(text.count(".tap()"), hunk["before"].count(".tap()"))
        current = self.current(driver.MARKETING).decode()
        self.assertIn('for language in ["en", "zh-Hans"]', current)
        self.assertIn('["Shop insights", "Entitlements", "Prediction inbox"]', current)
        self.assertIn('["店铺参谋", "付费权益", "竞猜待答"]', current)

    def test_story_barrier_only_second_apply_and_original_back_bytes(self):
        old = self.original(driver.STORY).decode()
        text = self.current(driver.STORY).decode()
        first = 'tap("projectStoryImage.apply", app); XCTAssertFalse(app.buttons["projectStoryImage.close"].exists); back(app)'
        self.assertEqual(old.count(first), 1)
        self.assertEqual(text.count(first), 1)
        helper = lambda s: s.split("    private func back(", 1)[1].split("    // UNMEASURED", 1)[0]
        self.assertEqual(helper(old), helper(text))
        new = self.c["files"][driver.STORY]["hunks"][0]["after"]
        for required in ('!app.buttons["projectStoryImage.close"].exists',
                         'app.navigationBars["Chapter"].buttons["BackButton"]',
                         "chapterBack.exists && chapterBack.isEnabled && chapterBack.isHittable"):
            self.assertIn(required, new)
        self.assertTrue(new.endswith("        back(app); saved = try inspect(app)"))
        self.assertEqual(text.count("let replacementDismissed ="), 1)

    def test_exactly_one_new_five_second_wait_per_source_no_existing_wait_inflation(self):
        for relative in self.c["files"]:
            before = self.original(relative).decode()
            current = self.current(relative).decode()
            self.assertEqual(current.count("timeout: 5"), before.count("timeout: 5") + 1)
            self.assertEqual(current.count(".tap()"), before.count(".tap()"))
            for hunk in self.c["files"][relative]["hunks"]:
                self.assertNotIn("sleep(", hunk["after"])
                self.assertNotIn("coordinate(", hunk["after"])
                self.assertNotIn("try?", hunk["after"])
                self.assertNotIn("continueAfterFailure", hunk["after"])
                self.assertNotIn("while ", hunk["after"])

    def test_exact_full_method_costs_and_explicit_current_only_905_exception(self):
        costs = driver.validate_costs(ROOT)
        marketing = next(row for key, row in costs.items() if key.startswith("MerchantMarketing"))
        story = next(row for key, row in costs.items() if key.startswith("ProjectStoryImage"))
        self.assertEqual(marketing["candidate_complete_method_seconds"], 114.954 + 2 * 3 * 5)
        self.assertEqual(story["candidate_complete_method_seconds"], 900 + 5)
        self.assertTrue(story["requires_explicit_over_900_review"])
        profile = json.loads((ROOT / "tools/ui_duration_weights.json").read_text())
        key = next(key for key in costs if key.startswith("ProjectStoryImage"))
        self.assertEqual(profile["estimated_method_seconds"][key], 900)

    def test_changed_original_assertion_is_rejected(self):
        raw = self.current(driver.STORY)
        mutated = raw.replace(b"XCTAssertEqual(saved.storyImageUploadCount, 2)",
                              b"XCTAssertEqual(saved.storyImageUploadCount, 1)", 1)
        self.assertNotEqual(raw, mutated)
        with self.assertRaises(ValueError):
            driver.original_source(driver.STORY, mutated, ROOT)

    def test_extra_wait_or_repeated_barrier_is_rejected(self):
        raw = self.current(driver.STORY)
        for mutated in (raw.replace(b"timeout: 5", b"timeout: 10", 1),
                        raw + self.c["files"][driver.STORY]["hunks"][0]["after"].encode()):
            with self.assertRaises(ValueError):
                driver.original_source(driver.STORY, mutated, ROOT)

    def test_missing_barrier_and_preimage_cannot_masquerade_as_current(self):
        for relative in self.c["files"]:
            with self.assertRaises(ValueError):
                driver.original_source(relative, self.original(relative), ROOT)

    def test_unknown_path_is_rejected(self):
        with self.assertRaises(ValueError):
            driver.original_source("Tests/AppUITests/Unapproved.swift", b"", ROOT)

    def test_mutated_inverse_contract_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / driver.CONTRACT_PATH
            target.parent.mkdir(parents=True)
            target.write_bytes((ROOT / driver.CONTRACT_PATH).read_bytes() + b" ")
            with self.assertRaises(ValueError):
                driver.contract(Path(folder))


if __name__ == "__main__":
    unittest.main()

