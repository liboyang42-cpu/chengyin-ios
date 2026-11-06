"""Native source contracts only; not Swift compilation, UI, or live-service evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class ActivityParityW206P2Checks(unittest.TestCase):
    def test_detail_topic_links_are_navigation_only(self):
        view = read("App/OfficialEventDetailView.swift")
        self.assertIn("OfficialDetailTopicLinks.linkedTopic(event.missions[mission.index], signed: event.signed == true)", view)
        self.assertIn("OfficialDetailTopicLinks.ctaTopic(event, cta: presentation.cta)", view)
        self.assertIn("guard let topicLinks, reader.isAuthenticated, !ids.isEmpty else { return }", view)
        self.assertIn("topicLinks.reader.topicDetail(id: id)", view)
        # Signup stays with the reviewed participation actions; topics never dispatch writes.
        self.assertIn("OfficialParticipationActions(coordinator: actions, event: event, onReturn:", view)
        self.assertIn("topicLinks:OfficialTopicLinks(reader:session.topicReader", read("App/SessionHomeFeedView.swift"))
        self.assertIn("topicLinks: topicLinks)", read("App/OfficialEventsBrowserView.swift"))

    def test_failure_copies(self):
        self.assertIn("OfficialDetailServiceFailure.matches(error)", read("App/OfficialEventDetailView.swift"))
        inbox = read("App/OfficialPrivateViews.swift")
        self.assertIn("issueCopy: OfficialInboxView.issueCopy", inbox)
        self.assertIn("guard case .failed = OfficialScreenIssue(error) else { return nil }", inbox)

    def test_registration_entries_are_read_only(self):
        sheet = read("App/RegistrationSheetView.swift")
        self.assertIn("if let mySignupsDestination {", sheet)
        self.assertIn("flow.uncertainOutcomeEvidence(orders: reader)", sheet)
        check = sheet.split("private struct RegistrationUncertainOrdersCheck", 1)[1]
        for forbidden in ["confirm(", "retry", "create(", "unlock"]:
            self.assertNotIn(forbidden, check.split("var body", 1)[1].split("Text(\"registration.w206.matchNotProof\")", 1)[0])
        self.assertIn('.environment(\\.registrationMySignupsDestination, { AnyView(SessionPlayerJourneyView(destination: .participations)) })', read("App/QuestifyApp.swift"))

    def test_keys_exist_in_both_languages(self):
        catalog = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        sources = "".join(read(p) for p in ["App/OfficialEventDetailView.swift", "App/OfficialPrivateViews.swift", "App/RegistrationSheetView.swift"])
        keys = set(re.findall(r'"((?:official|registration)\.w206\.[A-Za-z.]+)"', sources))
        keys |= {"official.w206.detail.boundTopic %@", "registration.w206.matchingOrders %lld"}
        self.assertGreaterEqual(len(keys), 12)
        for key in sorted(keys):
            self.assertIn(key, catalog, key)
            for language in ("en", "zh-Hans"):
                self.assertTrue(catalog[key]["localizations"][language]["stringUnit"]["value"].strip(), (key, language))


if __name__ == "__main__":
    unittest.main()
