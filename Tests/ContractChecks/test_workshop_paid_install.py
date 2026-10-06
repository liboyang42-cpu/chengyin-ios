"""Source/fixture checks only. These do not execute Swift, UIKit, HTTP, or the private backend."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class PaidInstallSourceContracts(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()
    def test_confirmation_binds_source_and_target_not_owner_input(self):
        s = self.read('Core/WorkshopPaidInstallContracts.swift')
        for field in ['requestId', 'licenseId', 'purchasedVersionId', 'contentHash', 'termsHash', 'targetDraftId', 'targetRevision', 'targetPayloadHash', 'planningRegion', 'commercialUse']:
            self.assertIn(field, s)
        for value in ['w18-paid-private-text-install-command-v1', 'UNRESOLVED', 'W18_PRIVATE_COMPONENT_ONLY', 'MATERIALIZATION_REQUIRED']:
            self.assertIn(value, s)
        self.assertNotIn('var ownerId', s)
    def test_existing_paid_metadata_still_cannot_grant_use_or_checkout(self):
        s = self.read('Core/WorkshopPurchasedContracts.swift')
        self.assertIn('permitsContentUse: Bool { false }', s)
        self.assertIn('permitsPurchase: Bool { false }', s)
    def test_independent_approval_is_default_nil_on_normal_root_and_transport(self):
        s = self.read('App/AppCompositionRoot.swift')
        self.assertEqual(s.count('workshopPaidInstallApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval? = { _ in nil }'), 2)
        self.assertEqual(s.count('workshopPaidInstallApproval: workshopPaidInstallApproval'), 2)
        self.assertIn('currentWorkshopPaidInstallApproval', self.read('App/AppSession.swift'))
    def test_general_transport_has_only_read_branch_and_dedicated_write_consumes_once(self):
        s = self.read('App/AppCompositionRoot.swift')
        self.assertIn('WorkshopPaidInstallRequest.accepts(request, baseURL: api.baseURL), route != .submit', s)
        block = s.split('func sendWorkshopPaidInstall(', 1)[1].split('func send(_ request:', 1)[0]
        self.assertLess(block.index('authorization.consume'), block.index('underlying.send'))
        self.assertIn('guard valid()', block)
        self.assertIn('try authorization.validate()', block)
    def test_submit_authorization_rejects_wrong_body_context_token_and_reuse(self):
        s = self.read('Core/WorkshopPaidInstallService.swift')
        for marker in ['guard !consumed', 'revision == approvalRevision', 'request.httpBody == body', 'forHTTPHeaderField: "Authorization"', 'consumed = true', 'context.session.role']:
            self.assertIn(marker, s)
    def test_routes_require_canonical_json_and_bounded_known_length(self):
        s = self.read('Core/WorkshopPaidInstallService.swift')
        for marker in ['(2...4096).contains(data.count)', 'String(data.count)', 'request.httpBodyStream == nil', 'url.query == nil', '"Transfer-Encoding") == nil', '(try? command.wireData()) == data', '(try? body.data()) == data']:
            self.assertIn(marker, s)
    def test_response_parser_reuses_bounded_duplicate_aware_json_validation(self):
        s = self.read('Core/WorkshopPaidInstallContracts.swift')
        self.assertIn('ContentDraftJSON.parse(text)', s)
        self.assertIn('data.count <= maximum', s)
        self.assertIn('values.count < 50', s)
        self.assertIn('zip(items, items.dropFirst())', s)
    def test_pending_record_is_owner_realm_scoped_without_credentials(self):
        s = self.read('Core/WorkshopPaidInstallPendingStore.swift')
        self.assertIn('context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), licenseId', s)
        self.assertNotIn('context.session.token', s)
        self.assertIn('workshop-paid-install.pending.v1.', s)
        self.assertIn('old.wireData() == command.wireData()', s)
        self.assertIn('saved.wireData() == command.wireData()', s)
    def test_only_terminal_matching_receipt_can_acknowledge_pending(self):
        s = self.read('Core/WorkshopPaidInstallPendingStore.swift')
        self.assertIn('outcome.state.terminal', s)
        self.assertIn('outcome.matches(pending)', s)
        c = self.read('Core/WorkshopPaidInstallController.swift')
        self.assertIn('NOT_FOUND never erases a saved UUID', c)
        self.assertNotIn('clearPending', c)
    def test_save_and_phase_claim_precede_task_creation(self):
        s = self.read('Core/WorkshopPaidInstallController.swift').split('public func offerSubmit', 1)[1]
        self.assertLess(s.index('try store.save(confirmation)'), s.index('phase = .submitting'))
        self.assertLess(s.index('phase = .submitting'), s.index('return { [weak self]'))
        self.assertIn('action.claim()', s)
    def test_back_and_stale_appearance_cannot_mint_fresh_action(self):
        s = self.read('Core/WorkshopPaidInstallController.swift')
        self.assertIn('guard !started, !closed', s)
        self.assertIn('displayed.revoke(); guard appearance === displayed', s)
        self.assertIn('self.current(displayed) && action.live', s)
        self.assertIn('phase != .submitting', s)
    def test_modal_binding_and_old_disappearance_are_generation_bound(self):
        s = self.read('App/WorkshopPaidInstallView.swift')
        self.assertIn('let expected = selection?.id', s)
        self.assertIn('guard selection?.id == expected', s)
        self.assertIn('guard selection?.id == captured.id', s)
        self.assertIn('.id(captured.id)', s)
        self.assertIn('controller.close(displayed)', s)
        self.assertIn('controller.appear(displayed)', s)
    def test_current_unauthorized_callback_is_fenced(self):
        s = self.read('Core/WorkshopPaidInstallService.swift')
        self.assertIn('try check(lifetime); onUnauthorized(lease.context)', s)
        self.assertIn('try lifetime.check()', s)
        self.assertIn('lease.isCurrent', s)
        self.assertIn('latest.revision == approval.revision', s)
    def test_normal_account_detail_has_real_factory_and_entry(self):
        self.assertIn('makeInstall: { session.makeWorkshopPaidInstallController(item: $0) }', self.read('App/AccountView.swift'))
        self.assertIn('WorkshopPaidInstallEntry(item: item, makeController: makeInstall, makeProfessional: makeProfessional, makeText: makeText)', self.read('App/WorkshopPurchasedLibraryView.swift'))
        s = self.read('App/AppSession.swift')
        self.assertIn('workshopPaidInstallBinding.invalidate()', s)
        self.assertIn('storage: templateAuthoringSecureStorage', s)
    def test_no_checkout_professional_write_or_direct_network_added(self):
        paths = ['Core/WorkshopPaidInstallContracts.swift', 'Core/WorkshopPaidInstallController.swift', 'Core/WorkshopPaidInstallPendingStore.swift', 'Core/WorkshopPaidInstallService.swift', 'App/WorkshopPaidInstallView.swift']
        s = '\n'.join(self.read(p) for p in paths)
        for absent in ['URLSession.shared', '/api/template/draft', '/api/template/publish', 'StoreKit', 'requestPayment', 'ContentDraftService(']:
            self.assertNotIn(absent, s)
    def test_all_new_copy_is_bilingual_and_explicit_about_scope(self):
        values = json.loads(self.read('Resources/WorkshopPaidInstall.xcstrings'))['strings']
        self.assertEqual(len(values), 58)
        for key, value in values.items():
            self.assertEqual(set(value['localizations']), {'zh-Hans', 'en'}, key)
        for key in ['unknownNote', 'unresolvedMode', 'materializationRequired', 'storageBlocked', 'state.EXPIRED']:
            self.assertIn('workshopPaidInstall.' + key, values)
    def test_real_service_controller_regressions_authored_not_run_here(self):
        s = self.read('Tests/CoreTests/WorkshopPaidInstallTests.swift')
        for marker in ['testSaveReadbackPrecedesDispatch', 'testUnknownCommitIsRecovered', 'testQueuedSubmitAfterBack', 'testCurrent401', 'testClosedWrite401', 'testCorruptPending', 'WorkshopPaidInstallService(', 'CheckedContinuation']:
            self.assertIn(marker, s)
        s = self.read('Tests/AppUnitTests/WorkshopPaidInstallNormalFlowTests.swift')
        for marker in ['AppCompositionRoot(', 'testNormalControllerConfirmation', 'testNormalConfigurationABA', 'testRealHostedInstallModal', 'UIHostingController', 'testNormalTransportNeverAcceptsSubmit', 'testTransportClonePreservesInstallSelector']:
            self.assertIn(marker, s)
