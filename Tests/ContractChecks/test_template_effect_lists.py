"""Focused source contracts, not Swift/Apple/server execution."""
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class EffectListChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateEffectList.swift').read_text()
        cls.app=(ROOT/'App/TemplateEffectListView.swift').read_text()
        cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateEffectListTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateEffectListControllerTests.swift').read_text()
    def test_typed_destination_and_generic_fallback_preserve_previous_mounts(self):
        for token in ['TemplateEffectList.isEffectPath(family, path)', 'TemplateEffectListView(model: model, family: family, path: path, titleKey: field.labelKey)', 'TemplateQAAnswerFields(model: model)', 'TemplateBlindOptionFields(model: model)', '.onDelete', '.onMove', 'case .rows', 'case .stateValue']:
            self.assertIn(token,self.form)
    def test_only_existing_effect_paths_are_intercepted(self):
        for token in ['"successEffects", "failEffects", "critEffects", "fumbleEffects"', 'family == .qa, path.count == 3', '[.profile, .branch].contains(family), path.count == 5', '.field("effects")', 'draft.text("qa", "mode") == "PICK"', '["kind"]?.string == "pick"', '["terminal"] == .bool(false)']:
            self.assertIn(token,self.core)
    def test_source_add_cap_and_atomic_operation_value_transition(self):
        for token in ['rows.count < 16', '(values?.count ?? 0) <= 16', '"var": .string(""), "op": .string("INC"), "value": .number(1)', 'if operation == "ADD_TAG"', '.string(value?.string ?? "")', 'Self.numericTransition(value)', 'row["op"] = .string(operation)', 'if trimmed.isEmpty { return 0 }', 'return 1']:
            self.assertIn(token,self.core)
    def test_numeric_and_tag_inputs_keep_existing_contract(self):
        for token in ['row["op"]?.string != "ADD_TAG"', 'let number = Double(trimmed), number.isFinite', 'row["value"] = .number(number)', 'row["value"] = .string(text)', 'next.setCreatorValue(family, path: path, entry: .array(values))']:
            self.assertIn(token,self.core)
        for token in ['editor.operation(row.id)', 'editor.input(row.id, .variable)', 'editor.input(row.id, .value)', 'editor.addAction()', 'editor.removeAction(row.id)', 'editor.moveAction(row.id, row.id - 1)', 'editor.issues']:
            self.assertIn(token,self.app)
    def test_exact_parent_snapshot_and_lifecycle_fences(self):
        for token in ['scope.setCreatorValue(family, path: path, entry: nil)', 'fingerprint == Self.snapshot(draft, family: family)', 'encoder.encode(value)', 'scopeFingerprint']:
            self.assertIn(token,self.core)
        for token in ['model.objectWillChange.sink', 'if !self.writingText { self.textGeneration = UUID() }', 'private let session:', 'private let identity:', 'projection.scopeFingerprint == scopeFingerprint', 'self.actionGeneration == stamp', 'self.textGeneration == stamp', 'self.model.metadataGeneration == metadata', 'model.mediaReviewGeneration == mediaGeneration', 'model.canEdit', '.onDisappear { editor.retire() }']:
            self.assertIn(token,self.app)
    def test_no_live_effect_execution_new_service_or_variable_rule(self):
        for token in ['URLSession', 'HTTPTransport', 'UserDefaults', 'capabilityGrant', 'submit(', 'applyPlayer', 'grantXP', 'factory']:
            self.assertNotIn(token,self.core+self.app)
        self.assertIn('model.changed()',self.app)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-effect-lists.json').read_text())['strings']
        keys=set(re.findall(r'"(templateEffects\.[^"\\]+)"',self.app))
        self.assertTrue(keys<=set(strings),keys-set(strings));self.assertIn('templateEffects.rowNumber %lld',strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-effect-lists.json').read_text())
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_native_tests_cover_full_chain_and_recovery(self):
        for token in ['testAddDefaultAndSixteenRowLimit','testSwitchOperationConvertsOnlyValueShapeAndPreservesVariable','testNumericTypingStaysEditableAndExistingSerializerUsesNumber','testFullAddTypeSwitchInputMoveAndRemoveFlow','testOperationChangeRetiresHiddenInputAndOldOperationBindings','testEnclosingOptionChangeCannotSilentlyRetargetEvenAfterReload','testLocalSaveAndFreshRestoreRetainTypedEffectConfiguration','testPendingWriteLockDeniesAllEffectChanges']:
            self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
