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
        sheet = span(self.source, ".sheet(item: $selected,", "private func reload(")
        self.assertIn("if current(target)", sheet)
        self.assertIn("model.terms(for: target, in: context,", sheet)
        self.assertIn("clubReader: clubReader, reader: reader, access: access)", sheet)
        self.assertIn("ClubInvitationFeedbackTermsView(terms: terms)", sheet)
        self.assertIn('Button("club.gov.close") { selected = nil }', sheet)
        self.assertIn(".onChange(of: current(target), initial: true)", sheet)
        self.assertIn(".onDisappear { selected = nil; model.leave(scope) }", self.source)

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
