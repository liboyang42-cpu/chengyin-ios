"""Source contracts only; actual SwiftUI environment assertions run in Apple UI tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CANONICAL = {'--uitesting-dark', '--uitesting-large-text', '--uitesting-max-text'}


def display_flags(source):
    return {flag for flag in re.findall(r'"(--uitesting-[a-z-]+)"', source)
            if 'dark' in flag or flag.endswith('-text')}


class FixtureEnvironmentContractTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_every_custom_display_flag_has_the_shared_recognized_spelling(self):
        options = self.read('App/AccessibilityFixtureOptions.swift')
        recognized = set(re.findall(r'args\.contains\("([^"]+)"\)', options))
        self.assertEqual(recognized, CANONICAL)
        found = set()
        for path in (ROOT / 'Tests/AppUITests').glob('*.swift'):
            flags = display_flags(path.read_text())
            found |= flags
            with self.subTest(file=path.name):
                self.assertFalse(flags - recognized, f'Unrecognized display flags: {flags - recognized}')
        self.assertEqual(found, CANONICAL)

    def test_readback_reads_the_effective_environment_not_launch_arguments(self):
        source = self.read('App/AccessibilityFixtureOptions.swift')
        self.assertTrue(source.startswith('#if DEBUG\n'))
        observation = source.split('struct AccessibilityFixtureEnvironmentValue:', 1)[1]
        for token in ['@Environment(\\.colorScheme)', '@Environment(\\.dynamicTypeSize)',
                      'content.accessibilityValue(Text(verbatim:', 'switch dynamicTypeSize',
                      'case .accessibility3:', 'case .accessibility5:']:
            self.assertIn(token, observation)
        for forbidden in ['ProcessInfo', 'arguments', 'args.contains', '.preferredColorScheme(', '.dynamicTypeSize(']:
            self.assertNotIn(forbidden, observation)
        self.assertIn('args.contains("--uitesting-dark") ? .dark : nil', source)
        self.assertIn('args.contains("--uitesting-max-text") ? .accessibility5 : (args.contains("--uitesting-large-text") ? .accessibility3 : size)', source)

    def test_probe_is_on_existing_fixture_notice_below_the_override(self):
        source = self.read('App/ModuleFixtureSupport.swift')
        self.assertTrue(source.startswith('#if DEBUG\n'))
        self.assertIn('.accessibilityIdentifier("module.fixture.notice")\n                .modifier(AccessibilityFixtureEnvironmentValue())', source)
        self.assertLess(source.index('.modifier(AccessibilityFixtureEnvironmentValue())'), source.index('switch module'))
        self.assertGreater(source.index('.modifier(AccessibilityFixtureOptions())'), source.index('case .localization:'))
        self.assertEqual(source.count('.modifier(AccessibilityFixtureOptions())'), 1)
        app = self.read('App/QuestifyApp.swift')
        self.assertIn('ModuleFixtureRootView(module:module)', app)
        self.assertNotIn('AccessibilityFixtureEnvironmentValue', app)
        self.assertNotIn('AccessibilityFixtureOptions', app)
        callers = [p.name for p in (ROOT / 'App').glob('*.swift')
                   if 'AccessibilityFixtureEnvironmentValue()' in p.read_text()]
        self.assertIn('ModuleFixtureSupport.swift', callers)
        self.assertFalse(set(callers) - {'ModuleFixtureSupport.swift', 'MerchantMarketingFixtureHost.swift'})
        for name in callers:
            self.assertTrue(self.read(f'App/{name}').startswith('#if DEBUG\n'))

    def test_all_module_display_flag_callers_assert_observed_environment(self):
        for path in (ROOT / 'Tests/AppUITests').glob('*.swift'):
            source = path.read_text()
            if display_flags(source) and '"--uitesting-module"' in source:
                with self.subTest(file=path.name):
                    self.assertIn('assertFixtureEnvironment(in: app', source)
        helper = self.read('Tests/AppUITests/FixtureEnvironmentAssertions.swift')
        self.assertIn('noticeIdentifier: String = "module.fixture.notice"', helper)
        self.assertIn('identifier: noticeIdentifier', helper)
        self.assertIn('value BEGINSWITH', helper)
        self.assertIn('value ENDSWITH', helper)
        self.assertIn('XCTWaiter.wait', helper)
        self.assertNotIn('launchArguments', helper)

    def test_repaired_flows_keep_chinese_dark_and_large_type_and_ui_assertions(self):
        cases = {
            'SocialAccountFlowTests': ['"--uitesting-large-text", "--uitesting-dark"', 'editor.value as? String, "Native draft"', 'dialogTitle: "要放弃这份草稿吗？"'],
            'SquareReportFlowTests': ['"--uitesting-large-text", "--uitesting-dark"', 'squareReport.description', 'squareReport.review'],
            'SettingsNativeFlowTests': ['"--uitesting-large-text", "--uitesting-dark"', '复制失败，请选择文字后手动复制。', 'settingsNative.about.contactPhone'],
        }
        for name, tokens in cases.items():
            source = self.read(f'Tests/AppUITests/{name}.swift')
            with self.subTest(file=name):
                for token in tokens + ['language: "zh-Hans"', 'colorScheme: "dark", dynamicTypeSize: "accessibility3"']:
                    self.assertIn(token, source)

    def test_presentation_host_cannot_shadow_the_shared_size_override(self):
        source = self.read('App/NativePresentationFixtureSupport.swift')
        self.assertNotIn('.dynamicTypeSize(', source)
        caller = self.read('Tests/AppUITests/NativePresentationPatternFlowTests.swift')
        self.assertIn('"--uitesting-max-text"', caller)
        self.assertIn('colorScheme: "dark", dynamicTypeSize: "accessibility5"', caller)
        self.assertNotIn('--uitesting-presentation-max-text', caller)

    def test_other_direct_consumers_stay_debug_only_and_attached(self):
        for path in ['App/ShopNPCFixtureView.swift', 'App/RegistrationFixtureSupport.swift']:
            source = self.read(path)
            with self.subTest(file=path):
                self.assertTrue(source.startswith('#if DEBUG\n'))
                self.assertIn('.modifier(AccessibilityFixtureOptions())', source)
        # Separate OS-level size injection remains explicit for template fixtures.
        for name in ['TemplateAuthoringFlowTests', 'TemplateOwnShelfFlowTests']:
            source = self.read(f'Tests/AppUITests/{name}.swift')
            self.assertIn('"-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"', source)

    def test_authored_maximum_precedence_case_asserts_actual_environment(self):
        source = self.read('Tests/AppUITests/AccessibilityPresentationFlowTests.swift')
        case = source.split('func testMaximumTextWinsWhenBothCanonicalSizeFlagsArePresent()', 1)[1]
        self.assertIn('"--uitesting-large-text", "--uitesting-max-text"', case)
        self.assertIn('colorScheme: "dark", dynamicTypeSize: "accessibility5"', case)


if __name__ == '__main__':
    unittest.main()
