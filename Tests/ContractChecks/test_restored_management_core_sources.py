"""Source-level restoration checks only. Not Swift compilation or runtime acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class RestoredManagementCoreSources(unittest.TestCase):
    def test_friend_callbacks_cannot_continue_a_retired_visit(self):
        expected = {"NativeFriendFlow": 10, "NativeBlacklistFlow": 7,
                    "NativeFriendMetadataFlow": 4, "NativeFriendRemovalFlow": 5}
        for name, count in expected.items():
            with self.subTest(name=name):
                text = (ROOT / "Core" / (name + ".swift")).read_text()
                lines = text.splitlines()
                positions = [i for i, line in enumerate(lines) if "try await service." in line]
                self.assertEqual(len(positions), count)
                self.assertTrue(all(lines[i - 1].strip() == "try requireCurrentVisit(stamp)" for i in positions))
                self.assertIn("guard generation == stamp, isCurrent, !Task.isCancelled", text)
                self.assertIn("private func requireCurrentVisit(_ stamp: UInt64) throws", text)
    def test_webhook_routes_keep_deployment_prefix_and_exact_approval(self):
        route = (ROOT / "Core/NativeWebhookRuntimeRoute.swift").read_text()
        self.assertIn("binding.origin.appendingPathComponent(String(path.dropFirst()))", route)
        self.assertNotIn("parts.path = path", route)
        self.assertIn('!path.contains("%")', route)
        self.assertIn('!path.contains("//")', route)
        provider = (ROOT / "Core/NativeWebhookScopeProvider.swift").read_text()
        self.assertNotIn("String(url.path.dropFirst())", provider)
        self.assertIn("approval.paths.contains", provider)
        self.assertIn("canonical.absoluteString.utf8.elementsEqual(targetURL.absoluteString.utf8)", provider)
        self.assertIn("approval.namespace.utf8.elementsEqual(captured.session.namespace.utf8)", provider)
    def test_unknown_webhook_receipts_stay_fail_closed(self):
        service = (ROOT / "Core/NativeWebhookHTTPService.swift").read_text()
        inbound = service.split("public func inboundLogs", 1)[1].split("public func changeRequest", 1)[0]
        self.assertIn("row.result == row.state", inbound)
        self.assertIn("row.senderType == 4 && row.messageID != nil", inbound)
        self.assertIn("row.messageID == nil && row.senderType == nil && row.webhookID == nil", inbound)
        self.assertNotIn(".received", inbound)
        self.assertNotIn(".unknown", inbound)
    def test_independent_callback_and_prefix_regressions_are_present(self):
        friend = (ROOT / "Tests/CoreTests/NativeFriendRestoredCallbackBoundaryTests.swift").read_text()
        self.assertEqual(friend.count("    func test"), 8)
        self.assertEqual(friend.count("f.onChange = { if f.busy"), 8)
        webhook = (ROOT / "Tests/CoreTests/NativeWebhookRestoredBoundaryTests.swift").read_text()
        self.assertIn("testRuntimeAuthorizerMatchesExactApprovedRelativePathUnderDeploymentPrefix", webhook)
        self.assertIn("testManagementContextSourceAndResourceRouteShareDeploymentPrefix", webhook)

if __name__ == "__main__":
    unittest.main()
