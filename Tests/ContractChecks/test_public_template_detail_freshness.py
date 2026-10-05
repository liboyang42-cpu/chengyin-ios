"""Static integration guards only; XCTest execution remains an Apple-toolchain gate."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublicTemplateDetailFreshnessContracts(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / "Core/PublicTopicTemplateDetail.swift").read_text()
        self.session = (ROOT / "App/AppSession.swift").read_text()

    def test_session_coordinator_defers_expiration_to_accepted_failure(self):
        factory = self.session.split("func publicTopicTemplateCoordinator(id: Int)", 1)[1].split(
            "func makePublicTopicTemplateCoordinator", 1)[0]
        self.assertIn("readPublicTopicTemplate(id: id, expiresSession: false)", factory)
        self.assertNotIn("expireIfMatching", factory)
        reader = self.session.split("private func readPublicTopicTemplate", 1)[1].split(
            "func discoveryTopicTemplates", 1)[0]
        self.assertIn("epoch == publicTemplateDetails.epoch", reader)
        self.assertIn("credential == token", reader)
        self.assertIn("guard current(), !Task.isCancelled", reader)
        self.assertIn("if expiresSession { expireIfMatching", reader)

    def test_expiration_callback_uses_captured_epoch_stamp_and_credential(self):
        factory = self.session.split("func makePublicTopicTemplateCoordinator", 1)[1].split(
            "func discoveryTopicTemplateDetail", 1)[0]
        self.assertIn("let stamp = gate.currentStamp, credential = token, epoch = publicTemplateDetails.epoch", factory)
        self.assertIn("self.publicTemplateDetails.epoch == epoch", factory)
        self.assertIn("stamp: stamp, credential: credential", factory)
        self.assertNotIn("credential: self.token", factory)

    def test_generation_and_cancellation_precede_unauthorized_side_effect(self):
        coordinator = self.core.split("public final class PublicTopicTemplateCoordinator", 1)[1].split(
            "public struct PublicTemplateViewerContext", 1)[0]
        handler = coordinator.split("} catch {", 1)[1]
        guard = "guard generation == captured, !isInvalidated, !Task.isCancelled else { return }"
        self.assertLess(handler.index(guard), handler.index("onUnauthorized()"))
        self.assertIn("if error as? APIError == .unauthorized { onUnauthorized() }", handler)
        for method in ("clear", "invalidate"):
            body = coordinator.split(f"public func {method}()", 1)[1].split("    }", 1)[0]
            self.assertIn("generation &+= 1", body)

    def test_current_direct_read_still_expires_and_owner_forwards_callback(self):
        direct = self.session.split("func discoveryTopicTemplateDetail", 1)[1].split(
            "private func readPublicTopicTemplate", 1)[0]
        self.assertIn("readPublicTopicTemplate(id: id, expiresSession: true)", direct)
        owner = self.core.split("public final class PublicTemplateDetailOwner", 1)[1]
        self.assertIn("onUnauthorized: onUnauthorized, read: read", owner)

    def test_app_session_regressions_cover_stale_and_current_failure(self):
        tests = (ROOT / "Tests/AppUnitTests/PublicTemplateDetailAppTests.swift").read_text()
        for name in (
            "testSupersededUnauthorizedCannotExpireSessionOrEraseFreshDetail",
            "testDismissedUnauthorizedCannotExpireSessionAndReopenStillLoads",
            "testCanceledUnauthorizedCannotExpireSession",
            "testCurrentUnauthorizedStillExpiresSessionAndInvalidatesProjection",
        ):
            self.assertIn(f"func {name}", tests)
        self.assertIn("reads: []", tests)
        self.assertIn("XCTAssertNil(session.account); XCTAssertNil(vault.value)", tests)


if __name__ == "__main__":
    unittest.main()
