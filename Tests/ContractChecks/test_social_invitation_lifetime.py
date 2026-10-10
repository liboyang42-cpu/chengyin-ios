"""Invitation history source contracts only; these do not execute Swift or SwiftUI."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InvitationHistoryLifetimeContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "App/SocialInviteHistoryView.swift").read_text()
        self.view, self.model = self.source.split("@MainActor final class SocialInviteHistoryModel", 1)
        self.tests = (ROOT / "Tests/AppUnitTests/SocialPresentationIdentityAppTests.swift").read_text()

    def test_visible_lifetime_starts_synchronously_and_all_entrypoints_are_owned(self):
        for required in ["@StateObject private var model = SocialInviteHistoryModel()",
                         "let binding = model.bind(reader)", "let permit = model.permit(reader)",
                         ".onAppear { model.appear(reader) }",
                         ".onChange(of: binding) { _, _ in model.replaceReader(reader) }",
                         ".refreshable { await model.refresh(reader, permit: permit) }",
                         ".onDisappear { model.suspend() }"]:
            self.assertIn(required, self.view)
        self.assertEqual(self.view.count("model.start(reader, permit: permit,"), 2)
        self.assertNotIn("Task {", self.view)
        self.assertNotIn(".task(", self.view)
        self.assertNotIn("loadedIdentity", self.view)

    def test_owner_visibility_reader_identity_revision_and_config_are_separate_fences(self):
        for required in ["let owner: UUID", "let presentation: UUID", "let key: SocialReadPresentationKey",
                         "private let owner = UUID()", "presentation: UUID(), binding: binding",
                         "presentation.owner == owner", "presentation.binding.key == Self.key(reader)", "presentation.binding == boundReader",
                         "self.permit(reader) == permit && requestID == request"]:
            self.assertIn(required, self.model)
        key = (ROOT / "App/SocialAccountComponents.swift").read_text().split("struct SocialReadPresentationKey", 1)[1].split("@MainActor struct SocialReadScreen", 1)[0]
        for required in ["ObjectIdentifier(reader)", "identity = reader.identity",
                         "revision = reader.presentationRevision", "configured = reader.isConfigured"]:
            self.assertIn(required, key)
        self.assertIn('request: "invitation-history", requiresSignIn: true', self.model)

    def test_hidden_work_cannot_restart_but_navigation_link_rows_are_retained(self):
        suspend = self.model.split("func suspend()", 1)[1].split("@discardableResult", 1)[0]
        self.assertIn("presentation = nil; requestID = nil", suspend)
        self.assertIn("task?.cancel(); task = nil; loading = false", suspend)
        for forbidden in ["pagination =", "scan =", "loadedBinding ="]:
            self.assertNotIn(forbidden, suspend)
        replace = self.model.split("func replaceReader", 1)[1].split("func suspend", 1)[0]
        self.assertIn("guard presentation != nil else { return nil }", replace)
        self.assertLess(self.view.index("!model.matches(reader)"), self.view.index("ForEach(groups"))
        self.assertIn("NavigationLink", self.view)

    def test_start_rejects_stale_permits_and_overlapping_pagination_before_mutation(self):
        start = self.model.split("func start(", 1)[1].split("func refresh(", 1)[0]
        for required in ["self.permit(reader) == permit", "!loading || reset", "reset || pagination.hasMore"]:
            self.assertIn(required, start)
            self.assertLess(start.index(required), start.index("task?.cancel()"))
        self.assertIn("let request = UUID(); requestID = request", start)
        self.assertIn("let page = pagination.nextPage", start)
        self.assertEqual(start.count("let work = Task"), 1)
        self.assertIn("task = work", start)
        refresh = self.model.split("func refresh(", 1)[1].split("private func owns", 1)[0]
        self.assertIn("guard !Task.isCancelled", refresh)
        self.assertIn("withTaskCancellationHandler", refresh)
        self.assertIn("work.cancel()", refresh)

    def test_success_error_401_and_completion_each_keep_the_current_owner_fence(self):
        load = self.model.split("private func load(", 1)[1]
        self.assertEqual(load.count("owns(reader, permit: permit, request: request)"), 4)
        self.assertEqual(load.count("try Task.checkCancellation()"), 2)
        end = load.split("defer {", 1)[1].split("        do {", 1)[0]
        self.assertLess(end.index("if owns("), end.index("loading = false"))
        catch = load.split("catch {", 1)[1]
        self.assertLess(catch.index("!Task.isCancelled, owns("), catch.index("APIError == .unauthorized"))
        self.assertLess(catch.index("!Task.isCancelled, owns("), catch.index("self.error = error"))
        self.assertIn("try pagination.accept(value.page); scan = value.rewardScan", load)

    def test_adversarial_app_tests_use_held_real_operations_not_sleep_races(self):
        for required in [
            "testSameIdentityCloseReopenRejectsOldSuccessFailure401AndCompletion",
            "testSameIdentityReaderReplacementRejectsOldResultsAndQueuedActions",
            "testSamePresentationRefreshSupersedesOldRequestWithoutOldDeferClearingBusy",
            "testLateSuccessAndErrorsWhileClosedCannotPublishOrRestart",
            "testCoveredNavigationRetainsRowsButNoActionsAndReappearanceReloadsPageOne",
            "testForeignOwnerCannotUsePermitEvenWithSameReader",
            "testAccountRoleEpochRevisionAndConfigurationChangesImmediatelyHideOldPresentation",
            "testGuestAndUnconfiguredReadersNeverDispatch",
            "testDuplicateAppearAndLoadMoreDispatchOnceAndRetryKeepsExactPage",
            "testCurrentUnauthorizedClearsPrivateRowsWhileOrdinaryFailureDoesNot",
            "testCurrentSuccessPreservesUnknownRewardAndSeparateTotal",
            "testCancelledRefreshCannotPublishLateUnauthorizedOrOrdinaryError",
            "testClosedReadCannotExpireSessionFromLateHTTPOrEnvelope401",
            "testCurrentHTTPOrEnvelope401StillExpiresSessionAndShowsSignInError",
            "testRenderBindingRetiresOldReaderBeforeOnChangeIncludingSession401SideEffects",
            "testRenderBindingABAReplacesLifetimeEvenBeforeAnyOnChangeRuns",
        ]:
            self.assertIn("func " + required, self.tests)
        section = self.tests.split("final class SocialInvitationHistoryLifetimeAppTests", 1)[1]
        self.assertNotIn("Task.sleep", section)
        self.assertIn("for outcome in 0..<3", section)
        self.assertIn("withCheckedThrowingContinuation", self.tests)
        self.assertIn("SocialAccountSessionReader(", section)
        self.assertIn("XCTAssertEqual(expirations, 0)", section)
        self.assertIn("XCTAssertEqual(expirations, 1)", section)
        self.assertEqual(len(re.findall(r"func test\w+\(", section)), 16)

    def test_render_binding_is_nonpublished_and_cancels_before_lifecycle_rebind(self):
        bind = self.model.split("func bind(", 1)[1].split("func matches(", 1)[0]
        self.assertIn("private var boundReader: ReaderBinding?", self.model)
        self.assertIn("let id = UUID()", self.model)
        self.assertIn("boundReader = current", bind)
        self.assertLess(bind.index("boundReader = current"), bind.index("task?.cancel()"))
        for forbidden in ["pagination =", "scan =", "loading =", "error =", "presentation =", "loadedBinding ="]:
            self.assertNotIn(forbidden, bind)
        self.assertLess(self.view.index("let binding = model.bind(reader)"), self.view.index("let permit = model.permit(reader)"))
        self.assertIn("binding.key == key, presentation?.binding != binding", self.model)

    def test_existing_target_wiring_and_read_only_scope_are_retained(self):
        project = (ROOT / "Questify.xcodeproj/project.pbxproj").read_text()
        self.assertIn("App/SocialInviteHistoryView.swift", project)
        self.assertIn("Tests/AppUnitTests/SocialPresentationIdentityAppTests.swift", project)
        for forbidden in ["URLSession", "HTTPTransport", "SocialActionService(", "Approval(", "UserDefaults"]:
            self.assertNotIn(forbidden, self.source)
        self.assertEqual(self.model.count("reader.invitationHistory(page:"), 1)


if __name__ == "__main__":
    unittest.main()
