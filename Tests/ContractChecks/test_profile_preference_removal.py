"""Focused source-only P107 selected preference removal checks; no Swift/runtime claim."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
def section(path,start,end): return read(path).split(start,1)[1].split(end,1)[0]
class ProfilePreferenceRemovalContracts(unittest.TestCase):
    def test_parse_fails_closed_instead_of_compacting_invalid_tokens(self):
        s=read('Core/ProfilePreferenceRemoval.swift')
        for token in ['raw.split(separator: ",", omittingEmptySubsequences: false)', '!token.isEmpty',
                      'token.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })', 'let value = Int(token), value > 0',
                      'return validIDs(values) ? values : nil', 'Set(values).count == values.count']:
            self.assertIn(token,s)
        self.assertNotIn('compactMap',s)
    def test_subset_preserves_original_order_and_rejects_new_ids(self):
        s=section('Core/ProfilePreferenceRemoval.swift','public static func isOrderedSubset','public static func names')
        self.assertIn('guard validIDs(original), validIDs(proposed) else { return false }',s)
        self.assertIn('return original.filter { kept.contains($0) } == proposed',s)
        self.assertNotIn('.sorted',s)
    def test_draft_selection_is_preferred_and_labels_never_authorize_ids(self):
        s=section('Core/ProfilePreferenceRemoval.swift','public static func selection','public static func isOrderedSubset')
        self.assertIn('if let values = draft.routePreferenceIDs { return validIDs(values) ? values : nil }',s)
        self.assertIn('return parse(snapshot.tagIds)',s)
        self.assertNotIn('preferenceNames',s)
    def test_names_are_optional_unambiguous_display_metadata(self):
        s=read('Core/ProfilePreferenceRemoval.swift')
        for token in ['case name = "categoryName"','Dictionary(grouping: labels, by: \\.id)','id > 0 && values.count == 1',
                      '!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty','result[id] = name']:
            self.assertIn(token,s)
        c=read('Core/ProfileEditContracts.swift')
        self.assertIn('(try? c.decode([ProfilePreferenceLabel].self, forKey: .sysCategoryList)) ?? []',c)
        self.assertIn('preferenceNames = ProfilePreferenceRemoval.names(labels)',c)
    def test_review_metadata_not_encoded_and_original_tag_write_unchanged(self):
        s=section('Core/ProfileEditContracts.swift','public struct ProfileEditPayload','public struct ProfileEditSession')
        self.assertIn('preferenceIDs = draft.routePreferenceIDs',s)
        keys=s.split('enum CodingKeys:',1)[1].split('public init',1)[0]
        self.assertNotIn('preferenceIDs',keys);self.assertNotIn('preferenceNames',keys)
        self.assertIn('tagIds = draft.routePreferenceIDs.map { $0.map(String.init).joined(separator: ",") } ?? snapshot.tagIds',s)
        self.assertIn('&& tagIds == snapshot.tagIds',s)
    def test_local_confirm_uses_full_scope_and_stale_action_fences(self):
        s=section('App/ProfileEditView.swift','func confirmTextEdit','func ownsAvatarScope')
        for token in ['guard textEdit?.id == value.id else { return false }', '!exitCommitted', '!coordinator.isLocked',
                      'coordinator.identity == value.identity','coordinator.viewerRevision == value.viewerRevision',
                      'generation == value.generation','revision == value.modelRevision','avatarDraftRevision == value.draftRevision',
                      'Self.sameDraft(draft, value.draft)','Self.sameSnapshot(snapshot, value.snapshot)']:
            self.assertIn(token,s)
        self.assertLess(s.index('retireTextEdit()'),s.index('var next = draft'))
        self.assertNotIn('await ',s)
    def test_confirm_stages_only_safe_subset_and_noop_preserves_raw(self):
        s=section('App/ProfileEditView.swift','case .preferences:','func ownsAvatarScope')
        for token in ['ProfilePreferenceRemoval.selection(draft: draft, snapshot: snapshot)',
                      'ProfilePreferenceRemoval.parse(text)','ProfilePreferenceRemoval.isOrderedSubset(selected, of: original)',
                      'if selected != original { next.routePreferenceIDs = selected }',
                      'guard value.field == .preferences,','ProfilePreferenceRemoval.validIDs(selectedIDs)',
                      'selectedIDs.map(String.init).joined(separator: ",")']:
            self.assertIn(token,s)
    def test_sheet_is_local_removal_undo_cancel_and_clear_without_catalogue(self):
        s=read('App/ProfilePreferenceRemovalEditor.swift')
        for token in ['@State private var selection: [Int]','selection.removeAll { $0 == id }',
                      'selection = original.filter { $0 == id || selection.contains($0) }',
                      'Button("profile.preferenceRemoval.clear", role: .destructive) { selection = [] }',
                      'Button("profile.preferenceRemoval.undoAll") { selection = original }',
                      'Button("action.cancel", role: .cancel, action: cancel)','Button("profile.fieldEdit.apply") { confirm(selection) }']:
            self.assertIn(token,s)
        for token in ['model.draft', 'DiscoveryReading', 'discoveryCategories(', 'URLSession','AsyncImage','NativeMediaGallery','TextField(','.save(','.task']:
            self.assertNotIn(token,s)
    def test_empty_and_invalid_selections_have_visible_non_destructive_states(self):
        s=read('App/ProfilePreferenceRemovalEditor.swift')
        self.assertIn('if original.isEmpty',s);self.assertIn('Text("profile.preferenceRemoval.empty")',s)
        self.assertIn('Text("profile.preferenceRemoval.unavailable")',s);self.assertIn('.disabled(original == nil)',s)
        self.assertIn('if let name = edit.snapshot.preferenceNames[id]',s);self.assertIn('Text(verbatim: "#\\(id)")',s)
    def test_entry_routes_dedicated_editor_and_existing_catalogue_picker_is_retained(self):
        s=read('App/ProfileEditView.swift')
        for token in ['Button("profile.preferenceRemoval.open") { model.beginTextEdit(.preferences) }',
                      'ProfilePreferenceRemovalEditor(edit: value,','model.confirmPreferenceRemoval(value, selectedIDs: $0)',
                      'ProfileRoutePreferencePicker(reader: categoryReader, selected: selectedPreferences,',
                      'if let ids = value.payload.preferenceIDs {','ProfilePreferenceRemovalReview(ids: ids)']:
            self.assertIn(token,s)
        fallback=read('App/ProfileTextFieldEditor.swift')
        self.assertIn('case .preferences: return ""',fallback);self.assertIn('.disabled(edit.field == .preferences)',fallback)
    def test_existing_prewrite_conflict_and_unknown_lock_contract_remain(self):
        s=read('Core/ProfileEditCoordinator.swift')
        for token in ['draft.routePreferenceIDs == nil || latest.tagIds == original.tagIds','guard latest == value.snapshot,',
                      'if unresolved.acknowledged && matches','messageKey = "profile.edit.readbackUnconfirmed"']:
            self.assertIn(token,s)
    def test_fixture_has_selected_id_and_self_name_without_reader_injection(self):
        s=read('Core/ProfileEditSyntheticFixtures.swift')
        self.assertIn('if scenario == .preferenceRemoval { tagIds = "4,7007" }',s)
        self.assertIn('"id": 7007, "categoryName": "Retired category"',s)
        fixture=read('App/ProfileEditFixtureSupport.swift')
        self.assertIn('case "preferenceRemoval": mode = .preferenceRemoval',fixture)
        self.assertNotIn('categoryReader:',fixture)
    def test_fragment_declares_only_new_sources_and_bilingual_keys(self):
        values=json.loads(read('Resources/ProfilePreferenceRemovalLocalizations.fragment.json'));self.assertEqual(len(values),11)
        for key,row in values.items():
            self.assertTrue(key.startswith('profile.preferenceRemoval.'))
            for lang in ['en','zh-Hans']:self.assertTrue(row['localizations'][lang]['stringUnit']['value'])
        f=json.loads(read('docs/profile-preference-removal-registration.fragment.json'))
        self.assertEqual(f['central_files_modified'],[]);self.assertEqual(f['apple'],'NOT_RUN')
    def test_tests_cover_gap_and_honest_runtime_limits(self):
        app=read('Tests/AppUnitTests/ProfilePreferenceRemovalTests.swift')
        for token in ['testOpeningUsesCurrentSelfSelectionWithoutCatalogueOrAnotherRequest',
                      'testAdditionReorderDuplicateAndNonpositiveActionsAreRejected',
                      'testMalformedStoredSelectionFailsClosedWithoutLosingOtherDrafts',
                      'testUnknownWriteRemainsLockedEvenAfterMatchingSelectionReadback']:
            self.assertIn(token,app)
        docs=read('docs/profile-preference-removal.md')
        for token in ['Apple: NOT_RUN','PENDING_PARENT_INTEGRATION','96d727404a966cd3b3d2437c79449046beda560f',
                      'makes no claim to recover a category the self response itself omits']:
            self.assertIn(token,docs)
if __name__=='__main__':unittest.main()
