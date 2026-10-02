"""Executed source checks only; no Swift compilation, HTTP, or Apple runtime."""
import json
import re
import unittest
from pathlib import Path
from flutter_source import read_flutter_source
ROOT = Path(__file__).resolve().parents[2]
# A complete checkout may have any directory name. Packet overlays do not carry
# both build manifests and still use the sibling native host for untouched files.
IS_NATIVE_CHECKOUT = all((ROOT / path).is_file() for path in [
    'Package.swift', 'Questify.xcodeproj/project.pbxproj'])
HOST = ROOT if IS_NATIVE_CHECKOUT else ROOT.parent / 'chengyin-ios'
def read(path):
    local = ROOT / path
    return (local if local.exists() else HOST / path).read_text()

class ExactOwnShelfRepair(unittest.TestCase):
    def test_exact_own_shelf_fields_are_audited(self):
        contract = read('Core/TemplateAuthoringContract.swift')
        for key in ['is_quote','keyword','category_id','pageNum','pageSize','template_id','publish_status']:
            self.assertIn('"'+key+'"',contract)
        for path in ['/api/template/my-list','/api/template/draft','/api/template/publish','/api/template/delete','/api/template/updateLibraryStatus']:
            self.assertIn(path, contract)
        self.assertIn('"pageNum": "1", "pageSize": "100"', contract)
    def test_own_shelf_external_flutter_parity(self):
        source = read_flutter_source(self, 'data/api/template_api.dart')
        for key in ['is_quote','keyword','category_id','pageNum','pageSize','template_id','publish_status']:
            self.assertIn("'"+key+"'", source)
        for path in ['/api/template/my-list','/api/template/draft','/api/template/publish','/api/template/delete','/api/template/updateLibraryStatus']:
            self.assertIn(path, source)
    def test_generic_project_contract_remains_separate(self):
        if ROOT != HOST:
            self.assertFalse((ROOT/'Core/PublishModesContracts.swift').exists())
            self.assertFalse((ROOT/'App/PublishingManagementViews.swift').exists())
    def test_generic_project_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/api/my_project_api.dart')
        self.assertIn("'id':",source)
    def test_concrete_adapter_calls_builder_and_http(self):
        text=read('Core/TemplateAuthoringHTTPTransport.swift')
        self.assertIn('TemplateAuthoringWireRequestBuilder.make(descriptor',text)
        self.assertIn('try await http.send(request)',text)
        self.assertIn('enabled: Bool = false',text)
        self.assertNotIn('URLSession(',text)
        self.assertIn('before.session == expectedSession',text)
        self.assertIn('after.token == before.token',text)
    def test_shipped_factory_remains_off_and_untouched(self):
        if ROOT != HOST: self.assertFalse((ROOT/'App/AppSession.swift').exists())
        factory=read('App/AppSession.swift').split('func templateAuthoringEditor')[1].split('\n    }')[0]
        self.assertIn('TemplateAuthoringAdapter()',factory)
        self.assertNotIn('TemplateAuthoringHTTPTransport',factory)
    def test_request_builder_rejects_generic_identity_and_edit(self):
        text=read('Core/TemplateAuthoringWireRequestBuilder.swift')
        self.assertIn('fields["id"] == nil',text)
        self.assertIn('Set(fields.keys) == expected',text)
        self.assertIn('descriptor == TemplateAuthoringContract.listMine()',text)
    def test_own_shelf_consumes_exact_coordinator(self):
        ui=read('App/TemplateAuthoringMineView.swift')
        for call in ['coordinator.prepareShelf(', 'coordinator.confirmShelf(', 'coordinator.loadMine()', 'coordinator.leaveShelfScreen()']:
            self.assertIn(call,ui)
        self.assertIn('value.templateID.rawValue',ui)
        self.assertNotIn('PublishingService',ui)
    def test_review_requires_fresh_identity_and_no_title_reconciliation(self):
        core=read('Core/TemplateAuthoringCoordinator.swift')
        self.assertIn('fresh.first(where: { $0.id == value.templateID.rawValue }) == value.baseline',core)
        self.assertLess(core.index('try store.saveShelfPending(intent'),core.index('await adapter.submit(value.request)',core.index('public func confirmShelf')))
        self.assertIn('shelfReview == value',core)
        self.assertIn('value.generation == shelfGeneration',core)
    def test_unknown_cannot_be_reconciled_and_full_page_is_capped(self):
        core=read('Core/TemplateAuthoringShelf.swift')
        self.assertIn('guard acknowledged else { return false }',core)
        self.assertIn('rows.count < 100 && matches.isEmpty',core)
        self.assertIn('$0.id == templateID.rawValue',core)
        self.assertNotIn('$0.title',core)
    def test_journal_scoped_and_backward_compatible(self):
        core=read('Core/TemplateAuthoringStorage.swift')
        self.assertIn('key(session, "own-shelf-pending")',core)
        self.assertIn('value.ownerKey == session.ownerKey',core)
        self.assertIn('public var acknowledged: Bool? = nil',core)
    def test_all_new_labels_are_bilingual(self):
        labels=json.loads((ROOT/'docs/template-authoring-repair-localizations.json').read_text())
        baseline=json.loads((HOST/'Resources/Localizable.xcstrings').read_text())['strings']
        keys=set()
        for path in list((ROOT/'App').glob('*.swift'))+list((ROOT/'Core').glob('*.swift')):
            keys |= set(re.findall(r'"(templateAuthor\.[A-Za-z.]+)"',re.sub(r'\.accessibilityIdentifier\([^\n]*?\)', '', path.read_text())))
        for key,value in labels.items():
            self.assertEqual(set(value),{'en','zh-Hans'}); self.assertTrue(all(value.values()))
        for key in keys:
            if key.endswith('.') or key in ['templateAuthor.status','templateAuthor.shelf.status','templateAuthor.field.','templateAuthor.diceFace.']: continue
            self.assertTrue(key in labels or key in baseline,key)
    def test_no_public_hierarchy_or_existing_edit_added(self):
        if ROOT != HOST:
            self.assertFalse((ROOT/'App/DiscoveryTemplateBrowserView.swift').exists())
            self.assertFalse((ROOT/'App/SessionHomeFeedView.swift').exists())
        self.assertIn('templateAuthor.existingEditUnavailable',read('App/TemplateAuthoringMineView.swift'))
    def test_fake_and_ui_tests_are_authored(self):
        core=read('Tests/CoreTests/TemplateAuthoringHTTPTests.swift')
        self.assertIn('class HTTP: HTTPTransport',core)
        self.assertIn('testUnknownPersistsAfterNewCoordinatorAndMatchingReadback',core)
        ui=read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift')
        self.assertIn('--template-author-shelf',ui)
        self.assertIn('testUnknownLocksBothActionsAcrossReopen',ui)

if __name__ == '__main__': unittest.main(verbosity=2)
