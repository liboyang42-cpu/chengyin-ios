"""Focused source contracts, not Swift/Apple/IME or live daily-sign execution."""
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class DailyPoemChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateDailyPoemPool.swift').read_text()
        cls.app=(ROOT/'App/TemplateDailyPoemEditor.swift').read_text()
        cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateDailyPoemPoolTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateDailyPoemEditorTests.swift').read_text()
    def test_supported_destination_and_existing_line_fallback(self):
        for token in ['case .poems','family == .dailySign, TemplateDailyPoemPool(model.draft.advanced).isSupported','TemplateDailyPoemEditor(model: model)','field: .init("poemLines", .strings(min: 1, max: 4, length: 24)']:
            self.assertIn(token,self.form)
    def test_exact_raw_text_and_source_split_trim_filter(self):
        for token in ['joined(separator: "\\n")','components(separatedBy: "\\n")','trimmingCharacters(in: .whitespacesAndNewlines)','filter { !$0.isEmpty }','nextRows[index].text = text','nextRows.map { .array(Self.lines($0.text).map { .string($0) }) }']:
            self.assertIn(token,self.core)
        self.assertIn('TextEditor(text: editor.text(row.id))',self.app)
    def test_full_pool_add_edit_remove_preserves_existing_fields(self):
        for token in ['rows.count < 60','nextRows.append(.init(text: ""))','nextRows.remove(at: index)','next.set("dailySign", "poems", .array(poems))','pool.rows = nextRows']:
            self.assertIn(token,self.core)
        for token in ['editor.addAction()','editor.removeAction(row.id)','DisclosureGroup("templatePoems.preview")','TemplateDailyPoemPool.lines(row.text)','editor.issues']:
            self.assertIn(token,self.app)
    def test_raw_only_changes_retire_buttons_without_breaking_repeated_typing(self):
        for token in ['actionGeneration = UUID(); writing = true','pool = update.pool','if !update.pool.isCurrent(model.draft.advanced)','self.pool.applying(.text(id, text)','self.textGeneration == stamp']:
            self.assertIn(token,self.app)
    def test_external_reload_ownership_and_lifecycle_guards(self):
        for token in ['fingerprint == Self.snapshot(draft)','pool.fingerprint = Self.snapshot(next)']:
            self.assertIn(token,self.core)
        for token in ['model.objectWillChange.sink','model.$draft.dropFirst().sink','model.coordinator.session == session','model.coordinator.identity == identity','mediaGeneration == model.mediaReviewGeneration','self.actionGeneration == stamp','self.model.metadataGeneration == metadata','needsReload = true','Button("templatePoems.reload")','.onDisappear { editor.retire() }']:
            self.assertIn(token,self.app)
    def test_no_storage_schema_random_draw_or_service_addition(self):
        for token in ['URLSession','HTTPTransport','UserDefaults','factory','submit(','randomElement','Calendar.current','grantXP']:
            self.assertNotIn(token,self.app+self.core)
        self.assertNotIn('Codable',self.core)
        self.assertIn('model.changed()',self.app)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-daily-poems.json').read_text())['strings']
        keys=set(re.findall(r'"(templatePoems\.[^"\\]+)"',self.app));self.assertTrue(keys<=set(strings),keys-set(strings))
        for key in ['templatePoems.number %lld','templatePoems.lineCount %lld']:self.assertIn(key,strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-daily-poems.json').read_text())
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_native_coverage_has_full_input_and_restore_lifecycle(self):
        for token in ['testWholePasteNormalizesLinesButKeepsExactRawInput','testRawOnlyNewlinesChangeEditorEvenWhenCanonicalDraftIsIdentical','testEachExplicitActionRebuildsTheWholePoolLikeMini','testCompleteAddPasteRepeatedEditPreviewAndDeleteFlow','testRawOnlyTypingKeepsInputAndRetiresEarlierButtons','testParentChangedRefreshDoesNotDiscardRawInputOrInterruptTyping','testExternalPublicationNeedsExplicitReloadAndRejectsOldRawDraft','testDismissalAndReopenUsesCanonicalTextAndFreshBindings','testLocalSaveRestorePersistsOnlyCanonicalPoems','testPendingLockDeniesPoemWrites']:
            self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
