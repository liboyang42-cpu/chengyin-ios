"""Native UI source regressions only; requires Apple UI tests for runtime proof."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text()


class NativeUIAccessibilitySemanticsChecks(unittest.TestCase):
    def test_sound_switch_has_control_sized_frame_and_retains_transactional_storage(self):
        view = source('App/SettingsSupportSections.swift')
        toggle = view[view.index('private func soundToggle'):view.index('@MainActor struct SettingsUnavailableFeatureView')]
        for expected in ['Toggle(', '.labelsHidden()', '.toggleStyle(.switch)', '.fixedSize()',
                         '.accessibilityLabel(Text(LocalizedStringKey(key.titleKey)))',
                         '.disabled(model.state.isBusy)', 'await model.set(key, to: value)']:
            self.assertIn(expected, toggle)
        coordinator = source('Core/SettingsSoundPreferences.swift')
        self.assertLess(coordinator.index('try await store.write(next)'), coordinator.index('state.preferences = next'))
        tests = source('Tests/AppUITests/SettingsNativeFlowTests.swift')
        for expected in ['testFailedSaveKeepsPreviousValueAndNextTapCanSave',
                         'testSoundSixDefaultsSaveBackAndReopen',
                         'tapNativeSwitch(forest); expectSwitch(forest, value: "1")']:
            self.assertIn(expected, tests)

    def test_essential_legal_source_notice_uses_adaptive_primary_contrast(self):
        view = source('App/SettingsLegalDocumentView.swift')
        self.assertIn('Text("settingsNative.legal.sourceNotice").font(.footnote).foregroundStyle(.primary)', view)
        self.assertIn('}.font(.caption).foregroundStyle(.secondary)', view)

    def test_switch_taps_require_visible_frames_and_preserve_exact_outcomes(self):
        tests = source('Tests/AppUITests/SettingsNativeFlowTests.swift')
        for expected in ['frame.minY > top && frame.maxY < bottom',
                         'if frame.minY <= top { app.swipeDown() } else { app.swipeUp() }',
                         'coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))',
                         'XCTAssertTrue(element.isEnabled',
                         'reveal(app.staticTexts["settingsNative.sound.error"])',
                         'expectSwitch(sound, value: "1")', 'expectSwitch(sound, value: "0")',
                         'back(); open("settingsNative.openSound")']:
            self.assertIn(expected, tests)
        self.assertNotIn('sound.tap()', tests)
        self.assertNotIn('forest.tap()', tests)

    def test_report_receipt_exposes_exact_semantic_status(self):
        view = source('App/PublicMerchantReviewEditor.swift')
        self.assertIn('.accessibilityValue(Text(verbatim: receipt.status))', view)
        self.assertIn('.accessibilityIdentifier("merchant.publicHome.status")', view)
        tests = source('Tests/AppUITests/PublicMerchantHomeFlowTests.swift')
        self.assertIn('XCTAssertEqual(status.value as? String, "PENDING_PLATFORM_REVIEW"', tests)
        self.assertIn('XCTAssertFalse(app.buttons["merchant.publicHome.confirm"].exists)', tests)
        self.assertIn('XCTAssertFalse(app.staticTexts["merchant.publicHome.writeFailure"].exists)', tests)

    def test_square_save_verifies_new_draft_and_scrolls_back_to_local_status(self):
        tests = source('Tests/AppUITests/SquareWorkspaceFlowTests.swift')
        for expected in ['"--uitesting-reset-language"', '"-AppleLocale"',
                         'reveal(savedBody, in: app)',
                         'reveal(status, in: app, upwards: false)',
                         'XCTAssertEqual(status.label, "已保存在本机"',
                         'XCTAssertFalse(app.buttons["squareWorkspace.saveServer"].isEnabled)']:
            self.assertIn(expected, tests)

    def test_operating_market_has_separate_exact_accessible_value(self):
        view = source('App/SettingsAboutView.swift')
        self.assertIn('.accessibilityLabel(Text("region.market"))', view)
        self.assertIn('.accessibilityValue(Text(verbatim: market?.rawValue ?? "—"))', view)
        tests = source('Tests/AppUITests/SettingsNativeFlowTests.swift')
        self.assertIn('XCTAssertEqual(market.value as? String, "US")', tests)
        self.assertIn('XCTAssertFalse(app.staticTexts["settingsNative.legal.sourceNotice"].exists)', tests)

    def test_growth_asserts_values_instead_of_unrelated_bare_text(self):
        view = source('App/GrowthCenterView.swift')
        self.assertIn('.accessibilityValue(pointsValue(board.me.score))', view)
        self.assertIn('.accessibilityValue(rankValue(board.me.rank))', view)
        self.assertIn('return Text("growth.unknownValue")', view)
        self.assertIn('return Text("growth.unranked")', view)
        tests = source('Tests/AppUITests/GrowthCenterFlowTests.swift')
        self.assertIn('XCTAssertEqual(points.value as? String, value)', tests)
        self.assertIn('XCTAssertEqual(rank.value as? String, "Not ranked yet")', tests)
        self.assertEqual(tests.count('expectPoints("640")'), 3)

    def test_object_menu_keeps_native_action_and_asserts_category_translation(self):
        view = source('App/ObjectCardViews.swift')
        self.assertIn('Menu {', view)
        self.assertIn('.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)', view)
        self.assertIn('await model.load(category: category, reader: reader)', view)
        tests = source('Tests/AppUITests/ObjectCardFlowTests.swift')
        self.assertIn('app.descendants(matching: .any)["objects.filter"].firstMatch', tests)
        self.assertIn('XCTAssertEqual(category.label, label)', tests)
        for category in ['selectCategory(5, label: "Books and stationery")',
                         'selectCategory(4, label: "Food and drinks")']:
            self.assertIn(category, tests)

    def test_report_action_identity_and_navigation_survive_parent_disappearance(self):
        reviews = source('App/PublicMerchantReviewsView.swift')
        self.assertNotIn('}.accessibilityIdentifier("merchant.publicHome.review.', reviews)
        self.assertIn('.accessibilityIdentifier("merchant.publicHome.report.\\(item.id)")', reviews)
        self.assertIn('if loadedKey == key, let snapshot', reviews)
        self.assertIn('current == key, !Task.isCancelled', reviews)
        self.assertIn('.onDisappear { generation += 1; loading = false }', reviews)
        home = source('App/PublicMerchantHomeView.swift')
        self.assertIn('else if loading || loadedKey != key', home)
        self.assertIn('snapshot == key, !Task.isCancelled', home)
        self.assertIn('.onDisappear { generation += 1; loading = false }', home)
        tests = source('Tests/AppUITests/PublicMerchantHomeFlowTests.swift')
        self.assertIn('"merchant.publicHome.confirm"', tests)
        self.assertIn('"PENDING_PLATFORM_REVIEW"', tests)

    def test_home_feed_reveals_activation_point_and_keeps_exact_typed_destination(self):
        tests = source('Tests/AppUITests/HomeFeedFlowTests.swift')
        self.assertIn('element.frame.midY > top + 12', tests)
        self.assertIn('element.frame.midY < app.frame.maxY - 80', tests)
        self.assertIn('XCTAssertEqual(app.staticTexts["homeFeed.destination.activity"].label, "Synthetic activity destination 7")', tests)
        self.assertIn('"Currency not provided"', tests)
        self.assertIn('XCTAssertFalse(app.buttons["Buy"].exists)', tests)
