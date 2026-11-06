"""Static boundary regression checks; does not substitute for Swift runtime tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class RestoredManagementBoundaries(unittest.TestCase):
    def test_every_mutating_leaf_fences_both_suspensions(self):
        for name in ("Role", "Moderation", "PersonalState"):
            with self.subTest(name=name):
                text = (ROOT / "Core" / f"NativeChannel{name}Flow.swift").read_text()
                self.assertIn("private var generation: UInt64 = 0", text)
                self.assertIn("public func deactivate() { generation &+= 1;", text)
                self.assertIn("run == generation && isCurrent && !Task.isCancelled", text)
                exchange = text.split("private func exchange(", 1)[1]
                before_source, after_source = exchange.split("try await channels.currentChannelContext", 1)
                self.assertIn("let run = generation", before_source)
                self.assertIn("guard valid(run)", before_source)
                before_transport, after_transport = after_source.split("try await transport.send(request)", 1)
                compact = before_transport.replace(" ", "")
                self.assertGreaterEqual(compact.count("guardvalid(run),permits(method,path)"), 2)
                self.assertIn("guard valid(run), permits(method,path)", after_transport)
                self.assertLess(after_transport.index("guard valid(run)"), after_transport.index("if status == 401"))
                self.assertLess(after_transport.index("if status == 401"), after_transport.index("JSONSerialization.jsonObject"))
    def test_audit_401_is_after_visit_fence_before_json(self):
        text = (ROOT / "Core/NativeChannelAuditFlow.swift").read_text()
        chunks = text.split("try await transport.send(request)")[1:]
        self.assertEqual(len(chunks), 2)
        for chunk in chunks:
            self.assertLess(chunk.index("run == generation"), chunk.index("if status == 401"))
            self.assertLess(chunk.index("if status == 401"), chunk.index("JSONSerialization.jsonObject"))
    def test_runtime_regressions_present(self):
        text = (ROOT / "Tests/CoreTests/NativeChannelManagementRestoredBoundaryTests.swift").read_text()
        for method in ("testExactEndpointRevokedDuringSourceRefreshNeverDispatches", "testEndpointRevokedDuringResponseCannotPublish", "testDeactivateReactivateDuringSourceRefreshCannotDispatchOldVisit", "testDeactivateReactivateDuringResponseCannotPublishOldVisit", "testBareHTTP401ExpiresCurrentButNotOldVisit", "testOldVisitAppliedResponsePreservesOriginalJournal"):
            self.assertIn("func " + method, text)

if __name__ == "__main__":
    unittest.main()
