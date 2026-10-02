"""Run-49 source-level UI regressions; not Apple compiler/runtime evidence."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text()


class OfficialPreferenceUIRegressions(unittest.TestCase):
    def test_official_read_lifecycle_owns_stable_container_and_scope_fences(self):
        text = source('App/OfficialEventComponents.swift')
        screen = text[text.index('@MainActor struct OfficialReadScreen'):text.index('struct OfficialReadOnlyNotice')]
        self.assertIn('ZStack(alignment: .topLeading)', screen)
        self.assertNotIn('        Group {', screen)
        for required in ['.task(id: key)', '.onDisappear { generation &+= 1; loading = false }',
                         'loadedKey != key || loading', 'generation == operation, key == captured',
                         'if isPrivate && !reader.isAuthenticated', '!(error is CancellationError)']:
            self.assertIn(required, screen)
        tests = source('Tests/AppUITests/OfficialEventFlowTests.swift')
        self.assertIn('XCTAssertFalse(app.buttons["official.event.71"].exists)\n        retry.tap()', tests)

    def test_official_browser_does_not_override_search_and_retry_identity(self):
        text = source('App/OfficialEventsBrowserView.swift')
        self.assertNotIn('.accessibilityIdentifier("official.browser")', text)
        for leaf in ['official.search', 'official.filter', 'official.more']:
            self.assertIn(f'.accessibilityIdentifier("{leaf}")', text)
        self.assertIn('privateList ? "" : keyword', text)
        self.assertIn('canPublish && publisherScope == reader.scope', text)

    def test_official_price_assertion_is_exact_semantic_unknown_value(self):
        text = source('App/OfficialEventDetailView.swift')
        for required in ['.accessibilityLabel(Text("official.price"))',
                         '.accessibilityValue(Text("official.priceNotProvided"))',
                         '.accessibilityIdentifier("official.price")']:
            self.assertIn(required, text)
        tests = source('Tests/AppUITests/OfficialEventFlowTests.swift')
        self.assertEqual(tests.count('        expectUnspecifiedPrice()'), 2)
        self.assertIn('XCTAssertEqual(price.value as? String, "Price not provided by the source")', tests)
        self.assertIn('XCTAssertFalse(app.staticTexts["Free"].exists)', tests)
        self.assertIn('XCTAssertFalse(app.buttons["Sign up"].exists)', tests)

    def test_preference_and_summary_leaf_identifiers_keep_runtime_guards(self):
        runtime = source('App/PlayExperienceView.swift')
        self.assertIn('if let preference, node.validationMethod == 6', runtime)
        self.assertIn('if let topicID = model.snapshot?.result.topicID, let factory = summaryModel', runtime)
        self.assertIn('.accessibilityIdentifier("playx.preference.open")', runtime)
        self.assertIn('.accessibilityIdentifier("playx.os.open")', runtime)
        views = source('App/PlayPreferenceViews.swift')
        self.assertIn('.privacySensitive().navigationTitle("playx.os.title")', views)
        self.assertIn('.accessibilityIdentifier("playx.os.tag.\\(tag.id)")', views)
        self.assertIn('else { Button("playx.os.revoke", role: .destructive)', views)
        self.assertIn('.disabled(model.phase != "ready")', views)

    def test_preference_ui_reveals_lazy_rows_and_asserts_exact_content(self):
        tests = source('Tests/AppUITests/PlayPreferenceFlowTests.swift')
        for required in ['continueAfterFailure = false', 'attachFailureScreenshot',
                         'reveal(link); XCTAssertEqual(link.label, "Preference questionnaire")',
                         'reveal(tag); XCTAssertEqual(tag.label, "Synthetic tag")',
                         'XCTAssertEqual(privacy.label, "Private build. Only visible to you.")',
                         'app.descendants(matching: .any)["playx.preference.step.FIRST"]',
                         'app.buttons["Synthetic first option"]']:
            self.assertIn(required, tests)
