"""Source contracts only; actual SwiftUI environment assertions run in Apple UI tests."""
from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CANONICAL = {'--uitesting-dark', '--uitesting-large-text', '--uitesting-max-text'}


def display_flags(source):
    return {flag for flag in re.findall(r'"(--uitesting-[a-z-]+)"', source)
            if 'dark' in flag or flag.endswith('-text')}


def reviewed_branch_history_display_family(sources=None):
    """Only this exact reviewed wrapper split shares its original observation.

    The lifetime wrapper copies the unmodified private helper but never selects
    its Chinese branch. Full-file pins reject *any* new call, including indirect
    expressions, extra methods and helper changes; this is not a flag exemption.
    """
    expected = {
        'PlayBranchHistoryFlowTests': '66d9552a55f04d286ff267803786d434c08da35977338042c31c229cdc88729c',
        'PlayBranchHistoryLifetimeFlowTests': '6428aeea73bb28e478fef600d4271a067a02335e6e8e256a1aa1d9d45a2a8306',
    }
    if sources is None:
        sources = {name: (ROOT / 'Tests/AppUITests' / (name + '.swift')).read_text() for name in expected}
    assert set(sources) == set(expected), 'Unknown or missing display-family wrapper'
    for name, value in sources.items():
        assert hashlib.sha256(value.encode()).hexdigest() == expected[name], 'Changed display-family source: ' + name
    original = (ROOT / 'tools/tests/fixtures/player_map_history/authored-PlayBranchHistoryFlowTests.swift.txt').read_text()
    assert hashlib.sha256(original.encode()).hexdigest() == '19a6dccc6226808b8d1ca5f51b7495249f4ff4286202cd94d0d4b16957bd17cf'

    def methods(value):
        result = {}
        for match in re.finditer(r'    func (test\w+)\s*\(', value):
            assert match[1] not in result, 'Duplicated complete method'
            end = value.index('\n    }', match.start()) + len('\n    }')
            result[match[1]] = value[match.start():end]
        return result

    old = methods(original)
    actual = {}
    for value in sources.values():
        items = methods(value)
        assert not set(items) & set(actual), 'Repeated complete method across wrappers'
        actual.update(items)
        helpers = value
        for declaration in items.values():
            helpers = helpers.replace(declaration, '', 1)
        old_helpers = original
        for declaration in old.values():
            old_helpers = old_helpers.replace(declaration, '', 1)
        normalize = lambda text: '\n'.join(line for line in re.sub(r'final class \w+: XCTestCase', 'final class Original: XCTestCase', text).splitlines() if line.strip())
        assert normalize(helpers) == normalize(old_helpers), 'Changed original helper or lifecycle'
    assert len(actual) == 5 and actual == old, 'Original five complete journeys must execute once'
    chinese = 'testChineseMaximumTextUnknownNodeAndRefreshReplaceOldHistory'
    assert chinese in methods(sources['PlayBranchHistoryFlowTests'])
    assert 'assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")' in actual[chinese]
    return '\n'.join(sources.values())


def reviewed_run129_display_family(name, sources=None):
    """Two exact reviewed two-method families; no blanket display-flag exemption."""
    from tools.run129_repair_planning import source_index, FIXTURES
    families = {
        'ProjectSubmissionAcknowledgmentFlowTests': 'ProjectSubmissionAcknowledgmentChineseFlowTests',
        'ApprovedReleasePreparationFlowTests': 'ApprovedReleasePreparationChineseFlowTests',
    }
    assert name in families, 'Unknown run129 display family'
    pair = [name, families[name]]
    index = source_index()
    if sources is None:
        sources = {key: (ROOT/'Tests/AppUITests'/(key+'.swift')).read_text() for key in pair}
    assert set(sources) == set(pair), 'Missing or extra family member'
    oldrow=index['historical_ui_sources']['Tests/AppUITests/'+name+'.swift']
    original=(FIXTURES/oldrow['historical_file']).read_text()
    assert hashlib.sha256(original.encode()).hexdigest()==oldrow['sha256']
    pattern=r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
    old={key:body for body,key in re.findall(pattern,original)}
    actual={};helpers=[]
    for key,text in sources.items():
        assert hashlib.sha256(text.encode()).hexdigest()==index['current_ui_sources']['Tests/AppUITests/'+key+'.swift']['sha256'], 'Changed display-family complete source'
        declarations={method:body for body,method in re.findall(pattern,text)}
        assert len(declarations)==1 and not set(actual)&set(declarations)
        actual.update(declarations)
        helper=re.sub(pattern,'',text)
        helper=re.sub(r'(?m)^    // UNMEASURED complete method estimate:.*\n','',helper)
        helper=helper.replace('final class '+key+': XCTestCase','final class Original: XCTestCase')
        helpers.append('\n'.join(line for line in helper.splitlines() if line.strip()))
    assert len(actual)==2 and actual==old, 'Two original complete journeys must map once'
    assert helpers[0]==helpers[1], 'Both wrappers must retain the same reviewed helpers'
    chinese=next(body for method,body in actual.items() if 'Chinese' in method)
    assert 'assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")' in chinese
    return '\n'.join(sources.values())


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
                    checked = reviewed_branch_history_display_family() if path.name == 'PlayBranchHistoryLifetimeFlowTests.swift' else source
                    if path.stem in {'ProjectSubmissionAcknowledgmentFlowTests', 'ApprovedReleasePreparationFlowTests'}:
                        checked = reviewed_run129_display_family(path.stem)
                    self.assertIn('assertFixtureEnvironment(in: app', checked)
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
