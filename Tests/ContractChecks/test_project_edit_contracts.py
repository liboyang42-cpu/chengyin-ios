"""Source/structure evidence only. These checks do not execute Swift or prove server parity."""
import json
import os
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get('FLUTTER_AUDIT_ROOT', str(ROOT.parent / 'app-audit')))

class ProjectEditContracts(unittest.TestCase):
    def setUp(self):
        self.contract = (ROOT/'Core/ProjectEditContract.swift').read_text()
        self.coordinator = (ROOT/'Core/ProjectEditCoordinator.swift').read_text()
        self.service = (ROOT/'Core/ProjectEditService.swift').read_text()
    def test_default_off_with_separate_scoped_transport(self):
        for name in ['ProjectEditService.swift','ProjectEditCoordinator.swift','ProjectEditSyntheticFixtures.swift']:
            text=(ROOT/'Core'/name).read_text()
            self.assertNotIn('URLSession(',text); self.assertNotIn('transport.send(',text); self.assertNotIn('URLRequest(',text)
        self.assertIn('return false',self.coordinator.split('public var canSimulate')[1].split('public init')[0])
        self.assertIn('case disabled, readOnly, approved }',self.service)
        adapter=(ROOT/'Core/ProjectEditHTTPService.swift').read_text()
        for guard in ['approval.allows', 'store.pending', 'dispatchStarted = true', 'fresh.snapshot == baseline', 'return .unknown']: self.assertIn(guard,adapter)
        self.assertIn('service: ProjectEditDisabledService()', (ROOT/'App/AppSession.swift').read_text())
    def test_known_contract_paths_only(self):
        self.assertEqual(set(re.findall(r'"(/api/[^\"]+)"',self.contract)), {'/api/topic/create','/api/topic/update','/api/topic/edit-detail','/api/ai/safety/precheck'})
    def test_source_endpoint_and_whitelist_alignment(self):
        if not SOURCE.exists(): self.skipTest('Flutter source unavailable; do not claim source verification')
        api=(SOURCE/'lib/data/api/publish_api.dart').read_text()
        logic=(SOURCE/'lib/feature/publish/publish_draft_logic.dart').read_text()
        for path in re.findall(r'"(/api/[^\"]+)"',self.contract): self.assertIn("'"+path+"'",api)
        source_keys=re.findall(r"'([^']+)'",logic.split('Map<String, dynamic> whitelistPayload')[1].split('])')[0])
        native_keys=re.findall(r'"([^\"]+)"',self.contract.split('public static let whitelist = [')[1].split(']')[0])
        self.assertEqual(source_keys,native_keys)
    def test_source_replacement_fields_preserved(self):
        if not SOURCE.exists(): self.skipTest('Flutter source unavailable')
        logic=(SOURCE/'lib/feature/publish/publish_draft_logic.dart').read_text()
        carry=logic.split('_chapterCarryOver(PublishChapter c)')[1].split('};')[0]
        native=re.findall(r'"([^\"]+)"',self.contract.split('public static let chapterCarryOver = [')[1].split(']')[0])
        self.assertEqual(set(re.findall(r"'([^']+)'\s*:",carry)),set(native))
    def test_source_local_draft_envelope_and_conflict_evidence(self):
        if not SOURCE.exists(): self.skipTest('Flutter source unavailable')
        source=(SOURCE/'lib/feature/publish/pro_editor_draft_store.dart').read_text()
        for token in ['FlutterSecureStorage','member_mismatch','revision_conflict','draftUuid','baseRevision','topicId']:
            self.assertIn(token,source)
        native=(ROOT/'Core/ProjectEditLocalStore.swift').read_text()
        for token in ['envelope.accountID == session.accountID','envelope.namespace == session.storageNamespace','envelope.identity == identity','envelope.baseRevision != baseline.baseRevision']:
            self.assertIn(token,native)
    def test_durable_pending_precedes_submit_and_uses_active_pointer(self):
        body=self.coordinator.split('public func confirm(')[1]
        self.assertLess(body.index('try store.save(value.draft'),body.index('try store.savePending'))
        self.assertLess(body.index('try store.savePending'),body.index('await service.submit'))
        self.assertIn('if let existing = try store.pending',body)
    def test_unknown_outcome_uses_receipt_not_matching_readback(self):
        body=self.coordinator.split('public func checkOutcome')[1]
        self.assertIn('terminalReceipt',body); self.assertNotIn('submit(',body)
        self.assertIn('operationID == operation.operationID',self.coordinator)
    def test_session_guards_after_each_async_service_return(self):
        for marker in ['let value = try await service.preflight','let check = try await service.preflight','let outcome = await service.submit','let receipt = try await service.terminalReceipt']:
            tail=self.coordinator.split(marker)[1]
            self.assertIn('guard active(session, stamp)',tail[:420])
    def test_secure_storage_has_no_unscoped_or_plaintext_fallback(self):
        text=(ROOT/'App/ProjectEditSecureStorage.swift').read_text()
        for token in ['scope.service + ".project-editor"','kSecAttrAccessibleWhenUnlockedThisDeviceOnly','kSecAttrSynchronizable as String: false','guard let scope']:
            self.assertIn(token,text)
        self.assertNotIn('UserDefaults',text)
    def test_fixture_is_debug_only(self):
        for name in ['Core/ProjectEditSyntheticFixtures.swift','App/ProjectEditFixtureSupport.swift']:
            value=(ROOT/name).read_text().strip(); self.assertTrue(value.startswith('#if DEBUG')); self.assertTrue(value.endswith('#endif'))
    def test_catalog_bilingual_and_all_static_user_keys(self):
        catalog=json.loads((ROOT/'docs/project-edit-localizations.json').read_text())
        for key,value in catalog.items(): self.assertEqual(set(value),{'en','zh-Hans'},key); self.assertTrue(all(value.values()))
        identifiers={'projectEdit.status','projectEdit.restoreStatus','projectEdit.cancelReview','projectEdit.openCity','projectEdit.openFreeExplore','projectEdit.openPublishingModes'}
        for folder in ['App','Core']:
            for path in (ROOT/folder).glob('ProjectEdit*.swift'):
                for key in re.findall(r'"(projectEdit\.[A-Za-z][A-Za-z.]+)"',path.read_text()):
                    if not key.endswith('.') and key not in identifiers: self.assertIn(key,catalog,key)
        validation=(ROOT/'Core/ProjectEditDraft.swift').read_text()
        for key in ['name','description','cover','categories','dates','dateOrder','deadline','chapters','story','nodes','blocks','references','media','coordinates','nodeName','number','merchant','ticketName','price','meeting']:
            self.assertIn('projectEdit.validation.'+key,catalog)
    def test_authoring_inventory_keeps_runtime_distinction(self):
        core=(ROOT/'Tests/CoreTests/ProjectEditTests.swift').read_text(); ui=(ROOT/'Tests/AppUITests/ProjectEditFlowTests.swift').read_text()
        self.assertGreaterEqual(len(re.findall(r'func test\w+',core)),26)
        self.assertEqual(len(re.findall(r'func test\w+',ui)),9)
        self.assertIn('No UI test was run',ui)
    def test_full_edit_locks_and_source_normalizations(self):
        self.assertIn('whitelistLockedFieldsEqual',self.coordinator)
        self.assertIn('"openClubPool"] = .number(0)',self.contract)
        self.assertIn('topicID == nil && draft.publishToCreative',self.contract)
        self.assertIn('draft.product.rawValue',self.contract)
    def test_review_confirmation_never_reports_published_success(self):
        ui=(ROOT/'App/ProjectEditDetailForms.swift').read_text()
        self.assertIn('if canSubmit {',ui)
        self.assertIn('projectEdit.confirmLive',ui)
        self.assertIn('projectEdit.confirmSimulation',ui)
        self.assertNotIn('publishedSuccessfully',ui)
        catalog=json.loads((ROOT/'docs/project-edit-localizations.json').read_text())
        self.assertEqual(catalog['projectEdit.simulated']['en'],'Simulation completed. No project was published.')

if __name__=='__main__': unittest.main()
