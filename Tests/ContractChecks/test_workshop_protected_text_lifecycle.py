"""Offline contracts for original protected-text lifecycle. No Swift/runtime acceptance implied."""
from pathlib import Path
import hashlib
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ProtectedTextLifecycleSourceContracts(unittest.TestCase):
    def text(self, p): return (ROOT / p).read_text()
    def service(self): return self.text('Core/WorkshopPaidInstalledTextService.swift')
    def controller(self): return self.text('Core/WorkshopPaidInstalledTextController.swift')

    def test_all_product_bytes_match_original_protected_consumer_delivery(self):
        expected = {'App/WorkshopPaidInstalledTextView.swift': '126e43db7cbf33a42e0a00744aea091c60d5326e4652016ade749195046b8e3d',
                    'Core/WorkshopPaidInstalledTextController.swift': '59a3b8f70eb5631e596d96bd9cd074ac9e9ef9415b58822b11c59caac55ca3dc',
                    'Core/WorkshopPaidInstalledTextService.swift': 'b042ebf2507250a7b3429611826cc2d7604a67db3b079d3d3cce0dfa8399c3a8'}
        for p, expected_hash in expected.items():
            self.assertEqual(hashlib.sha256((ROOT / p).read_bytes()).hexdigest(), expected_hash)

    def test_visible_permission_check_uses_original_complete_grants_and_one_clock_read(self):
        source = self.service().split('public func validateReadPermission()', 1)[1].split('private func check(', 1)[0]
        for marker in ['guard lease.isCurrent', 'let instant = now()', 'current.revision == approval.revision',
                       'current.matches(lease.context, now: instant)', 'approval.matches(lease.context, now: instant)',
                       'WorkshopPaidInstallWire.same(api.baseURL.absoluteString, lease.context.baseURL.absoluteString)']:
            self.assertIn(marker, source)
        self.assertEqual(source.count('now()'), 1)
        for forbidden in ['await ', 'transport.', 'UUID()', 'install(', 'store.', 'journal', 'detail(']:
            self.assertNotIn(forbidden, source)

    def test_original_network_reads_check_lifetime_before_and_after_local_authority(self):
        self.assertIn('try lifetime.check(); try validateReadPermission(); try lifetime.check()', self.service())
        detail = self.service().split('public func detail(', 1)[1]
        self.assertIn('try check(lifetime)', detail)
        self.assertIn('api/workshop/purchased/installed-text/detail', detail)

    def test_background_erases_body_and_retires_original_read_action(self):
        source = self.controller().split('public func suspend(', 1)[1].split('public func resume(', 1)[0]
        for marker in ['appearance === displayed', '!displayed.closed', 'phase != .invalidated',
                       'displayed.suspended = true', 'displayed.action?.revoke()', 'lifetime?.revoke()',
                       'content = nil', 'phase = .idle']:
            self.assertIn(marker, source)
        for forbidden in ['reference =', 'UUID()', 'lease.revoke()', 'store.', 'submit(']:
            self.assertNotIn(forbidden, source)

    def test_foreground_uses_only_same_reference_and_existing_protected_read(self):
        source = self.controller().split('public func resume(', 1)[1].split('public func refreshVisiblePermission(', 1)[0]
        self.assertIn('appearance === displayed, !displayed.closed, displayed.suspended', source)
        self.assertIn('return offerReload(displayed)', source)
        self.assertIn('public let reference: WorkshopPaidInstalledTextReference', self.controller())
        self.assertIn('self.service.detail(self.reference, lifetime: life)', self.controller())
        self.assertNotIn('UUID()', source)

    def test_idle_expiry_or_revocation_clears_current_body_without_business_operation(self):
        source = self.controller().split('public func refreshVisiblePermission(', 1)[1].split('public func offerReload(', 1)[0]
        self.assertIn('guard current(displayed) else { return false }', source)
        self.assertIn('try service.validateReadPermission()', source)
        self.assertIn('invalidate(); issue =', source)
        invalidation = self.controller().split('public func invalidate()', 1)[1].split('private func current(', 1)[0]
        self.assertIn('content = nil; phase = .invalidated', invalidation)
        self.assertNotIn('store.', invalidation)

    def test_queued_and_late_reads_cannot_borrow_foreground_presentation(self):
        source = self.controller()
        self.assertIn('appearance?.suspended == false && appearance?.action === self', source)
        self.assertIn('appearance === displayed && !displayed.closed && !displayed.suspended', source)
        self.assertIn('guard action.live, self.current(displayed) else { return }', source)
        self.assertIn('try life.check(); guard body.matches(self.reference)', source)

    def test_native_view_hides_body_before_async_cleanup(self):
        source = self.text('App/WorkshopPaidInstalledTextView.swift')
        self.assertLess(source.index('if scenePhase != .active'), source.index('else if let content = controller.content'))
        self.assertIn('controller.suspend(displayed); ownedTask?.cancel()', source)
        self.assertIn('if phase == .active { schedule(controller.resume(displayed)) }', source)
        self.assertIn('.privacySensitive()', source)

    def test_one_second_observer_only_checks_captured_permission_locally(self):
        source = self.text('App/WorkshopPaidInstalledTextView.swift').split('.task(id: scenePhase)', 1)[1].split('private func schedule(', 1)[0]
        self.assertIn('guard scenePhase == .active else { return }', source)
        self.assertIn('try await Task.sleep(for: .seconds(1))', source)
        self.assertIn('guard !Task.isCancelled, controller.refreshVisiblePermission(displayed)', source)
        for forbidden in ['.detail(', '.submit(', '.offerReload(', 'store.', 'UUID()']:
            self.assertNotIn(forbidden, source)

    def test_original_fixture_and_sixteen_core_tests_are_byte_exact_and_new_tests_separate(self):
        original = (ROOT / 'Tests/CoreTests/WorkshopPaidInstalledTextTests.swift').read_bytes()
        self.assertEqual(hashlib.sha256(original).hexdigest(), 'ac130d781fe695be5da659d6d1a22626ca116c973c17677ce6a0736d8052a79c')
        self.assertEqual(len(re.findall(rb'func test\w+\(', original)), 16)
        new = self.text('Tests/CoreTests/WorkshopPaidInstalledTextLifecycleTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', new)), 7)
        old = original.decode()
        helpers = old[old.index('    @MainActor private final class Wire:'):old.index('    func testExactProtectedSource')]
        self.assertIn(helpers, new)
        self.assertNotIn('static let source', new)
        self.assertNotIn('protocol ', new)

    def test_independent_read_grant_stays_default_off_and_cannot_come_from_receipt(self):
        root = self.text('App/AppCompositionRoot.swift')
        self.assertEqual(root.count('workshopPaidInstalledTextApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstalledTextApproval? = { _ in nil }'), 2)
        binding = self.text('App/WorkshopPaidInstalledTextSessionBinding.swift')
        self.assertIn('guard let context, let approval, let api', binding)
        self.assertIn('approval.matches(context)', binding)
        self.assertNotIn('WorkshopPaidInstallApproval', binding)

    def test_only_existing_real_service_conforms_to_changed_protocol(self):
        matches = []
        for folder in ['App', 'Core', 'Tests']:
            for p in (ROOT / folder).rglob('*.swift'):
                for name in re.findall(r'(?:class|struct|enum)\s+(\w+)\s*:\s*[^\n{]*\bWorkshopPaidInstalledTextReading\b', p.read_text()):
                    matches.append((str(p.relative_to(ROOT)), name))
        self.assertEqual(matches, [('Core/WorkshopPaidInstalledTextService.swift', 'WorkshopPaidInstalledTextService')])

if __name__ == '__main__': unittest.main()
