"""Source-wiring checks only. They do not execute Swift, UIKit, or production reads."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()

class ProfileComplaintPreparationChecks(unittest.TestCase):
    def setUp(self):
        self.core = read('Core/ProfileComplaintPreparation.swift')
        self.app = read('App/ProfileComplaintPreparationView.swift')
    def test_only_authoritative_selector_is_read(self):
        self.assertIn('reader.read(.complaintTopics, isCurrent:', self.core)
        self.assertEqual(self.core.count('reader.read('), 1)
        for t in ['.profileOrders(', '.participations(', '.settlement(', 'APIConfiguration(', 'HTTPTransport', 'URLSession']:
            self.assertNotIn(t, self.core + self.app)
    def test_unique_positive_topic_ids_without_fallback(self):
        self.assertIn('let id = row["topicId"].integer', self.core)
        self.assertIn('id > 0, seen.insert(id).inserted', self.core)
        self.assertNotIn('row["registrationId"]', self.core)
        self.assertNotIn('row["id"]', self.core)
    def test_array_and_name_are_strict(self):
        self.assertIn('guard let rows = value.rows else', self.core)
        self.assertIn('guard case .object = row', self.core)
        self.assertIn('case .string(let raw):', self.core)
        self.assertIn('default: throw APIError.malformedResponse', self.core)
    def test_no_fake_defaults_or_eligibility(self):
        self.assertIn('var topics: [ProfileComplaintTopic]?', self.core)
        for t in ['filterEndedOverWeek', 'paymentStatus', 'owner_type', 'Date()', 'UserDefaults']:
            self.assertNotIn(t, self.core)
    def test_topic_selected_from_current_list(self):
        self.assertIn('topics.contains(where: { $0.id == topicID })', self.core)
        self.assertIn('topics.first(where: { $0.id == topicID })', self.core)
    def test_utf16_minimum_and_limits(self):
        for t in ['Self.trimmed(reason).utf16.count >= 5', 'reason.utf16.count <= 500', 'contact.utf16.count <= 50']:
            self.assertIn(t, self.core)
        self.assertNotIn('.prefix(500)', self.core + self.app)
    def test_ecmascript_trim_bom_not_nel(self):
        self.assertIn('\\u{FEFF}', self.core); self.assertNotIn('\\u{0085}', self.core)
        self.assertIn('value.trimmingCharacters(in: trimSet)', self.core)
    def test_exact_five_type_labels(self):
        for text in ['服务与履约', '费用与退款', '安全与纠纷', '虚假宣传', '其他']:
            self.assertIn('return "' + text + '"', self.core)
    def test_type_reason_contact_order(self):
        self.assertIn('text = "【" + kind.sourceLabel + "】" + text', self.core)
        self.assertIn('text += "\\n联系方式：" + contact', self.core)
        self.assertLess(self.core.index('kind.sourceLabel + "】"'), self.core.index('联系方式：'))
    def test_captured_session_and_parent_lifetime(self):
        self.assertIn('owner = reader.session', self.core)
        self.assertIn('active && owner != nil && reader.session == owner && isCurrent()', self.core)
    def test_singleflight_and_generation(self):
        self.assertIn('guard !isLoading, review == nil else', self.core)
        self.assertIn('contextMatches && generation == stamp && !Task.isCancelled', self.core)
    def test_predispatch_success_error_fences(self):
        self.assertIn('try Task.checkCancellation()', self.core)
        self.assertGreaterEqual(self.core.count('guard current() else'), 3)
        self.assertIn('reader.read(.complaintTopics, isCurrent: { current() })', self.core)
    def test_cancelled_refresh_does_not_unlock_stale_review(self):
        self.assertIn('else if generation == stamp { issue = .failed }', self.core)
        self.assertEqual(self.core.count('guard current() else { abandon(); return }'), 3)
    def test_retire_clears_ephemeral_data(self):
        self.assertIn('active = false; generation &+= 1; isLoading = false', self.core)
        self.assertIn('topics = nil; issue = nil; draft = .init(); review = nil; validation = nil', self.core)
    def test_refresh_failure_blocks_review(self):
        self.assertIn('!isLoading && issue == nil && review == nil', self.core)
        self.assertIn('guard canEdit, let topics else', self.core)
    def test_auth_and_config_clear_draft(self):
        self.assertIn('if failure == .signIn || failure == .unavailable', self.core)
        self.assertIn('topics = nil; draft = .init(); review = nil', self.core)
    def test_missing_fresh_selection_dropped(self):
        self.assertIn('topics = fresh', self.core)
        self.assertIn('!fresh.contains(where: { $0.id == selected }) { draft.topicID = nil }', self.core)
    def test_review_is_immutable_local_value(self):
        self.assertIn('public let reason: String', self.core)
        self.assertIn('public let topic: ProfileComplaintTopic', self.core)
        self.assertIn('review = draft.review(topics: topics)', self.core)
        self.assertIn('model.continueEditing()', self.app)
    def test_production_link_uses_existing_reader_and_revision(self):
        self.assertIn('reader: session.cooperationFlowReader', self.app)
        self.assertIn('session.sessionRevision == revision && session.cooperationFlowReader.session == owner', self.app)
        self.assertIn('.id(revision)', self.app)
    def test_reader_and_epoch_presentation_key(self):
        for t in ['ObjectIdentifier(reader)', 'reader.session?.accountID', 'reader.session?.epoch', '.id(ProfileComplaintPresentationKey(reader))']:
            self.assertIn(t, self.app)
    def test_background_close_and_disappear_clear(self):
        self.assertIn('Button("action.close") { model.retire(); dismiss() }', self.app)
        self.assertIn('if phase == .background { focused = nil; model.retire() }', self.app)
        self.assertIn('.onDisappear { model.retire() }', self.app)
        self.assertIn('.privacySensitive()', self.app)
    def test_local_only_and_not_submitted_are_visible(self):
        self.assertIn('Text("profile.complaint.localOnly")', self.app)
        self.assertIn('Text("profile.complaint.notSubmitted")', self.app)
    def test_no_write_share_copy_or_store_dependency(self):
        for t in ['CoopFlowMutation', 'CoopFlowRequestPreview', 'perform(', 'submit(', 'UIPasteboard', 'ShareLink', 'UserDefaults', 'FileManager', 'JSONEncoder', 'print(', 'CoopFlowService(']:
            self.assertNotIn(t, self.core + self.app)
    def test_five_kind_picker_and_optional_none(self):
        self.assertIn('ForEach(ProfileComplaintKind.allCases)', self.app)
        self.assertIn('Optional<ProfileComplaintKind>.none', self.app)
    def test_validation_first_error_can_be_reviewed(self):
        self.assertIn('if !model.beginReview()', self.app)
        self.assertIn('case .reasonShort, .reasonLong: focused = .reason', self.app)
        self.assertIn('case .contactLong: focused = .contact', self.app)
    def test_retry_and_empty_are_distinct(self):
        self.assertIn('topics.isEmpty && model.issue == nil && !model.isLoading', self.app)
        self.assertIn('if issue == .failed', self.app)
        self.assertIn('.disabled(!model.canEdit)', self.app)
    def test_fixture_is_synthetic_and_separate(self):
        s = read('App/ProfileComplaintPreparationFixture.swift'); self.assertTrue(s.startswith('#if DEBUG'))
        for t in ['URLSession', 'HTTPTransport', 'AppSession(', 'CoopFlowService(', 'UserDefaults', 'CoopFlowProtectedDispatch']:
            self.assertNotIn(t, s)
    def test_fragment_has_no_central_edits_or_grants(self):
        f = json.loads(read('docs/profile-complaint-preparation-registration.fragment.json'))
        self.assertEqual(f['central_files_modified'], [])
        self.assertEqual(f['personal_mount']['status'], 'NOT_APPLIED')
        self.assertIn('ProfileComplaintPreparationLink(session: session)', f['personal_mount']['unified_diff'])
    def test_29_bilingual_keys(self):
        s = json.loads(read('Resources/ProfileComplaintPreparationLocalizations.fragment.json'))['strings']
        self.assertEqual(len(s), 29)
        for row in s.values(): self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'})
    def test_native_tests_cover_races_limits_and_local_roundtrip(self):
        s = read('Tests/CoreTests/ProfileComplaintPreparationTests.swift')
        for t in ['testLateSuccessCannotRestoreClosedDraft', 'testLateErrorAfterSwitchDoesNotOverwriteNewContext', 'testInputLimitsRejectInsteadOfTruncate', 'testLocalReviewReturnAndCloseClear', 'testRefreshFailureKeepsDraftButBlocksReviewUntilRecovery']:
            self.assertIn(t, s)
    def test_ui_tests_cover_review_retry_and_account_change(self):
        s = read('Tests/AppUITests/ProfileComplaintPreparationFlowTests.swift')
        for t in ['testPrepareReviewReturnAndNoSubmitControl', 'testInitialFailureRetry', 'testAccountChangeClearsPreparedReview']:
            self.assertIn(t, s)

if __name__ == '__main__': unittest.main()
