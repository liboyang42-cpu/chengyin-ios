"""Offline source checks only; these do not execute SwiftUI navigation."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ActivityTopicNavigationChecks(unittest.TestCase):
    def test_allowed_detail_only_and_exact_topic_identity(self):
        view = (ROOT/'App/ActivityDetailView.swift').read_text()
        self.assertIn('case .allowed(let detail):\n                    detailContent(detail)', view)
        self.assertIn('if let topicID = detail.summary.linkedTopicID, let topicDestination', view)
        self.assertIn('NavigationLink { topicDestination(topicID) }', view)
        gate = view.split('case .clubRequired', 1)[1].split('case .allowed', 1)[0]
        self.assertNotIn('topicDestination', gate)
        self.assertNotIn('ShareLink', view)
    def test_existing_session_destination_and_lifetime_are_retained(self):
        view = (ROOT/'App/ActivityDetailView.swift').read_text()
        self.assertIn('topicDestination: { AnyView(SessionTopicDetailView(id: $0, session: session)) }', view)
        self.assertIn('if session.account == nil', view)
        self.assertIn('.id(session.contentDetailRevision)', view)
        self.assertIn('.onDisappear { loads.cancel(); generation += 1; loading = false }', view)
        topic = (ROOT/'App/PlatformConsumerSessionOwner.swift').read_text()
        for value in ['reader: session.topicReader', 'if session.account == nil', '.id(session.contentDetailRevision)']:
            self.assertIn(value, topic)
    def test_route_is_safe_integer_and_has_no_external_payload(self):
        model = (ROOT/'Core/ActivitySummary.swift').read_text()
        self.assertIn('topicID > 0, topicID <= 9_007_199_254_740_991', model)
        body = model.split('public var linkedTopicID', 1)[1].split('public var hasValidCoordinates', 1)[0]
        for prohibited in ['latitude', 'longitude', 'token', 'memberId', 'URL(']: self.assertNotIn(prohibited, body)
    def test_authored_boundary_navigation_and_failure_coverage(self):
        unit = (ROOT/'Tests/CoreTests/ActivityContractTests.swift').read_text()
        for name in ['testLinkedTopicRequiresPositiveSafeIdentifier', 'testClubGateDoesNotDecodeHiddenTopicLink']: self.assertIn(name, unit)
        ui = (ROOT/'Tests/AppUITests/SignedInContentDetailFlowTests.swift').read_text()
        for name in ['testActivityTopicRouteBackAndReopen', 'testActivityTopicRouteClearsOnRoleChangeAndSignOut', 'testActivityTopicFailureStaysInTopicAndBackReopens']: self.assertIn(name, ui)

    def test_role_refresh_assertions_match_scoped_screen_without_assuming_pop(self):
        ui = (ROOT/'Tests/AppUITests/SignedInContentDetailFlowTests.swift').read_text()
        flow = ui.split('func testActivityTopicRouteClearsOnRoleChangeAndSignOut()', 1)[1].split('func testActivityTopicFailure', 1)[0]
        self.assertLess(flow.index('Synthetic merchant route'), flow.index('app.navigationBars["Route details"].buttons.firstMatch.tap()'))
        for proof in ['"contentDetail.fixture.requests"', '"signed-in"', '"guest"', 'XCTAssertGreaterThan(reopenedReads, 3', 'Sign-out must not dispatch a detail read', '"topic.detail.content"']:
            self.assertIn(proof, flow)
        self.assertIn('attachFailureScreenshot(self, app: launchedApp)', ui)
        self.assertNotIn('destroys its pushed destination', flow)
