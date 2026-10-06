import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

class WorkshopPaidInstalledTextContracts(unittest.TestCase):
    def test_new_protected_contract_is_separate_and_read_only(self):
        model = read('Core/WorkshopPaidInstalledTextContracts.swift')
        self.assertIn('w18-paid-installed-text-v1', model)
        self.assertIn('OWNER_PAID_INSTALLED_TEXT_PROTECTED_READ_ONLY', model)
        self.assertIn('MATERIALIZATION_REQUIRED', model)
        self.assertIn('UNRESOLVED', model)
        self.assertNotIn('public struct WorkshopPaidInstalledText: Codable', model)
        self.assertIn('WorkshopPaidInstalledText[redacted]', model)
        self.assertIn('WorkshopPaidInstalledTextFields[redacted]', model)

    def test_original_fields_and_opaque_terms_are_integrity_checked(self):
        model = read('Core/WorkshopPaidInstalledTextContracts.swift')
        for field in ['merchantGuide','questionAnswer','hint1','hint2','answerReveal']:
            self.assertIn('"' + field + '"', model)
        self.assertIn('sourceFields == installedFields', model)
        self.assertIn('ContentDraftRecord.hash(sourceJSON) == contentHash', model)
        self.assertIn('ContentDraftRecord.hash(componentJSON) == componentHash', model)
        self.assertIn('SHA256.hash(data: document)', model)
        self.assertIn('document.base64EncodedString().utf8.elementsEqual(encoded.utf8)', model)
        self.assertIn('rights.matches(reference.item)', model)

    def test_independent_approval_defaults_to_nil(self):
        service = read('Core/WorkshopPaidInstalledTextService.swift')
        root = read('App/AppCompositionRoot.swift')
        self.assertIn('approval: WorkshopPaidInstalledTextApproval? = nil', service)
        self.assertIn('current.revision == approval.revision', service)
        self.assertEqual(root.count('workshopPaidInstalledTextApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstalledTextApproval? = { _ in nil }'), 2)
        self.assertGreaterEqual(root.count('workshopPaidInstalledTextApproval: workshopPaidInstalledTextApproval'), 2)
        self.assertIn('WorkshopPaidInstalledTextRequest.accepts(request, baseURL: api.baseURL)', root)

    def test_request_shape_has_no_owner_or_payment_and_no_write_alias(self):
        service = read('Core/WorkshopPaidInstalledTextService.swift')
        shape = service.split('private struct Body: Codable')[1].split('static func body')[0]
        self.assertIn('let requestId: String', shape)
        self.assertIn('let ownedDraftId: Int64', shape)
        self.assertNotIn('owner', shape)
        self.assertNotIn('payment', shape)
        for guard in ['(2...512).contains(data.count)', 'request.httpBodyStream == nil', 'request.cachePolicy == .reloadIgnoringLocalCacheData', '(try? body.data()) == data']:
            self.assertIn(guard, service)
        self.assertIn('try check(lifetime); onUnauthorized(lease.context)', service)
        self.assertIn('data.count <= 2_097_152', service)

    def test_irreversible_captured_actions_fence_queued_calls(self):
        controller = read('Core/WorkshopPaidInstalledTextController.swift')
        for guard in ['guard !started, !closed', 'guard live, !entered', 'action.claim(), self.current(displayed)', 'action.live && self.current(displayed)', 'content = nil']:
            self.assertIn(guard, controller)
        origin = read('Core/WorkshopPaidInstallController.swift')
        capture = origin.split('public func installedTextReference')[1]
        self.assertIn('current(displayed)', capture)
        self.assertIn('outcome == receipt || history.contains(receipt)', capture)

    def test_normal_entry_wires_factory_without_changing_purchase_navigation_lifecycle(self):
        self.assertIn('makeText: { session.makeWorkshopPaidInstalledTextController(reference: $0) }', read('App/AccountView.swift'))
        library = read('App/WorkshopPurchasedLibraryView.swift')
        self.assertIn('WorkshopPaidInstallEntry(item: item, makeController: makeInstall, makeProfessional: makeProfessional, makeText: makeText)', library)
        self.assertIn('navigation.listViewDisappeared(displayed)', library)
        self.assertIn('navigation.detailViewDisappeared(displayed)', library)
        install = read('App/WorkshopPaidInstallView.swift')
        self.assertEqual(install.count('WorkshopPaidInstalledTextEntry(makeReference:'), 2)
        self.assertIn('controller.installedTextReference(receipt, appearance: displayed)', install)

    def test_identity_barrier_invalidates_body_binding_and_canonicalizes_only_its_role(self):
        session = read('App/AppSession.swift')
        self.assertIn('workshopPaidInstalledTextBinding.invalidate()', session)
        context = session.split('private var currentWorkshopPaidInstalledTextContext:')[1].split('private var currentWorkshopPaidInstalledTextApproval:')[0]
        self.assertIn('["player", "club", "merchant"].contains(context.role)', context)
        self.assertIn('token: context.session.token, role: context.role', context)
        method = session.split('func makeWorkshopPaidInstalledTextController')[1].split('/// Independent install protocol')[0]
        self.assertIn('self.workshopReadConfigurationRevision == configurationRevision', method)
        self.assertIn('self.compositionViewerRevision == viewer', method)
        root = read('App/AppCompositionRoot.swift')
        route = root.split('} else if WorkshopPaidInstalledTextRequest.accepts')[1].split('} else if let route = WorkshopPaidInstallRequest')[0]
        self.assertIn('captured.isSignedInContentViewer', route)
        self.assertIn('token: token, role: role', route)
        self.assertIn('fresh.revision == approval.revision', route)

    def test_shared_actual_sheet_presentation_rejects_stale_dismiss(self):
        presenter = read('App/WorkshopPaidInstalledTextPresentation.swift')
        self.assertIn('guard selection?.id == expected', presenter)
        self.assertIn('guard selection === displayed', presenter)
        view = read('App/WorkshopPaidInstalledTextView.swift')
        self.assertIn('presentation.open(makeReference: makeReference, makeController: makeController)', view)
        self.assertIn('presentation.replace($0, expected: expected)', view)
        self.assertIn('controller.close(displayed); ownedTask?.cancel(); onClose()', view)
        for forbidden in ['TemplateAuthoringLocalStore', 'TemplateAuthoringContract.request', 'publishTemplate', '.save(']:
            self.assertNotIn(forbidden, view)
        self.assertIn('.privacySensitive()', view)
        self.assertIn('Text(verbatim: value)', view)

    def test_authored_swift_regressions_are_present_not_claimed_executed(self):
        core = read('Tests/CoreTests/WorkshopPaidInstalledTextTests.swift')
        app = read('Tests/AppUnitTests/WorkshopPaidInstalledTextNormalFlowTests.swift')
        self.assertEqual(core.count('    func test'), 16)
        self.assertEqual(app.count('    func test'), 8)
        self.assertIn('withCheckedContinuation', core)
        self.assertIn('testActualHostedSheetOpensFromSharedEntryAndBackClearsBodyBeforeReopen', app)
        self.assertIn('XCTAssertEqual(context.role,context.session.role)', app)
        self.assertIn('testConfigurationABAInvalidatesBeforeChangeAndOld401CannotLogout', app)

    def test_new_resource_is_bilingual_and_honest_about_missing_materializer(self):
        value = json.loads(read('Resources/WorkshopPaidInstalledText.xcstrings'))
        self.assertEqual(len(value['strings']), 40)
        for entry in value['strings'].values():
            self.assertEqual(set(entry['localizations']), {'zh-Hans','en'})
        text = value['strings']['workshopPaidInstalledText.materializationRequired']['localizations']['en']['stringUnit']['value']
        self.assertIn('Save and publish are unavailable', text)
        self.assertIn('not a professional template ID', text)

if __name__ == '__main__':
    unittest.main()
