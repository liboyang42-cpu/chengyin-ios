"""Source contracts for restored original lifecycle/recovery. Not Swift or live-operation tests."""
from pathlib import Path
import hashlib
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PaidInstallLifecycleSourceContracts(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def core(self): return self.text('Core/WorkshopPaidInstallController.swift')

    def test_core_matches_exact_original_functional_artifact(self):
        self.assertEqual(hashlib.sha256(self.core().encode()).hexdigest(), '37555360a063c6b279dd217c89d83fb3465ebe1b14ded1386c28dbf12b738983')

    def test_original_pending_status_precedes_optional_collection_reads(self):
        source = self.core().split('public func offerLoad(', 1)[1].split('private func offerPage(', 1)[0]
        self.assertLess(source.index('self.store.load()'), source.index('self.service.status'))
        self.assertLess(source.index('self.service.status'), source.index('self.service.history'))
        self.assertLess(source.index('self.service.history'), source.index('self.service.targets'))
        self.assertIn('guard self.pending?.belongs(to: self.item) != false', source)
        self.assertIn('try self.accept(status, expected: pending)', source)
        self.assertNotIn('.submit(', source)

    def test_optional_history_failure_never_suppresses_revocation(self):
        source = self.core().split('let recoveringOriginalRequest', 1)[1].split('if self.item.status', 1)[0]
        self.assertIn('if !recoveringOriginalRequest || issue == .unauthorized || issue == .staleSession || issue == .disabled { throw issue }', source)
        self.assertIn('try life.check()', source)
        self.assertIn('self.issue = issue', source)

    def test_background_retires_only_presentation_and_preserves_original_store(self):
        source = self.core().split('public func suspend(', 1)[1].split('public func resume(', 1)[0]
        for marker in ['appearance === displayed', '!displayed.closed', 'phase != .invalidated',
                       'displayed.suspended = true', 'displayed.action?.revoke()', 'lifetime?.revoke()',
                       'confirmation = nil; target = nil; region = nil']:
            self.assertIn(marker, source)
        for forbidden in ['store.', 'pending = nil', 'UUID()', 'lease.revoke()', 'submit(']:
            self.assertNotIn(forbidden, source)

    def test_resume_is_same_original_read_not_auto_submit_or_new_command(self):
        source = self.core().split('public func resume(', 1)[1].split('private func offer(', 1)[0]
        for marker in ['appearance === displayed', '!displayed.closed', 'displayed.suspended',
                       'phase != .invalidated', 'return offerLoad(displayed)']:
            self.assertIn(marker, source)
        for forbidden in ['UUID()', 'store.', 'submit(', 'WorkshopPaidInstallCommand(']:
            self.assertNotIn(forbidden, source)

    def test_queued_and_late_actions_check_suspended_appearance(self):
        source = self.core()
        self.assertIn('appearance?.suspended == false && appearance?.action === self', source)
        self.assertIn('appearance === displayed && !displayed.closed && !displayed.suspended', source)
        self.assertIn('guard lease.isCurrent else { invalidate(); return false }', source)

    def test_normal_view_scene_hooks_use_same_captured_appearance(self):
        source = self.text('App/WorkshopPaidInstallView.swift')
        for marker in ['@State private var isVisible = false', '@Environment(\\.scenePhase) private var scenePhase',
                       '.disabled(scenePhase != .active)', 'let displayed = appearance',
                       'if scenePhase == .active { schedule(action) }', 'else { controller.suspend(displayed) }',
                       'controller.suspend(displayed); ownedTask?.cancel(); ownedTask = nil',
                       'else if isVisible { schedule(controller.resume(displayed)) }',
                       'guard isVisible, scenePhase == .active, let action else { return }',
                       '.onDisappear { isVisible = false; controller.close(displayed); ownedTask?.cancel(); ownedTask = nil }']:
            self.assertIn(marker, source)

    def test_original_core_tests_keep_all_original_added_recovery_and_lifecycle_cases(self):
        source = self.text('Tests/CoreTests/WorkshopPaidInstallTests.swift')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), 'bef5d0ad5af63a87f06febff5b516c45f96aa25716d960f087964eef7e33e81d')
        self.assertEqual(len(re.findall(r'func test\w+\(', source)), 47)

    def test_original_reentry_tests_are_registered_byte_exact_not_rewritten(self):
        source = self.text('Tests/AppUnitTests/WorkshopPaidInstallReentryTests.swift')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), '6e77fe385e2c95849ea223c97732b6e5b78cc635179b3e6d02c449a0fd6509fa')
        self.assertEqual(len(re.findall(r'func test\w+\(', source)), 11)
        self.assertIn('Tests/AppUnitTests/WorkshopPaidInstallReentryTests.swift', self.text('Questify.xcodeproj/project.pbxproj'))

    def test_scene_aware_normal_flow_test_uses_existing_unchanged_real_scene_helper(self):
        source = self.text('Tests/AppUnitTests/WorkshopPaidInstallNormalFlowTests.swift')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), '051f07f093a3eba034b2ce6ac1fd69e62ce6ca3eef6566c149ecf3156fa05c7f')
        self.assertIn('let sceneWindow = try HostedNavigationSceneWindow()', source)
        helper = self.text('Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift')
        self.assertIn('UIWindow(windowScene: selected)', helper)
        self.assertIn('$0.activationState == .foregroundActive', helper)

    def test_original_service_and_journal_are_unchanged(self):
        expected = {'Core/WorkshopPaidInstallService.swift': 'b6dc5652fc7e0ee729561d3dcfa81416b3cd519b93f20f35d51e5412b16900a7',
                    'Core/WorkshopPaidInstallPendingStore.swift': '75c30df61b46eae069830744d86d892bd86a5080226fb7dc476d2b2df5c0722e',
                    'Core/WorkshopPaidInstallContracts.swift': '8199990ace9dc67c8ad7dc9ea58ecbe51f7e673791f5ac186923bb961ea9f8fd'}
        for path, digest in expected.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)

    def test_independent_install_and_protected_text_grants_stay_separate(self):
        source = self.text('App/AppCompositionRoot.swift')
        self.assertEqual(source.count('workshopPaidInstallApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval? = { _ in nil }'), 2)
        self.assertIn('WorkshopPaidInstallRequest.accepts(request, baseURL: api.baseURL), route != .submit', source)
        text_binding = self.text('App/WorkshopPaidInstalledTextSessionBinding.swift')
        self.assertIn('guard let context, let approval, let api', text_binding)
        self.assertIn('approval.matches(context)', text_binding)

if __name__ == '__main__': unittest.main()
