import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class TemplateLocalCategoryRemovalContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateLocalCategoryRemoval.swift').read_text();cls.app=(ROOT/'App/TemplateLocalCategoryRemovalView.swift').read_text();cls.host=(ROOT/'App/TemplateAuthoringMetadataSelectors.swift').read_text()
    def test_existing_strict_parser_and_remove_only_selection_are_reused(self):
        for token in ['TemplateMetadataCategorySelection','selection = .init(raw: draft.activityCategoryids)','guard isSupported, selectedIDs.contains(id), isCurrent(draft)','nextSelection.toggle(id)','next.activityCategoryids = nextSelection.savedValue']:
            self.assertIn(token,self.core)
        for token in ['replaceUnsupportedSelection','append(', 'next.categoryId =']:self.assertNotIn(token,self.core)
        self.assertEqual(len(re.findall(r'next\.\w+ =',self.core)),1)
    def test_snapshot_and_observation_fence_old_removal(self):
        for token in ['[.sortedKeys, .withoutEscapingSlashes]','source != nil && source == Self.snapshot(draft)','model.objectWillChange.sink','self?.generation = UUID()','self.generation == stamp','self.model.metadataGeneration == metadata','original?.removing(id, from: self.model.draft)']:
            self.assertIn(token,self.core+self.app)
        self.assertEqual(self.app.count('self.model.draft = next'),1);self.assertIn('self.model.changed()',self.app)
    def test_no_new_reader_transport_persistence_or_grant(self):
        for token in ['DiscoveryReading','URLSession','ProductionTransport','capabilityGrant','Task {','model.prepare(','model.save(','removeItem(','AsyncImage','AVPlayer','.sheet(']:self.assertNotIn(token,self.app+self.core)
    def test_visible_scene_and_fixed_owner_boundaries(self):
        for token in ['isVisible && sceneActive && model.canReadMetadataDraft','owner == model.coordinator.session','identity == model.coordinator.identity','guard canReload else { retire(); return }','func viewDisappeared() { isVisible = false; retire() }','guard isVisible && sceneActive else { retire(); return }','if !active { reload() }','!model.busy && model.review == nil']:
            self.assertIn(token,self.app)
        self.assertEqual(self.app.count('@StateObject'),1);self.assertNotIn('.id(controller',self.app)
    def test_normal_host_adds_local_route_but_old_selector_gates_remain(self):
        self.assertEqual(self.host.count('TemplateLocalCategoryRemovalView(model: model)'),1)
        for token in ['canSaveCategories: Bool { canEdit && reader?.isConfigured == true','reader.templateMetadataCategoriesRequest()','Button { presented = field }','.sheet(item: $presented)','TemplateAuthoringVenueField']:
            self.assertIn(token,self.host)
    def test_named_bilingual_resource_covers_local_controls(self):
        strings=json.loads((ROOT/'Resources/TemplateLocalCategoryRemoval.xcstrings').read_text())['strings'];self.assertEqual(len(strings),10)
        for row in strings.values():
            self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
            for lang in ['en','zh-Hans']:self.assertTrue(row['localizations'][lang]['stringUnit']['value'])
        self.assertIn('tableName: "TemplateLocalCategoryRemoval"',self.app)
    def test_native_negative_controls_and_registration(self):
        core=(ROOT/'Tests/CoreTests/TemplateLocalCategoryRemovalTests.swift').read_text();app=(ROOT/'Tests/AppUnitTests/TemplateLocalCategoryRemovalViewTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',core)),8);self.assertEqual(len(re.findall(r'func test',app)),10)
        for method in ['testNilReaderLocalRemovalHasOnePublicationAndNoRequestAuthority','testBusyABARetiresOldActionButFreshLocalActionWorks','testHiddenSceneAndReloadDoNotReactivateOldRemoval','testOwnerChangeCannotReloadOrRemoveAnotherDraft','testExistingLocalSaveRestoreKeepsOnlyRequestedRemoval','testPendingWriteLockStillBlocksVisibleLocalRemoval']:
            self.assertIn(method,app)
        reg=json.loads((ROOT/'docs/registration/template-local-category-removal.json').read_text())
        for key in ['app_sources','app_unit_tests','package_tests','resources']:
            for p in reg[key]:self.assertTrue((ROOT/p).is_file())
        self.assertIn('NOT_RUN',(ROOT/'docs/template-local-category-removal.md').read_text())
