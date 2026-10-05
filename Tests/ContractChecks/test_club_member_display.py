"""Member presentation wiring only; Swift/XCUITest execution is a separate gate."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ClubMemberDisplayTests(unittest.TestCase):
    def test_optional_facts_belong_only_to_member_projection(self):
        source = (ROOT / "Core/ClubContracts.swift").read_text()
        member = source.split("public struct ClubMember:", 1)[1].split("public struct ClubHome:", 1)[0]
        self.assertIn("decodeIfPresent(Int.self, forKey: .levelId)", member)
        self.assertIn("decodeIfPresent(String.self, forKey: .joinTime)", member)
        self.assertIn("guard let levelId, levelId > 0", member)
        self.assertIn("guard !isOwner", member)
        self.assertNotIn("DateFormatter", member)
        self.assertNotIn("phone", member)
        self.assertNotIn("paidAmount", member)

    def test_both_profile_destinations_share_the_existing_scoped_row(self):
        source = (ROOT / "App/ClubMembersView.swift").read_text()
        for token in ["try await reader.clubMembers(id: id)", "requiresSignIn: true",
                      "if let level = member.displayedLevel", "if let joined = member.displayedJoinTime",
                      'Text("club.memberLevel \\(level)")', 'Text("club.memberJoined \\(joined)")',
                      "target.identity == reader.clubIdentity", "target.viewerRevision == governance?.viewerRevision",
                      "SocialPublicProfileView(memberID: target.memberID", "ClubGovernanceReadView(operation: .customer"]:
            self.assertIn(token, source)
        self.assertNotIn("HTTPTransport", source)
        self.assertNotIn("DateFormatter", source)

    def test_metadata_is_bilingual_with_exact_interpolation_types(self):
        strings = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        expected = {
            "club.memberLevel %lld": {"en": "Level %lld", "zh-Hans": "等级 %lld"},
            "club.memberJoined %@": {"en": "Joined %@", "zh-Hans": "加入 %@"},
        }
        for key, languages in expected.items():
            for language, value in languages.items():
                self.assertEqual(strings[key]["localizations"][language]["stringUnit"]["value"], value)

    def test_behavioral_unit_cases_are_authored(self):
        source = (ROOT / "Tests/CoreTests/ClubContractTests.swift").read_text()
        for name in ["testMemberDisplayUsesOnlyReturnedLevelAndJoinTime",
                     "testMemberDisplayOmitsMissingNullAndNonpositiveLevels",
                     "testMemberDisplayDoesNotLimitValidSourceLevelToClubHostLevels",
                     "testMemberDisplayOmitsMissingNullAndBlankJoinTimes",
                     "testMemberDisplayKeepsServerDateTextWithoutTimezoneGuess",
                     "testCreatorDisplaySuppressesJoinTimeButKeepsReturnedLevel",
                     "testAdministratorDisplayDoesNotHideJoinTimeOrPromoteOwner",
                     "testMalformedMemberDisplayTypesFailWithoutCoercion"]:
            self.assertIn("func " + name, source)

    def test_existing_ui_flow_asserts_display_and_suppression(self):
        source = (ROOT / "Tests/AppUITests/ModuleFlowTests.swift").read_text()
        for token in ['creator.contains("Level 7")', 'creator.contains("2026-01-01")',
                      'administrator.contains("Level 4")', 'administrator.contains("Joined 2026-02-03 10:15:00")',
                      'ordinary.contains("Level 0")', 'ordinary.contains("Joined")']:
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()
