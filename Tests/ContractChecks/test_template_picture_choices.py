"""Focused source contracts only; not Swift compilation, UI execution or server gameplay."""
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class PictureChoiceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplatePictureChoices.swift').read_text()
        cls.app=(ROOT/'App/TemplatePictureChoiceEditor.swift').read_text()
        cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplatePictureChoicesTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplatePictureChoiceEditorTests.swift').read_text()
    def test_precise_destination_keeps_generic_fallback(self):
        for token in ['family == .pricePair, path == [.field("items")], TemplatePictureChoices(model.draft.advanced).isSupported','TemplatePictureChoiceEditor(model: model)','case .rows(let fields, let minimum, let maximum, _)','Form { TemplateCreatorFieldsView(model: model, family: family, fields: fields, path: path + [.index(index)]) }']:
            self.assertIn(token,self.form)
    def test_exclusive_select_writes_every_correct_flag(self):
        for token in ['case .choose(let id):','nextRows.contains(where: { $0.id == id })','for index in nextRows.indices { nextRows[index].value["correct"] = .bool(nextRows[index].id == id) }']:
            self.assertIn(token,self.core)
        self.assertIn('Button(action: editor.chooseAction(row.id))',self.app)
        self.assertNotIn('Toggle(',self.app)
    def test_full_edit_chain_and_existing_id_allocator(self):
        for token in ['rows.count < 8','added.addCreatorRow(.pricePair, path: [.field("items")], field: field)','case .text(let id, let field, let text):','nextRows.remove(at: index)','nextRows.insert(row, at: index + offset)','next.set("pricePair", "items", .array(nextRows.map { .object($0.value) }))']:
            self.assertIn(token,self.core)
        for token in ['editor.text(row.id, field: .name)','editor.text(row.id, field: .imageURL)','editor.addAction()','editor.removeAction(row.id)','editor.moveAction(row.id, by: -1)','editor.moveAction(row.id, by: 1)','editor.correctCount','editor.issues']:
            self.assertIn(token,self.app)
    def test_own_typing_keeps_session_but_actions_retire(self):
        for token in ['model.objectWillChange.sink','model.$draft.dropFirst().sink','guard let self, !self.writing else','actionGeneration = UUID(); writing = true','if !update.choices.isCurrent(model.draft.advanced)','self.textGeneration = UUID(); self.apply(update)','self.choices.applying(.text(id, field, text)']:
            self.assertIn(token,self.app)
    def test_external_draft_owner_media_and_exact_bytes_are_guarded(self):
        for token in ['fingerprint == Self.snapshot(draft)','encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]','guard canEdit, isCurrent(draft)']:
            self.assertIn(token,self.core)
        for token in ['model.coordinator.session == session','model.coordinator.identity == identity','mediaGeneration == model.mediaReviewGeneration','self.actionGeneration == stamp','self.model.metadataGeneration == metadata','self.textGeneration == stamp','needsReload = true','.onDisappear { editor.retire() }']:
            self.assertIn(token,self.app)
    def test_no_network_storage_schema_or_permission_expansion(self):
        for token in ['URLSession','AsyncImage','HTTPTransport','UserDefaults','factory','submit(','grantXP','randomElement','Codable']:
            self.assertNotIn(token,self.app+self.core)
        self.assertIn('model.changed()',self.app)
        self.assertIn('creatorIssues(.pricePair)',self.app)
    def test_registration_and_localization_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-picture-choices.json').read_text())['strings']
        keys=set(re.findall(r'"(templatePictures\.[^"\\]+)"',self.app));self.assertTrue(keys<=set(strings),keys-set(strings))
        for key in ['templatePictures.number %lld','templatePictures.count %lld','templatePictures.correctCount %lld']:self.assertIn(key,strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-picture-choices.json').read_text());self.assertEqual(reg['dependencies'],[])
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_authored_native_coverage_includes_user_and_lifecycle_chain(self):
        for token in ['testSelectionAtomicallySetsExactlyOneAnswerAndRepeatedTapNeverUnsetsIt','testCompleteAddNameAddressSelectRemoveFlowUsesExistingWireShape','testRemovingChosenPictureDoesNotInventAnotherAnswerAndAllowsEmptyList','testNativeIDAllocatorAvoidsCollisionsAndCapsAtEight','testExistingRehearsalSerializationAndLocalDraftRoundTripReadTheSameAnswer','testCompleteAddEditSelectMoveRemoveFlowUpdatesCoordinator','testContinuousTextInputSurvivesParentChangedRefresh','testStructuralActionsRetireBindingsWithoutRetargeting','testSameValueABADoesNotReviveRetainedBindingsOrButtons','testLocalSaveRestoreRetainsSelectedAnswerAndMediaAddress','testPendingLockDeniesPictureEdits']:
            self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
