"""Offline source wiring checks. Swift/XCTest and Apple UI execution are separate gates."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SignedInContentDetailContracts(unittest.TestCase):
    def test_independent_typed_opt_in_and_exact_routes(self):
        root = (ROOT / "App/AppCompositionRoot.swift").read_text()
        route = (ROOT / "Core/SignedInContentDetailRead.swift").read_text()
        self.assertIn("contentDetails: SignedInContentDetailReadApproval? = nil", root)
        branch = root.split("} else if let route = SignedInContentDetailReadRoute", 1)[1].split("} else", 1)[0]
        self.assertIn("deployment.contentDetails == .activityAndTopic", branch)
        self.assertIn("captured.isSignedInContentViewer", branch)
        self.assertIn("route.accepts(request)", branch)
        self.assertNotIn("homeAndSearch", branch)
        for path in ("api/activity/info", "api/topic/info-to-user"):
            self.assertIn('"' + path + '"', route)
        for proof in ('request.httpMethod == "POST"', "request.httpBodyStream == nil", "url.query == nil", "url.fragment == nil", "id > 0", "String(id) == value", "canonical.httpBody == body"):
            self.assertIn(proof, route)
        launch = (ROOT / "App/RegionalLaunchConfiguration.swift").read_text()
        self.assertNotIn(".activityAndTopic", launch)

    def test_activity_and_topic_session_fence_identity_only_aba_before_401(self):
        session = (ROOT / "App/AppSession.swift").read_text()
        detail = session.split("func activityDetail(id:Int)", 1)[1].split("private func expireIfMatching", 1)[0]
        self.assertIn("guard account != nil, let credential = token", detail)
        self.assertEqual(detail.count("viewerRevision == compositionViewerRevision"), 2)
        catch = detail.split("} catch {", 1)[1]
        self.assertLess(catch.index("!Task.isCancelled"), catch.index("expireIfMatching"))
        self.assertIn("viewerRevision:compositionViewerRevision", session)
        topic = (ROOT / "Core/TopicReading.swift").read_text()
        self.assertIn("lhs.viewerRevision == rhs.viewerRevision", topic)
        self.assertIn("guard currentSession() != nil else { throw APIError.unauthorized }", topic)

    def test_server_gate_and_response_identity_are_preserved(self):
        activity = (ROOT / "Core/ActivityService.swift").read_text()
        self.assertIn("if case .allowed(let detail) = response.access, detail.summary.id != id", activity)
        self.assertIn("return response.access", activity)
        topic = (ROOT / "Core/TopicContracts.swift").read_text()
        self.assertIn("public let activities: [TopicActivitySummary]?", topic)
        self.assertIn('decodeIfPresent([TopicActivitySummary].self, forKey: TopicKey("activityList"))', topic)
        self.assertIn("Set(activities.map(\\.id)).count != activities.count", topic)
        shelf = topic.split("public struct TopicActivitySummary", 1)[1].split("public struct TopicDetail", 1)[0]
        for key in ("id", "name", "imgUrl", "addressName", "startDate", "endDate"):
            self.assertIn(key, shelf)
        self.assertNotIn("isOwner", shelf)
        self.assertNotIn("memberId", shelf)

    def test_normal_destinations_observe_context_and_shelf_routes_exact_id(self):
        activity = (ROOT / "App/ActivityDetailView.swift").read_text()
        self.assertIn("@ObservedObject var session: AppSession", activity)
        self.assertIn("if session.account == nil", activity)
        self.assertIn(".id(session.contentDetailRevision)", activity)
        topic = (ROOT / "App/PlatformConsumerSessionOwner.swift").read_text()
        self.assertIn("activityDestination: { AnyView(ActivityDetailView(id: $0, reader: session)) }", topic)
        self.assertIn(".id(session.contentDetailRevision)", topic)
        view = (ROOT / "App/TopicDetailView.swift").read_text()
        self.assertIn("activityDestination(activity.id)", view)
        self.assertIn("if let activities = value.activities", view)
        self.assertIn('Text("topic.noActivities")', view)

    def test_authored_core_app_and_ui_cover_contract_and_normal_composition(self):
        core = (ROOT / "Tests/CoreTests/SignedInContentDetailTests.swift").read_text()
        app = (ROOT / "Tests/AppUnitTests/SignedInContentDetailAppTests.swift").read_text()
        ui = (ROOT / "Tests/AppUITests/SignedInContentDetailFlowTests.swift").read_text()
        fixture = (ROOT / "App/SignedInContentDetailFixtureHost.swift").read_text()
        for proof in ("testOnlyTwoExactCanonicalMultipartIDRoutes", "testActivityCorrelatesAllowedDetailButPreservesRedactedClubGate", "testTopicShelfPreservesOmittedEmptyAndExactSummaryFields"):
            self.assertIn(proof, core)
        for proof in ("testGuestAndHomeOnlyApprovalNeverDispatchDetails", "testMalformedShapesPartialIdentitiesAndOtherPathsNeverReachWire", "testOwnerSwitchRoleABAAndSessionABARejectLateSuccessAnd401", "testCurrentHTTPAndEnvelope401ExpireButCanceled401DoesNot"):
            self.assertIn(proof, app)
        for proof in ("testHomeTopicShelfOpensExactActivityDetailAndBackReopens", "testActivitiesCardUsesNormalSessionDetailAndRetry", "testTopicActivityClubGateNeverShowsFullDetailOrActions", "testGuestCardsShowSignInWithZeroDetailRequests"):
            self.assertIn(proof, ui)
        self.assertIn("root.makeSession()", fixture)
        self.assertIn("SessionHomeFeedView()", fixture)
        self.assertIn("ActivityBrowserView(reader: session)", fixture)
        self.assertNotIn("URLSession", fixture)
        self.assertTrue(fixture.startswith("#if DEBUG"))

    def test_every_detail_reload_is_owned_and_canceled_before_disappearance(self):
        owner = (ROOT / "Core/SignedInContentDetailRead.swift").read_text()
        for proof in ("public final class SignedInContentDetailLoadOwner", "task?.cancel(); task = nil",
                      "let owned = start(operation)", "withTaskCancellationHandler", "owned.cancel()"):
            self.assertIn(proof, owner)
        for path in ("App/ActivityDetailView.swift", "App/TopicDetailView.swift"):
            view = (ROOT / path).read_text()
            for proof in ("@State private var loads = SignedInContentDetailLoadOwner()", "await loads.run { await load() }",
                          "loads.start { await load() }", ".onDisappear { loads.cancel();"):
                self.assertIn(proof, view)
            self.assertNotIn("Task { await load() }", view)
            # Preserve the NavigationLink subtree while its child is on screen.
            disappear = view.split(".onDisappear {", 1)[1].split("}", 1)[0]
            self.assertNotIn("access = nil", disappear)
            self.assertNotIn("detail = nil", disappear)
        topic = (ROOT / "App/TopicDetailView.swift").read_text()
        self.assertIn(".refreshable { await loads.run { await load() } }", topic)

    def test_review_tests_cover_same_session_late_401_and_current_forbidden(self):
        app = (ROOT / "Tests/AppUnitTests/SignedInContentDetailAppTests.swift").read_text()
        for name in ("testCurrent403IsAnErrorWithoutExpiringTheSignedInSession",
                     "testViewOwnedDismissalAndReplacementDropLate401InTheSameSession",
                     "testRestoredSessionUsesAuthoritativeAccountBeforeDetailDispatch",
                     "testTopicShelfOmittedEmptyAndMalformedStayDistinctInNormalComposition"):
            self.assertIn(name, app)
        ui = (ROOT / "Tests/AppUITests/SignedInContentDetailFlowTests.swift").read_text()
        for name in ("testDismissedTopicRetryCannotExpireTheCurrentSessionAndReopenStillWorks",
                     "testDismissedActivityRetryCannotExpireTheCurrentSessionAndReopenStillWorks",
                     "testCurrent403ShowsErrorWithoutSigningOutOrRenderingDetail",
                     "testUnknownShelfDoesNotClaimNoActivities"):
            self.assertIn(name, ui)
        self.assertIn("maximumSwipes: Int", (ROOT / "Tests/AppUITests/FailureScreenshot.swift").read_text())
        self.assertNotIn("maxSwipes:", ui)


if __name__ == "__main__":
    unittest.main()
