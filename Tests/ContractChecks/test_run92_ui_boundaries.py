"""Source regression only; actual Apple geometry/lifetime execution remains required."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class Run92UIBoundaryChecks(unittest.TestCase):
    def test_fixture_issuer_is_retained_with_session_and_wire(self):
        source = (ROOT / "App/OwnedOrderFixtureHost.swift").read_text()
        self.assertIn("@State private var grants: OwnedOrderFixtureGrants", source)
        self.assertIn("_grants=State(initialValue:grants)", source)
        self.assertIn("wire.issuer = grants", source)
        self.assertIn("ownedOrderReadApproval:{grants.approval($0)}", source)
        self.assertEqual(source.count("issuer === grants"), 2)
        host = source.split("private struct OwnedOrderFixtureGrantControls", 1)[0]
        self.assertNotIn("@ObservedObject", host)
        self.assertNotIn("actionEvidence", host)
        self.assertNotIn("@Published private(set) var retained", source)
        self.assertIn("@ObservedObject var grants", source)
        self.assertIn("retained?.revoke()", source)
        self.assertIn("approval.expireIfNeeded(now: approval.expiresAt)", source)
    def test_issuer_diagnostics_refresh_only_after_new_approval(self):
        source = (ROOT / "App/OwnedOrderFixtureHost.swift").read_text()
        issuance = source.split("func approval(_ context:", 1)[1].split("@MainActor private final class OwnedOrderFixtureVault", 1)[0]
        self.assertEqual(source.count("objectWillChange.send()"), 1)
        self.assertIn("if retained == nil || !ContentDraftContextFence.matches", issuance)
        self.assertIn("Task { @MainActor [weak self, weak issued] in", issuance)
        self.assertIn("guard !Task.isCancelled, let self, let issued", issuance)
        self.assertIn("self.retained === issued, !issued.isRevoked else { return }", issuance)
        host = source.split("private struct OwnedOrderFixtureGrantControls", 1)[0]
        self.assertNotIn(".onReceive", host)
        self.assertNotIn("@StateObject private var grants", host)
        self.assertNotIn("objectWillChange", host)
        test = (ROOT / "Tests/AppUITests/OwnedOrderFlowTests.swift").read_text()
        self.assertIn('actions=0;retained=true;revoked=false;bound=true', test)
        self.assertIn('actions=1;retained=true;revoked=true;bound=true', test)
        self.assertIn('cleared(privateTitle)', test)

    def test_counter_does_not_poll_covered_first_match(self):
        source = (ROOT / "Tests/AppUITests/ClubOperationsFlowTests.swift").read_text()
        count = source.split("private func count(_ value: Int)", 1)[1].split("private func reviewSetting", 1)[0]
        self.assertIn("self.visibleWriteCounters", count)
        self.assertIn("counters.count == 1", count)
        self.assertIn("counters[0].label == String(value)", count)
        self.assertIn("timeout: 5", count)
        self.assertNotIn("object: writeCounter", source)
    def test_order_path_checks_native_geometry_and_hittability(self):
        source = (ROOT / "Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift").read_text()
        row = source.split('if id == "profile.order.41"', 1)[1].split('XCTAssertTrue(revealFixtureElement', 1)[0]
        for assertion in ["navigation.frame.maxY", "tabs.frame.minY", "element.isEnabled", "element.isHittable", "orderRowFits(element.frame", "element.tap()"]:
            self.assertIn(assertion, row)
        self.assertNotIn("coordinate(", row)
