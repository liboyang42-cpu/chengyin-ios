"""Static navigation fences; Apple execution is a separate gate."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class ClubMemberProfileNavigationTests(unittest.TestCase):
    def test_real_member_destination_and_target(self):
        source = (ROOT / "App/ClubMembersView.swift").read_text()
        self.assertIn("SocialPublicProfileView(memberID: target.memberID", source)
        self.assertIn("memberID: member.memberId, identity: reader.clubIdentity", source)
        self.assertIn("member.memberId > 0", source)
        self.assertIn("navigationDestination(item: $destination)", source)

    def test_identity_fences_and_existing_membership_read(self):
        source = (ROOT / "App/ClubMembersView.swift").read_text()
        for token in ["requiresSignIn: true", "try await reader.clubMembers(id: id)",
                      "target.identity == reader.clubIdentity", "context.reader.identity.accountID == identity.accountID",
                      "context.reader.identity.epoch == identity.epoch", "destination = nil"]:
            self.assertIn(token, source)
        self.assertNotIn("HTTPTransport", source)

    def test_normal_composition_supplies_existing_profile(self):
        source = (ROOT / "App/ClubDetailView.swift").read_text()
        self.assertIn("profile: management?.governance?.enrollmentProfile", source)
        session = (ROOT / "App/AppSession.swift").read_text()
        self.assertIn("enrollmentProfile: .init(reader: socialAccountReader, squareReader: squareReader", session)

    def test_fixture_covers_back_and_identity_reset(self):
        source = (ROOT / "Tests/AppUITests/ModuleFlowTests.swift").read_text()
        self.assertIn("testClubMemberPublicProfileReturnsAndReopens", source)
        self.assertIn("for memberID in [703, 704]", source)
        self.assertIn("testClubMemberProfileClearsOnSignOut", source)

if __name__ == "__main__":
    unittest.main()
