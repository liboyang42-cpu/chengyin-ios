#!/usr/bin/env python3
"""Local source assertions, not Swift compilation, runtime or live-backend evidence."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

class OfficialSourceChecks(unittest.TestCase):
    def test_only_seven_source_backed_read_routes(self):
        service = read("Core/OfficialEventService.swift")
        routes = set(re.findall(r'"(api/official/[^"\n]+)"', service))
        expected = {"api/official/events", r"api/official/events/\(id)", "api/official/my-events", "api/official/v2/party-inbox", "api/official/can-publish", "api/official/my-published", r"api/official/broadcast/\(id)/stats"}
        self.assertEqual(routes, expected)
        self.assertEqual(re.findall(r'httpMethod\s*=\s*"([A-Z]+)"', service), ["GET"])
        self.assertNotIn("request.httpBody =", service)
    def test_read_module_has_no_write_or_real_configuration(self):
        services = "\n".join(p.read_text() for p in (ROOT / "Core").glob("OfficialEvent*.swift"))
        for forbidden in ["api/official/publish", "/signup\"", "/complete\"", "/arrivals\"", "/click\"", "/accept\"", "/decline\"", "URLSession.shared", "Keychain", "UserDefaults"]:
            self.assertNotIn(forbidden, services)
        self.assertNotIn("APIConfiguration(baseURL", read("Core/OfficialEventService.swift"))
    def test_official_and_ordinary_activities_stay_separate(self):
        browser = read("App/OfficialEventsBrowserView.swift")
        self.assertNotIn("ActivityBrowserView(", browser)
        self.assertNotIn("api/activity/", read("Core/OfficialEventService.swift"))
        models = read("Core/OfficialEventContracts.swift")
        self.assertIn("value.status == 2 || value.status == 3", models)
        self.assertIn("value.status == 1", models)
        self.assertIn("(value.status ?? -1) >= 5", models)
    def test_session_guards_and_private_guest_short_circuit(self):
        reader = read("Core/OfficialEventReading.swift")
        self.assertIn("guestEpoch: UInt64", reader)
        self.assertIn("fileprivate let token: String?", reader)
        self.assertIn("currentContext() == context, scope == captured", reader)
        self.assertIn("guard !Task.isCancelled", reader)
        self.assertIn("guard isAuthenticated else { throw APIError.unauthorized }", reader)
        self.assertIn("context.isAuthenticated { onUnauthorized(context) }", reader)
        self.assertIn("current != snapshot", reader.replace("context != snapshot", "current != snapshot"))
    def test_view_scope_and_generation_isolation(self):
        screen = read("App/OfficialEventComponents.swift")
        self.assertIn("loadedKey != key || loading", screen)
        self.assertIn("generation == operation, key == captured", screen)
        self.assertIn(".task(id: key)", screen)
        self.assertIn(".onDisappear { generation &+= 1", screen)
        detail = read("App/OfficialEventDetailView.swift")
        self.assertIn("reader.isAuthenticated ? event.participationKey : event.statusKey", detail)
        self.assertIn("if reader.isAuthenticated", detail)
    def test_permission_business_code_and_status_field_semantics(self):
        service = read("Core/OfficialEventService.swift")
        self.assertIn('envelope?.code == 401', service)
        self.assertIn('无官方发布权限', service)
        self.assertIn('通知不存在', service)
        self.assertIn('guard code == 200 else', service)
        model = read("Core/OfficialEventContracts.swift")
        self.assertIn('status = c.text("status")', model)
        self.assertNotIn('c.text("state")', model)
    def test_every_static_user_facing_key_has_two_languages(self):
        catalog = json.loads(read("docs/official-event-localizations.json"))["strings"]
        ignored = {"official.issue", "official.browser", "official.filter", "official.event.", "official.detail.content", "official.participationState", "official.mission.", "official.invite.", "official.inbox.content", "official.broadcast.", "official.published.content", "official.stats.content", "official.fixture.guest", "official.fixture.account", "official.bucket."}
        literals = set()
        for directory in ["App", "Core"]:
            for path in (ROOT / directory).glob("Official*.swift"):
                literals.update(re.findall(r'"(official\.[A-Za-z0-9_.]+)"', path.read_text()))
        self.assertFalse((literals - ignored) - set(catalog), (literals - ignored) - set(catalog))
        for key, entry in catalog.items():
            for language in ["en", "zh-Hans"]:
                self.assertTrue(entry["localizations"][language]["stringUnit"]["value"], key)
    def test_common_card_and_no_unbounded_animations(self):
        text = read("App/OfficialEventComponents.swift") + read("App/OfficialEventsBrowserView.swift")
        self.assertIn("QuestifyImageEntityCard", text)
        self.assertIn("QuestifyCardButtonStyle", text)
        for forbidden in ["Timer.publish", "repeatForever", ".animation(", "withAnimation("]:
            self.assertNotIn(forbidden, "\n".join(p.read_text() for p in (ROOT / "App").glob("Official*.swift")))
        self.assertIn("ForEach(visible)", text)
        self.assertIn(".frame(minHeight: 44)", text)
    def test_fixtures_are_valid_synthetic_json_without_remote_media(self):
        source = read("Core/OfficialEventSyntheticFixtures.swift")
        fixtures = re.findall(r'#"""\n(.*?)\n\s*"""#', source, re.S)
        self.assertEqual(len(fixtures), 5)
        for fixture in fixtures:
            json.loads(fixture)
            self.assertNotIn("https://", fixture)
            self.assertNotIn("token", fixture.lower())
        self.assertEqual(json.loads(json.loads(fixtures[0])["rewardJson"])["settleXp"], 25)
    def test_integrated_session_preserves_regional_and_cn_protected_gates(self):
        session = read("App/AppSession.swift")
        start = session.index('if let scope, let regional, let configuration=regional.apiConfiguration')
        end = session.index('} else {', start)
        self.assertIn('officialEventService=OfficialEventService(configuration:configuration,transport:transport)', session[start:end])
        self.assertIn('officialEventService=nil', session[end:])
        self.assertIn('self.currentOfficialContext == captured', session)
        self.assertIn('OfficialReadContext(guestEpoch:gate.currentStamp)', session)
        self.assertIn('private let accountSessionService: CNAccountSessionService?', session)
        self.assertIn('growthCenterService=GrowthCenterService', session)
    def test_integrated_entry_scope_fixture_and_catalog(self):
        home = read("App/SessionHomeFeedView.swift")
        self.assertEqual(home.count('accessibilityIdentifier("homeFeed.openOfficialEvents")'), 1)
        self.assertIn('.id(session.officialEventReader.scope)', home)
        self.assertIn('.onChange(of:session.officialEventReader.scope)', home)
        self.assertIn('case .officialEvents: OfficialFixtureHostView()', read("App/ModuleFixtureSupport.swift"))
        expected = json.loads(read("docs/official-event-localizations.json"))["strings"]
        actual = json.loads(read("Resources/Localizable.xcstrings"))["strings"]
        for key, value in expected.items(): self.assertEqual(actual[key], value)
        issue = read("App/OfficialEventComponents.swift")
        self.assertNotIn('}.padding().accessibilityIdentifier("official.issue")', issue)
    def test_authored_tests_cover_lifecycle_and_ui_states(self):
        core = read("Tests/CoreTests/OfficialEventTests.swift")
        ui = read("Tests/AppUITests/OfficialEventFlowTests.swift")
        self.assertGreaterEqual(len(re.findall(r'func test\w+', core)), 20)
        self.assertEqual(len(re.findall(r'func test\w+', ui)), 10)
        for text in ["testAccountEpochTokenAndGuestTransitionsDropSuccessAnd401", "testGuestEpochChangeInvalidatesPublicReadEvenAfterRoundTrip", "testCancelledReadNeverExpiresCurrentSession"]:
            self.assertIn(text, core)
        self.assertIn("testSignOutImmediatelyHidesPrivateInvitationsAndCanReenter", ui)
        self.assertIn("testPublisherDenialIsNotRetryableFailure", ui)
        self.assertNotRegex(core, r'XCTAssert\w+\(try await')

if __name__ == "__main__":
    unittest.main(verbosity=2)
