"""Source contracts only. No Swift compilation, live tags, or backend operations."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class ChoiceMemoryChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateChoiceMemory.swift').read_text();cls.app=(ROOT/'App/TemplateChoiceMemoryFields.swift').read_text();cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateChoiceMemoryTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateChoiceMemoryFieldsTests.swift').read_text()
    def test_exact_nested_entry_mount_and_generic_fields_retained(self):
        for token in ['TemplateChoiceMemory.isOptionPath(family, path)','TemplateChoiceMemory(model.draft.advanced, family: family, optionPath: path)','TemplateChoiceMemoryFields(model: model, family: family, optionPath: path).id(memory.scopeFingerprint)','ForEach(fields)','TemplateCreatorFieldView(model: model, family: family, field: field, path: path + [.field(field.id)])']:self.assertIn(token,self.form)
        for token in ['family == .qa, path.count == 2','family == .profile, path.count == 4','draft.text("qa", "mode") == "PICK"','?.object?["kind"]?.string == "pick"']:self.assertIn(token,self.core)
    def test_on_off_matches_source_memory_prefix_filter(self):
        for token in ['.filter { !Self.isMemory($0) }','value.object?["op"]?.string == "ADD_TAG"','hasPrefix("tag.m_")','kept.append(.object(["var": .string(""), "op": .string("ADD_TAG"), "value": .string(tag)]))','next.setCreatorValue(family, path: effectsPath, entry: .array(kept))']:self.assertIn(token,self.core)
    def test_generated_tag_collision_and_effect_capacity_guards(self):
        for token in ['otherEffectCount < 16','guard kept.count < 16','Self.reservedTags(.object(draft.value))','!used.contains(proposedTag)','for _ in 0..<32','abcdefghijklmnopqrstuvwxyz','String((0..<5).map']:self.assertIn(token,self.core)
        self.assertIn('editor.otherEffectCount >= 16',self.app);self.assertIn('editor.tags.enumerated()',self.app)
    def test_scope_owner_media_and_stale_action_guards(self):
        for token in ['scope.setCreatorValue(family, path: optionPath + [.field("effects")], entry: nil)','fingerprint == Self.snapshot(draft, family: family)','encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]']:self.assertIn(token,self.core)
        for token in ['model.objectWillChange.sink','model.coordinator.session == session','model.coordinator.identity == identity','model.mediaReviewGeneration == mediaGeneration','projection.scopeFingerprint == scopeFingerprint','self.actionGeneration == stamp','self.model.metadataGeneration == metadata','snapshot.applying(enabled: enabled','.onDisappear { editor.retire() }']:self.assertIn(token,self.app)
    def test_supported_legacy_data_is_read_before_explicit_toggle_only(self):
        self.assertIn('raw == nil || rows != nil',self.core)
        self.assertIn('tags = supported ? (rows ?? []).filter(Self.isMemory)',self.core)
        self.assertIn('model.draft.advanced = next; self.model.changed()',self.app)
        self.assertNotIn('applying(',self.core[self.core.index('public init('):self.core.index('public func applying(')])
    def test_no_new_storage_runtime_or_permissions(self):
        for token in ['URLSession','HTTPTransport','UserDefaults','Codable','factory','submit(','grantXP','PlayState','PlayKitNativeSensorProvider']:self.assertNotIn(token,self.core+self.app)
        self.assertIn('Toggle("templateMemo.remember"',self.app)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-choice-memory.json').read_text())['strings'];keys=set(re.findall(r'"(templateMemo\.[^"\\]+)"',self.app))
        self.assertTrue(keys<=set(strings),keys-set(strings));self.assertIn('templateMemo.otherEffects %lld',strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-choice-memory.json').read_text());self.assertEqual(reg['dependencies'],[])
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_authored_native_coverage_complete_lifecycle(self):
        for token in ['testEnableThenDisableUsesOnlyExistingEffectWireShapeForBothFamilies','testEnableReplacesAllMemoryEffectsAndPreservesOtherEffectsInOrder','testSixteenEffectCapacityNeverDeletesUnrelatedEffectsAndOffStillWorks','testInvalidOrCrossDraftCollisionCandidateCannotBeWritten','testCompleteOnReadbackOffAndReenableInBothOptionContexts','testOldButtonsAndBindingCannotUndoANewerMemoryWrite','testOptionRenameAndReorderCannotRetargetOldController','testSameValueABACannotReviveCapturedToggle','testLocalSaveRestoreRetainsConfigurationWithoutRunningPlayerEffects','testPendingLockDeniesMemoryWrites']:self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
