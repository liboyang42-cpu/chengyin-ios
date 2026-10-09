"""Bounded source contracts only; these do not execute Swift or SwiftUI."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = (ROOT / 'Core/ProjectInitialAttributes.swift').read_text()
UI = (ROOT / 'App/ProjectInitialAttributesEditor.swift').read_text()
HOST = (ROOT / 'App/ProjectInitialStateEditor.swift').read_text()
CORE_TESTS = (ROOT / 'Tests/CoreTests/ProjectInitialAttributesTests.swift').read_text()
APP_TESTS = (ROOT / 'Tests/AppUnitTests/ProjectInitialAttributesPresentationTests.swift').read_text()

class InitialAttributesContracts(unittest.TestCase):
    def test_existing_first_chapter_entry_hosts_new_flow(self):
        self.assertEqual(HOST.count('ProjectInitialAttributesEntry(model: model, chapterID: controller.chapterID)'), 1)
        self.assertIn('ProjectInitialStateSheet(controller: controller, original: original)', HOST)
    def test_full_edit_real_first_chapter_scope(self):
        for term in ['model.fullEdit', 'model.draft.product == .city', 'model.draft.chapters.first?.id.utf8.elementsEqual(chapterID.utf8)', 'model.draft.chapters.filter { $0.id == chapterID }.count == 1']:
            self.assertIn(term, UI)
    def test_tap_captures_current_lease_and_draft_bytes(self):
        for term in ['let captured = controller.capture()', 'controller.open(captured)', 'model.captureStarterLease()', 'model.draftMutationRevision', 'ProjectEditPendingMaterials.exactData(model.draft)']:
            self.assertIn(term, UI)
    def test_old_presentation_cannot_mutate_reopened_or_foreign_owner(self):
        for term in ['capture.controller == identity', 'capture.generation == generation', 'model.isCurrentStarterLease(capture.lease)', 'presentation?.id == original.id', 'model.draftMutationRevision == capture.revision']:
            self.assertIn(term, UI)
    def test_all_staging_is_owned_and_apply_is_draft_only(self):
        self.assertIn('guard isCurrent(original), var value = buffer, !value.readOnly', UI)
        self.assertIn('guard isCurrent(original), removal == nil, let buffer', UI)
        self.assertEqual(UI.count('model.draft = next'), 1)
        self.assertIn('next.preserved["journeyRules"] = result', UI)
        for forbidden in ['URLRequest', 'URLSession', '.submit(', '.saveLocal(', '.register(', '.deleteStateKey(', 'api/']:
            self.assertNotIn(forbidden, CORE + UI)
    def test_cancel_disappear_and_identity_changes_retire(self):
        self.assertIn('.onDisappear { controller.retire() }', UI)
        self.assertIn('.onDisappear { controller.close(original) }', UI)
        self.assertIn('.onChange(of: model.editorIncarnation)', UI)
        self.assertIn('guard presentation?.id == original.id else { return }; retire()', UI)
    def test_remove_declaration_requires_current_buffer_confirmation(self):
        for term in ['intent.bufferRevision == bufferRevision', 'intent.presentationID == original.id', 'removal?.id == intent.id', 'guard isCurrent(intent, in: original)', 'bufferRevision += 1; removal = nil']:
            self.assertIn(term, UI)
        self.assertIn('Button(role: .destructive)', UI)
    def test_existing_key_cannot_rename(self):
        self.assertIn('!key.utf8.elementsEqual(row.key.utf8)', CORE)
        self.assertIn('if row.existingKey != nil', UI)
        self.assertIn('row.existingKey.map({ $0.utf8.elementsEqual(row.key.utf8) })', CORE)
    def test_bounds_and_explicit_toggle_match_known_contract(self):
        for term in ['rows.count < 32', 'rows.count <= 32', 'minimum >= -10000', 'maximum <= 10000', '(minimum...maximum).contains(initial)', 'minimum == 0 && maximum == 1', 'label.utf16.count <= 24']:
            self.assertIn(term, CORE)
        self.assertIn('if stateEnabled != originalEnabled { next["stateEnabled"] = .bool(stateEnabled) }', CORE)
        self.assertNotIn('next["checkEnabled"]', CORE)
        self.assertNotIn('next["hp"]', CORE)
        self.assertNotIn('next["luck"]', CORE)
    def test_java_trim_is_not_swift_whitespace_trim(self):
        self.assertIn('first.value <= 0x20', CORE); self.assertIn('last.value <= 0x20', CORE)
        self.assertNotIn('.trimmingCharacters', CORE)
    def test_strict_imported_integer_tokens_and_null_types(self):
        for term in ['try Self.validateIntegerTokens(text)', 'path[0] == "attributes"', '["initial","min","max"].contains(path[2])', 'guard let value = raw.integer', 'guard case .bool(let flag) = value']:
            self.assertIn(term, CORE)
    def test_noop_exact_binding_and_omission_preservation(self):
        self.assertIn('try Self.bytes(raw) == Self.bytes(source)', CORE)
        self.assertIn('if isUnchanged { return raw }', CORE)
        self.assertIn('var result = row.source ?? [:]', CORE)
        self.assertIn('if !sameRows { next["attributes"] = .array(attributes) }', CORE)
    def test_unknown_data_cannot_collapse_during_json_decode(self):
        self.assertIn('ContentDraftJSON.parse(text) == ContentDraftJSON.parse(roundTrip)', CORE)
        self.assertIn('var next = root', CORE)
        self.assertIn('data.count <= 16 * 1024', CORE)
    def test_no_automatic_dependency_rewrites_or_key_endpoint(self):
        for key in ['thoughts','recovery','journeyStory','routeGraphJson','stateKeys']:
            self.assertNotIn('next["'+key+'"] =', CORE)
        self.assertNotIn('state-keys', CORE + UI)
    def test_bilingual_named_catalog_is_complete(self):
        catalog = json.loads((ROOT/'Resources/ProjectInitialAttributes.xcstrings').read_text())
        keys = {'projectInitialAttributes.'+x for x in re.findall(r'text\("([A-Za-z]+)"\)', UI)}
        keys |= {'projectInitialAttributes.title','projectInitialAttributes.flagHint','projectInitialAttributes.integerHint','projectInitialAttributes.removeTitle'}
        self.assertEqual(catalog['sourceLanguage'], 'en'); self.assertEqual(len(catalog['strings']), 21)
        self.assertFalse(keys-set(catalog['strings']))
        for entry in catalog['strings'].values():
            self.assertEqual(set(entry['localizations']), {'en','zh-Hans'})
            for locale in entry['localizations'].values(): self.assertTrue(locale['stringUnit']['value'].strip())
        for language in ['en','zh-Hans']:
            hint=catalog['strings']['projectInitialAttributes.removeHint']['localizations'][language]['stringUnit']['value']
            self.assertTrue(hint)
    def test_core_regressions_cover_boundary_and_preservation_cases(self):
        for name in ['NoOpPreserves','DoesNotEnableState','FreshAttributeAddsOnlySchema','ExistingKeyCannotRename','ThirtyThird','FlagBounds','JavaTrimAndUTF16','FloatingOrExponent','CanonicalEquivalentUnknownKeys','ExactSourceBinding','RemovingDeclarationKeepsDependencies','Oversize']:
            self.assertIn(name, CORE_TESTS)
    def test_actual_controller_regressions_include_stale_actions(self):
        for name in ['OpenCancelAndNoOp','ExplicitApplyOnly','QueuedOpeningAfterDeparture','SameByteABA','RemovalNeedsExplicitConfirmation','StaleRemovalRejectsBufferABA','RemovalAfterOwnerChange','UnsupportedImport']:
            self.assertIn(name, APP_TESTS)
        self.assertIn('ProjectInitialAttributesController', APP_TESTS)
        self.assertIn('controller.confirmRemoval', APP_TESTS)
    def test_schema_default_only_for_genuinely_empty_roots(self):
        self.assertIn('if next.isEmpty { next["schemaVersion"] = .number(1) }', CORE)
        self.assertIn('if !root.isEmpty { guard root["schemaVersion"]?.integer == 1', CORE)

if __name__ == '__main__': unittest.main()
