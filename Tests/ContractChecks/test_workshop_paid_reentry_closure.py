"""Offline source contracts only, not Swift execution or service/visual acceptance."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PaidInstallReentrySourceContracts(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_exact_original_binding_preserved_except_invalidated_cache_guard(self):
        source = self.text('App/WorkshopPaidInstallSessionBinding.swift')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), '07e7cbed24d6da02ca57b0b4b87e1d06735dcf4e76383e124e752d1456b29e87')
        inserted = ('controller.item == item,\n'
                    '           controller.phase != .invalidated { return controller }\n'
                    '        // An invalidated controller owns a revoked lease. Re-entry must use a fresh\n'
                    '        // controller/read lease after the full checks above, retaining the owner store.')
        self.assertEqual(source.count(inserted), 1)
        original = source.replace(inserted, 'controller.item == item { return controller }')
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), 'cc7e230861b48c9a918e65c4435f1c486a5bd762579b47db008a918852f55168')

    def test_original_context_and_grant_checks_still_precede_cache_and_new_lease(self):
        source = self.text('App/WorkshopPaidInstallSessionBinding.swift')
        guard = source.index('guard let context, let approval, let api')
        cache = source.index('controller.phase != .invalidated')
        lease = source.index('let lease = ContentDraftSessionLease')
        self.assertLess(guard, cache)
        self.assertLess(cache, lease)
        for marker in ['approval.matches(context)', 'currentApproval()?.revision == approval.revision',
                       'ContentDraftContextFence.matches(current(), context)',
                       'api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8)',
                       'captured?.session.role.utf8.elementsEqual(context.session.role.utf8) == true',
                       'revision == approval.revision, let controller, controller.item == item']:
            self.assertIn(marker, source[:cache])

    def test_same_owner_store_and_existing_service_constructor_are_reused(self):
        source = self.text('App/WorkshopPaidInstallSessionBinding.swift')
        self.assertIn('WorkshopPaidInstallPendingStore(storage: storage, context: context, licenseId: item.licenseId)', source)
        self.assertIn('WorkshopPaidInstallService(api: api, transport: transport, lease: lease, approval: approval, currentApproval: currentApproval, onUnauthorized: onUnauthorized)', source)
        self.assertIn('WorkshopPaidInstallController(item: item, service: service, lease: lease, store: store)', source)
        for marker in ['UUID()', 'store.save(', 'store.remove(', 'await ', '.submit(', '.status(', '.history(', '.targets(']:
            self.assertNotIn(marker, source)

    def test_only_invalidated_phase_is_excluded_from_cache(self):
        source = self.text('App/WorkshopPaidInstallSessionBinding.swift')
        self.assertEqual(source.count('controller.phase'), 1)
        self.assertIn('controller.phase != .invalidated { return controller }', source)
        self.assertNotIn('controller.phase =', source)

    def test_retired_controller_and_lease_are_never_revived(self):
        source = self.text('Core/WorkshopPaidInstallController.swift')
        invalidation = source.split('public func invalidate()', 1)[1].split('private func current(', 1)[0]
        self.assertIn('lease.revoke()', invalidation)
        self.assertIn('phase = .invalidated', invalidation)
        self.assertNotIn('store.remove(', invalidation)
        appearance = source.split('public func appear(', 1)[1].split('public func close(', 1)[0]
        self.assertIn('phase != .invalidated', appearance)
        self.assertIn('guard phase != .invalidated else { return }', invalidation)

    def test_original_bounded_503_decoding_and_retirement_remain_in_core(self):
        service = self.text('Core/WorkshopPaidInstallService.swift')
        self.assertIn('guard data.count <= 524_288 else', service)
        self.assertIn('throw code == 503 ? WorkshopPaidInstallIssue.disabled : .unavailable', service)
        source = self.text('Core/WorkshopPaidInstallController.swift')
        self.assertIn('if issue == .unauthorized || issue == .staleSession || issue == .disabled {\n                    self.invalidate()', source)

    def test_upgrade_button_matches_existing_single_request_guard_without_style_dependency(self):
        source = self.text('App/WorkshopModUpgradeSheetView.swift')
        added = '.disabled(confirmedRequestId != nil || !presentation.canConfirmUpgrade(confirmedByBuyer: confirmedByBuyer))'
        self.assertEqual(source.count(added), 1)
        original = source.replace(added, '.disabled(!presentation.canConfirmUpgrade(confirmedByBuyer: confirmedByBuyer))')
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), '2a0e7d4396b71e579fa0fd8a1692989b4fcdd23d3b962e9c419af48ae4339300')
        self.assertIn('guard confirmedRequestId == nil else { return }', source)
        self.assertNotIn('.modWorkflow', source)

    def test_upgrade_request_becomes_confirmed_only_after_original_save_callback(self):
        source = self.text('App/WorkshopModUpgradeSheetView.swift').split('private func submitUpgradeDraft()', 1)[1]
        self.assertLess(source.index('guard confirmedRequestId == nil'), source.index('makeUpgradeDraftRequest'))
        self.assertLess(source.index('try onConfirmDraft(request)'), source.index('confirmedRequestId = request.requestId'))
        self.assertEqual(source.count('confirmedRequestId = nil'), 4)
        self.assertIn('catch WorkshopUpgradeDraftIssue.unavailable', source)

    def test_independent_install_approval_stays_default_nil(self):
        source = self.text('App/AppCompositionRoot.swift')
        self.assertEqual(source.count('workshopPaidInstallApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval? = { _ in nil }'), 2)
        self.assertIn('WorkshopPaidInstallRequest.accepts(request, baseURL: api.baseURL), route != .submit', source)

    def test_pending_persistence_and_protected_text_grant_remain_independent(self):
        source = self.text('Core/WorkshopPaidInstallPendingStore.swift')
        for marker in ['accountID', 'namespace', 'licenseId', 'baseURL']:
            self.assertIn(marker, source)
        binding = self.text('App/WorkshopPaidInstalledTextSessionBinding.swift')
        self.assertIn('guard let context, let approval, let api', binding)
        self.assertIn('approval.matches(context)', binding)
        self.assertNotIn('WorkshopPaidInstallApproval', binding)

if __name__ == '__main__':
    unittest.main()
