"""Fixture source contracts; Swift lifecycle and simulator tests remain Apple-only."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubFixtureIdentityContractTests(unittest.TestCase):
    def test_companions_are_owned_by_the_state_object_and_synchronized_before_publish(self):
        source = (ROOT / "App/ClubFixtureSupport.swift").read_text()
        self.assertTrue(source.startswith("#if DEBUG"))
        self.assertIn("@StateObject private var reader: ClubFixtureReader", source)
        root, reader = source.split("final class ClubFixtureReader", 1)
        self.assertNotIn(".onAppear", root)
        self.assertNotIn(".onChange", root)
        for name in ["profileReader", "squareReader", "governanceAccess"]:
            self.assertIn("reader." + name, root)
            self.assertIn("let " + name + " =", reader)
        self.assertIn("synchronizeCompanions(with: clubIdentity)", reader)
        self.assertIn("synchronizeCompanions(with: identity)\n        clubIdentity = identity", reader)
        self.assertIn("governanceAccess.allowsOfflineWrites = false", reader)
        self.assertIn("scenario == .customerDenied ? .forbidden : nil", reader)

    def test_production_member_context_guards_remain_exact(self):
        source = (ROOT / "App/ClubMembersView.swift").read_text()
        for required in ["identity.isSignedIn && context.reader.identity.accountID == identity.accountID && context.reader.identity.epoch == identity.epoch",
                         "governance?.access.identity == identity", "target.viewerRevision == governance?.viewerRevision",
                         "target.identity == reader.clubIdentity", "target.memberID > 0, id > 0"]:
            self.assertIn(required, source)

    def test_outcomes_are_revealed_without_replacing_their_exact_assertions(self):
        source = (ROOT / "Tests/AppUITests/MerchantOperationsFlowTests.swift").read_text()
        for target in ["saved", "issue"]:
            self.assertIn(f"revealFixtureElement({target}, in: app, requiresHittable: false)", source)
            self.assertIn(f"{target}.waitForExistence(timeout: 4)", source)
        self.assertIn('XCTAssertEqual(saved.label, "Offline example saved. No real business change was made.")', source)
        self.assertIn('XCTAssertEqual(issue.label, "The example outcome is unknown. Saving is locked; reading again does not prove that the earlier operation failed.")', source)
        self.assertGreaterEqual(source.count("assertReviewLocked(app)"), 2)

if __name__ == "__main__":
    unittest.main()
