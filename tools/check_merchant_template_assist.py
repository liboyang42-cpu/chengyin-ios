#!/usr/bin/env python3
"""Offline source-contract checks only; not Swift execution or Apple UI evidence."""
import json
import os
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()
class MerchantTemplateAssistSourceTests(unittest.TestCase):
    def test_exact_scoped_route_and_default_off(self):
        runtime = read('Core/BusinessRuntimeConfiguration.swift')
        self.assertIn('case .publishingAITemplate: paths = ["api/ai/template/fill"]', runtime)
        self.assertIn('routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]', runtime)
        factory = read('Core/PublishingAIRuntimeFactory.swift')
        self.assertIn('case .publishingAITemplate: path = "api/ai/template/fill"', factory)
        self.assertIn('permits(feature)', factory)
        self.assertIn('approval = approval([feature])', factory)
        self.assertIn('fields["shopName"]?.text', factory)
        self.assertIn('fields["extraNote"]?.text', factory)
    def test_sheet_reaches_existing_editor_and_explicit_field_review(self):
        editor, views, sheet = map(read, ['App/MerchantOperationsEditor.swift', 'App/MerchantOperationsViews.swift', 'App/MerchantTemplateAssistSheet.swift'])
        self.assertIn('.sheet(item: $assist)', editor)
        self.assertEqual(views.count('destination: .template('), 2)
        self.assertEqual(views.count('imageHost: imageHost, templateAssistFactory: templateAssistFactory)'), 3)
        self.assertIn('MerchantTemplateSuggestionReviewPanel(review: review', sheet)
        self.assertIn('await flow.change(action, change)', sheet)
        self.assertIn('document.templateAssistChanged()', sheet)
        flow = read('Core/MerchantTemplateAssistFlow.swift')
        self.assertIn('coordinator.edit(.template(next))', flow)
        self.assertNotIn('func apply()', flow)
        self.assertNotIn('flow.apply()', sheet)
        for source in [sheet, read('Core/MerchantTemplateAssistFlow.swift')]:
            self.assertNotRegex(source, r'\.save(?:Example|Reviewed)?\(')
            self.assertNotIn('URLSession', source)
        self.assertNotIn('api/ai/node/generate', sheet + read('Core/MerchantTemplateAssistFlow.swift'))
    def test_scope_and_field_revisions_guard_merge(self):
        contracts, flow, coordinator = map(read, ['Core/MerchantTemplateAssistContracts.swift', 'Core/MerchantTemplateAssistFlow.swift', 'Core/MerchantOperationsReading.swift'])
        self.assertIn('coordinator.draftIdentity == draftIdentity', flow)
        self.assertIn('client?.session == session', flow)
        self.assertEqual(flow.count('try await readAccess()'), 2)
        self.assertIn('return try await reader.access()', flow)
        self.assertIn('permissionRead?.cancel()', flow)
        self.assertIn('edits.unchanged(field, since: capturedEdits)', contracts)
        self.assertIn('templateAssistEdits.record(from: old, to: new)', coordinator)
        self.assertIn('latest.id == captured.id', contracts)
        self.assertIn('guard !busy else { return }', flow)
    def test_source_field_mapping_and_unsupported_exposure(self):
        contracts = read('Core/MerchantTemplateAssistContracts.swift')
        for key in ['storyText', 'ruleInstructions', 'questionName', 'questionAnswer', 'hint1', 'hint2']:
            self.assertIn('"' + key + '"', contracts)
        self.assertIn('String($0.prefix(30))', contracts)
        self.assertIn('public var unsupportedKeys', contracts)
        self.assertIn('ForEach(result.unsupportedKeys', read('App/MerchantTemplateAssistSheet.swift'))
        self.assertNotIn('case questionA,', contracts)
    def test_fixtures_are_explicit_and_never_real_provider(self):
        fixture = read('App/MerchantTemplateAssistFixture.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('HTTPTransport', fixture)
        self.assertNotIn('URLSession', fixture)
        self.assertIn('--merchant-template-assist-fixture', read('App/MerchantOperationsFixtureSupport.swift'))
    def test_bilingual_keys_merged_without_empty_values(self):
        fragment = json.loads(read('Resources/MerchantTemplateAssistLocalizations.fragment.json'))
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 38)
        for key, item in fragment.items():
            self.assertEqual(catalog[key], item)
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'].strip())
    def test_focused_cases_are_authored(self):
        core = read('Tests/CoreTests/MerchantTemplateAssistTests.swift') + read('Tests/CoreTests/MerchantTemplateAssistRuntimeTests.swift') + read('Tests/CoreTests/MerchantTemplateSuggestionReviewTests.swift') + read('Tests/CoreTests/MerchantTemplateAssistPermissionLifetimeTests.swift')
        ui = read('Tests/AppUITests/MerchantTemplateAssistFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 42)
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 4)
    def test_optional_flutter_contract_reference(self):
        source = os.environ.get('CHENGYIN_FLUTTER_SOURCE_ROOT')
        if not source: self.skipTest('Optional private Flutter source not configured')
        assist = (Path(source) / 'lib/feature/merchant/ai_node_assist.dart').read_text()
        editor = (Path(source) / 'lib/feature/merchant/node_template_edit_page.dart').read_text()
        for needle in ['.templateFill(', 'shopName: widget.nodeName', 'extraNote: prompt', 'validationMethod: widget.validationMethod']:
            self.assertIn(needle, assist)
        for field in ['optionA', 'optionB', 'optionC', 'optionD', 'storyText', 'medalName', 'answerReveal']:
            self.assertIn(field, assist)
        self.assertIn('Future<void> _aiAssist()', editor)
        self.assertIn('if (_c[key]!.text.trim().isNotEmpty) return;', editor)
if __name__ == '__main__': unittest.main(verbosity=2)
