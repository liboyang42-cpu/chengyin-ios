"""Bounded source contracts, not native compilation or multiplayer execution."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class MultiplayerPlanChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateMultiplayerPlan.swift').read_text();cls.app=(ROOT/'App/TemplateMultiplayerPlanEditor.swift').read_text();cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateMultiplayerPlanTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateMultiplayerPlanEditorTests.swift').read_text()
    def test_scoped_roles_entry_unifies_order_and_keeps_generic_fallback(self):
        for token in ['family == .multiplayer, path.isEmpty, ["roles", "turnOrder"].contains(field.id), TemplateMultiplayerPlan(model.draft.advanced).isSupported','if field.id == "roles"','NavigationLink("templateTeam.title") { TemplateMultiplayerPlanEditor(model: model) }','TemplateCreatorFieldView(model: model, family: family, field: field, path: path + [.field(field.id)])']:
            self.assertIn(token,self.form)
    def test_source_defaults_and_full_role_editor(self):
        for token in ['roles.count < 20','"min": .number(0), "max": .number(1)','while used.contains(key)','case .identifier:','case .label:','case .minimum, .maximum:','plan.roles.remove(at: index)','plan.roles.insert(row, at: index + offset)']:
            self.assertIn(token,self.core)
        for token in ['field: .identifier','field: .label','field: .minimum','field: .maximum','editor.addAction()','editor.removeAction(role.id)','editor.moveAction(role.id, by: -1)','editor.moveAction(role.id, by: 1)']:
            self.assertIn(token,self.app)
    def test_bulk_parser_retains_order_duplicates_and_raw_input(self):
        for token in ['CharacterSet(charactersIn: ",，','\\u{FEFF}','\\u{200A}','text.components(separatedBy: separators).filter { !$0.isEmpty }','plan.orderText = text; plan.order = Self.parseOrder(text)','next.set("multiplayer", "turnOrder", .array(plan.order.map { .string($0) }))']:
            self.assertIn(token,self.core)
        self.assertNotIn('Set(plan.order)',self.core);self.assertIn('TextEditor(text: editor.orderInput())',self.app)
    def test_reference_readback_and_preserve_order_on_role_edit(self):
        for token in ['labels.count == 1','roles.filter { $0.wireID == key }.map(\\.label)','if case .order = edit {} else { next.set("multiplayer", "roles"','plan.roles[index].minimumText = text','value = .string(text)']:
            self.assertIn(token,self.core)
        self.assertIn('if turn.resolvesUniquely',self.app);self.assertIn('"templateTeam.unresolved"',self.app);self.assertIn('creatorIssues(.multiplayer)',self.app)
    def test_lifecycle_and_continuous_input_guards(self):
        for token in ['fingerprint == Self.snapshot(draft)','encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]']:self.assertIn(token,self.core)
        for token in ['model.objectWillChange.sink','model.$draft.dropFirst().sink','guard let self, !self.writing else','model.coordinator.session == session','model.coordinator.identity == identity','mediaGeneration == model.mediaReviewGeneration','self.actionGeneration == stamp','self.model.metadataGeneration == metadata','self.textGeneration == stamp','if !update.plan.isCurrent(model.draft.advanced)','.onDisappear { editor.retire() }']:self.assertIn(token,self.app)
    def test_no_network_or_live_allocation_and_storage_expansion(self):
        for token in ['URLSession','HTTPTransport','UserDefaults','factory','submit(','grantXP','assignPlayers','Codable']:self.assertNotIn(token,self.core+self.app)
        self.assertIn('model.changed()',self.app)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-multiplayer-plan.json').read_text())['strings']; keys=set(re.findall(r'"(templateTeam\.[^"\\]+)"',self.app+self.form))
        self.assertTrue(keys<=set(strings),keys-set(strings))
        for key in ['templateTeam.roleNumber %lld','templateTeam.roleCount %lld']:self.assertIn(key,strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-multiplayer-plan.json').read_text());self.assertEqual(reg['dependencies'],[])
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_authored_native_complete_chain_and_stale_controls(self):
        for token in ['testNewRoleHasSourceZeroOneBoundsAndUniqueAutomaticIdentifier','testBulkCommaChineseCommaWhitespaceInputPreservesSequenceAndDuplicates','testMiniWhitespaceIncludesBOMAndDoesNotTreatNELAsSeparator','testRenameAndRemoveKeepDanglingReferencesUntilAuthorEditsOrder','testNumericIncompleteAndLeadingZeroInputIsPreservedWithoutCoercingEmptyToZero','testCompleteValidConfigurationSerializesAndLocalDraftRoundTrips','testCompleteRoleEditBulkOrderReferenceAndRemoveFlow','testContinuousOrderAndRoleTypingSurvivesParentChangedRefresh','testRawOnlyOrderChangeRetiresButtonsWithoutWritingDifferentModel','testStructuralActionsRetireRoleAndOrderBindings','testLocalSaveRestorePersistsWireRolesAndOrderOnly','testPendingLockDeniesRoleAndOrderWrites']:self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
