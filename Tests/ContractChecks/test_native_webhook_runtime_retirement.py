"""Static Core wiring checks, not compiled Swift or App final-forward proof."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class WebhookRuntimeRetirement(unittest.TestCase):
    def test_once_binding_and_monotone_restrictions(self):
        text = (ROOT / 'Core/NativeWebhookCoordinator.swift').read_text()
        bind = text.split('public func bindRuntimeRetirement', 1)[1].split('private func visitIsCurrent', 1)[0]
        self.assertIn('guard runtimeRetirement == nil else { return false }', bind)
        self.assertIn('existing() && presentationIsCurrent()', bind)
        self.assertIn('existing() && restriction()', bind)
        self.assertIn('if !presentationIsCurrent() { invalidate() }', bind)
    def test_retirement_precedes_all_lifecycle_callbacks(self):
        text = (ROOT / 'Core/NativeWebhookCoordinator.swift').read_text()
        for method in ['invalidate', 'background']:
            body = text.split('public func ' + method + '() {', 1)[1]
            self.assertEqual(body.lstrip().splitlines()[0], 'runtimeRetirement?()')
        self.assertIn('public func leave() { invalidate() }', text)
    def test_cookie_and_authorization_cancellation_fences(self):
        text = (ROOT / 'Core/NativeWebhookHTTPService.swift').read_text()
        exchange = text.split('private func exchange(', 1)[1]
        self.assertIn('request.httpShouldHandleCookies = false', exchange)
        self.assertIn('!authorized.httpShouldHandleCookies', exchange)
        self.assertIn('!reauthorized.httpShouldHandleCookies', exchange)
        lines = exchange.splitlines()
        for i, line in enumerate(lines):
            if 'try await authorizer.authorize' in line:
                self.assertEqual(lines[i - 1].strip(), 'try Task.checkCancellation()')
                self.assertEqual(lines[i + 1].strip(), 'try Task.checkCancellation()')
            if 'try await transport.send(authorized)' in line:
                self.assertEqual(lines[i - 1].strip(), 'try Task.checkCancellation()')
    def test_confirm_checks_after_callback_before_journal_and_after_service(self):
        text = (ROOT / 'Core/NativeWebhookCoordinator.swift').read_text()
        confirm = text.split('public func confirm(', 1)[1].split('public func clearSecret()', 1)[0]
        self.assertLess(confirm.index('changed()'), confirm.index('guard visitIsCurrent(stamp)'))
        self.assertLess(confirm.index('guard visitIsCurrent(stamp)'), confirm.index('try journal.reserve(operation)'))
        after = confirm.split('try await service.perform(operation)', 1)[1]
        self.assertLess(after.index('guard visitIsCurrent(stamp)'), after.index('try journal.settle(operation)'))
        tests = (ROOT / 'Tests/CoreTests/NativeWebhookRuntimeRetirementTests.swift').read_text()
        self.assertEqual(tests.count('    func test'), 12)

if __name__ == '__main__': unittest.main()
