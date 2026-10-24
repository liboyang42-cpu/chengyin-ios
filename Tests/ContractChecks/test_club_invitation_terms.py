"""Club invitation display source contracts; these do not execute Swift or UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "App/ClubInvitationFeedbackView.swift"


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


def require_scoped_terms(source):
    projection = span(source, "static func project(", "@MainActor final class")
    for token in ["for row in snapshot.rows", "invitations[row.id.direction.rawValue].rows",
                  'raw["id"].integer == row.id.invitationID', '== row.topicID',
                  'raw["toType"].text == "club"', 'raw["toId"].integer == snapshot.clubID',
                  "row.topicID != nil", "matches.count == 1", "result[row.id] = try Self(raw)"]:
        if token not in projection:
            raise AssertionError("Lost terms scope: " + token)
    access = span(source, "func terms(for target:", "func leave(")
    for token in ["accepted(context, clubReader: clubReader, reader: reader, access: access)",
                  "target.isCurrent(snapshot: snapshot, context: context, snapshotID: snapshotID)",
                  "return termSnapshots[target.row.id]"]:
        if token not in access:
            raise AssertionError("Lost terms presentation fence: " + token)


class ClubInvitationTermsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = PATH.read_text()

    def test_terms_decode_only_the_finite_display_fields_with_the_existing_model(self):
        model = span(self.source, "struct ClubInvitationFeedbackTerms:", "static func project(")
        self.assertIn('["id", "shareMode", "shareRate", "fixedFee", "handleReason", "termsFrozen"]', model)
        self.assertIn("JSONDecoder().decode(CooperationInvite.self, from: safeValue.canonical())", model)
        for field in ["shareMode", "shareRate", "fixedFee", "handleReason", "termsFrozen"]:
            self.assertIn(f"{field} = decoded.{field}", model)
        for field in ["deposit", "phone", "leaderName", "contact", "transport"]:
            self.assertNotIn(field, model)

    def test_direction_id_and_current_snapshot_are_required(self):
        require_scoped_terms(self.source)

    def test_terms_publish_atomically_after_the_same_authorized_read_chain(self):
        load = span(self.source, "func load(_ permit:", "@MainActor struct ClubInvitationFeedbackEntry")
        ordered = ["freshClub = try await clubReader.clubDetail", "freshClub.isOwner",
                   "access.read(.topics", "permit.context.topicsContext.accepts(topics)",
                   "reader.read(.invitations", "ClubInvitationFeedbackSnapshot(context:",
                   "ClubInvitationFeedbackTerms.project(projected, invitations: invitations)",
                   "termSnapshots = projectedTerms", "loaded = permit.context; snapshot = projected; phase = .ready"]
        positions = [load.index(value) for value in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("guard current() else { return }\n            termSnapshots = projectedTerms", load)
        self.assertIn("guard current() else { return }; phase = .failed", load)
        self.assertEqual(load.count("reader.read(.invitations"), 1)

    def test_bind_activate_leave_and_reload_retire_old_terms(self):
        for first, last in [("func bind(", "func activate("), ("func activate(", "func permit("),
                            ("func leave(", "func load("), ("func load(", "let current =")]:
            self.assertIn("termSnapshots = [:]", span(self.source, first, last))
        self.assertIn("guard bound == context else { return }; visibility = nil", self.source)
        self.assertIn("generation == request && !Task.isCancelled", self.source)

    def test_the_existing_detail_is_the_only_new_display_host(self):
        owner = span(self.source, "private struct ClubInvitationFeedbackDetailOwner", "private struct ClubInvitationFeedbackRowLabel")
        self.assertIn(".sheet(isPresented: presentation.binding(for: item)", owner)
        self.assertIn("@StateObject private var model = ClubInvitationFeedbackReadModel()", owner)
        self.assertIn("snapshot.target(key: item.key, context: item.context, snapshotID: model.snapshotID)", owner)
        self.assertIn("model.terms(for: target, in: item.context,", owner)
        self.assertIn("ClubInvitationFeedbackTermsView(terms: terms)", owner)
        self.assertIn('Button("club.gov.close")', owner)
        self.assertIn("model.leave(item.context); presentation.close(item)", owner)
        self.assertIn(".onDisappear { model.leave(item.context) }", owner)
        self.assertIn("guard current(target) else { return }", self.source)
        self.assertIn("presentation.open(key: target.row.id, in: scope)", self.source)

    def test_display_keeps_unknowns_and_verbatim_reason_without_money_defaults(self):
        display = self.source.split("private struct ClubInvitationFeedbackTermsView:", 1)[1]
        for token in ['Section("cooperation.terms")', "switch terms.shareMode", "case 0:", "case 1:", "case 2:",
                      'default: Text("cooperation.termsUnknown")', 'Text("cooperation.amountUnknown")',
                      'Text("cooperation.currencyUnknown")', 'Label("cooperation.termsFrozen"',
                      "Text(verbatim: reason).textSelection(.enabled)", '.fractionLength(0...8)']:
            self.assertIn(token, display)
        for token in ["?? 0", "Button(", "NavigationLink", "deposit", "phone", "CNY", "USD", "yuan"]:
            self.assertNotIn(token, display)
        self.assertIn("if let rate = terms.shareRate", display)
        self.assertIn("if let fee = terms.fixedFee", display)

    def test_missing_ownership_or_snapshot_fences_fail_negative_controls(self):
        for token in ['raw["id"].integer == row.id.invitationID', 'raw["toId"].integer == snapshot.clubID',
                      'raw["toType"].text == "club"', "matches.count == 1", "row.topicID != nil",
                      "target.isCurrent(snapshot: snapshot, context: context, snapshotID: snapshotID)"]:
            with self.subTest(token=token), self.assertRaises(AssertionError):
                require_scoped_terms(self.source.replace(token, "true"))

    def test_fresh_detail_loading_cannot_render_the_parent_list_target(self):
        owner = span(self.source, "private struct ClubInvitationFeedbackDetailOwner", "private struct ClubInvitationFeedbackRowLabel")
        self.assertIn("guard current else { return nil }", owner)
        self.assertIn("return model.accepted(item.context,", owner)
        self.assertIn('Text("cooperation.unavailable")', owner)
        self.assertIn('ProgressView("club.loading")', owner)
        self.assertIn(".task(id: current)", owner)
        self.assertIn("await model.load(permit, clubReader: clubReader, reader: reader, access: access,", owner)
        self.assertEqual(owner.count("isCurrent: { current }"), 2)
        self.assertNotIn("item.row", owner)
        self.assertNotIn("target: ClubInvitationFeedbackTarget", owner)

    def test_concrete_sheet_uuid_rejects_old_callbacks(self):
        owner = span(self.source, "final class ClubInvitationFeedbackPresentation", "@MainActor struct ClubInvitationFeedbackView")
        self.assertIn("route?.id == item.id", owner)
        self.assertIn("item.context == context", owner)
        self.assertIn("Binding(get: { self.owns(item, in: item.context)", owner)
        self.assertIn("if !value { self.close(item) }", owner)
        self.assertIn("guard owns(item, in: item.context) else { return }", owner)
        self.assertIn("guard owns(item, in: context) else { return }", owner)
        self.assertIn("currentContext: { context }).id(item.id)", self.source)

    def test_hidden_parent_refresh_waits_for_current_visible_trigger(self):
        owner = span(self.source, "final class ClubInvitationFeedbackPresentation", "@MainActor struct ClubInvitationFeedbackView")
        self.assertIn("readRevision == trigger.revision", owner)
        self.assertIn("visible, active, route == nil, needsRead else { return false }", owner)
        self.assertIn("needsRead = false; return true", owner)
        self.assertIn("visible = false", owner)
        self.assertIn("if needsRead, route == nil { readRevision = UUID() }", owner)
        view = span(self.source, "@MainActor struct ClubInvitationFeedbackView", "private struct ClubInvitationFeedbackDetailOwner")
        self.assertIn(".task(id: trigger)", view)
        self.assertIn("presentation.consumeRead(trigger)", view)
        self.assertIn("if presentation.route == nil { model.leave(scope) }", view)
        self.assertNotIn("onDismiss:", view)
        self.assertNotIn("Task { await model.load", view)

    def test_detail_owner_predicate_is_checked_before_and_after_every_read(self):
        load = span(self.source, "func load(_ permit:", "@MainActor struct ClubInvitationFeedbackEntry")
        self.assertIn("isCurrent ownerIsCurrent: @escaping () -> Bool = { true }", load)
        self.assertIn("guard ownerIsCurrent(), accepts(permit)", load)
        self.assertIn("ownerIsCurrent() && accepts(permit) && generation == request", load)
        self.assertIn("clubReader.clubDetail(id: permit.context.clubID, isCurrent: current)", load)
        self.assertIn("guard current() else { throw CancellationError() }", load)
        self.assertIn("reader.read(.invitations, isCurrent: current)", load)
        self.assertEqual(load.count("guard current() else { return }"), 4)
        self.assertIn("guard current(), permit.context.topicsContext.accepts(topics)", load)

    def test_both_initial_detail_read_and_retry_pass_the_concrete_owner_gate(self):
        owner = span(self.source, "private struct ClubInvitationFeedbackDetailOwner", "private struct ClubInvitationFeedbackRowLabel")
        self.assertEqual(owner.count("isCurrent: { current }"), 2)
        current = span(owner, "private var current: Bool", "private var snapshot:")
        self.assertIn("presentation.isPresented", current)
        self.assertIn("presentation.owns(item, in: currentContext())", current)
        self.assertIn("scenePhase == .active", current)
        self.assertIn("item.context.matches(clubReader: clubReader, reader: reader, access: access)", current)

    def test_held_read_regressions_retire_owner_without_swiftui_cleanup(self):
        tests = (ROOT / "Tests/AppUnitTests/ClubInvitationFeedbackViewTests.swift").read_text()
        for name in ["testDetailCloseDuringFirstReadStopsLaterReadsWithoutLeaveOrTaskCancellation",
                     "testDetailBackgroundDuringFirstReadStopsLaterReadsWithoutLeaveOrTaskCancellation",
                     "testDetailCloseDuringTopicsReadStopsInvitationReadWithoutLeave",
                     "testDetailOldQueuedRetryCannotStartFirstReadAfterOwnerClose",
                     "testDetailCloseDuringInvitationReadCannotPublishReplyWithoutLeave"]:
            self.assertIn("func " + name + "(", tests)
        held = span(tests, "private func assertDetailFirstReadRetirement", "func testDetailCloseDuringTopicsRead")
        self.assertIn("owner.binding(for: item).wrappedValue = false", held)
        self.assertIn("owner.setActive(false, in: scope)", held)
        self.assertIn("XCTAssertTrue(f.access.resources.isEmpty); XCTAssertTrue(f.flow.resources.isEmpty)", held)
        self.assertNotIn("model.leave(scope)", held)
        self.assertNotIn("task.cancel()", held)

    def test_native_regressions_cover_direction_missing_values_stale_owners_and_late_reads(self):
        tests = (ROOT / "Tests/AppUnitTests/ClubInvitationFeedbackViewTests.swift").read_text()
        self.assertEqual(tests.count("func testInvitationTerms"), 9)
        for assertion in ['XCTAssertEqual(terms.count, 2)', 'XCTAssertEqual(zero.fixedFee, 0)',
                          'XCTAssertNil(terms.shareMode)', 'XCTAssertThrowsError(try ClubInvitationFeedbackTerms',
                          'XCTAssertNil(model.terms(for: old,', 'model.leave(scope); _ = model.activate(scope)',
                          '?.handleReason, "New")', 'XCTAssertEqual(f.access.sends, 0)']:
            self.assertIn(assertion, tests)


if __name__ == "__main__":
    unittest.main()
