"""w2-04 member tools (complaint progress, invite copy, template shelf). Source checks only:
not compiled Swift, real permission, backend reads or UI execution."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class ComplaintProgressChecks(unittest.TestCase):
    def setUp(self):
        self.core = read('Core/ProfileComplaintProgress.swift')
        self.section = read('App/ProfileComplaintProgressSection.swift')
        self.screen = read('App/ProfileComplaintPreparationView.swift')
    def test_source_endpoint_is_a_no_body_array_read(self):
        s = read('Core/CooperationFlowService.swift')
        self.assertIn('case .complaintProgress: return "api/coop/complaint/mine"', s)
        self.assertIn('.complaintTopics, .complaintProgress, .clubs', s)
    def test_progress_reads_only_its_endpoint_and_never_writes(self):
        self.assertEqual(self.core.count('reader.read('), 1)
        self.assertIn('reader.read(.complaintProgress, isCurrent: { current() })', self.core)
        for t in ['CoopFlowMutation', 'perform(', 'submit(', 'URLSession', 'HTTPTransport', 'UserDefaults', 'CoopFlowService(']:
            self.assertNotIn(t, self.core + self.section)
    def test_missing_id_rejects_whole_array(self):
        self.assertIn('guard case .object = row, let id = row["id"].integer, id > 0 else { throw APIError.malformedResponse }', self.core)
    def test_access_codes_follow_source(self):
        self.assertIn('[400, 403, 422].contains(code)', self.core)
        self.assertIn('if code == 401 { self = .signIn; return }', self.core)
    def test_personal_reader_allows_only_selector_and_progress(self):
        s = read('App/SessionWalletCommerceView.swift')
        self.assertIn('guard resource == .complaintTopics || resource == .complaintProgress else { throw APIError.notConfigured }', s)
    def test_screen_owns_progress_lifetime(self):
        for t in ['_progress = State(initialValue: .init(reader: reader, isCurrent: isCurrent))', '.task { await progress.load() }',
                  '.onDisappear { progress.retire() }', 'if phase == .background { progress.retire() }',
                  '.onChange(of: reader.session) { _, _ in progress.retire() }', 'ProfileComplaintProgressSection(model: progress)']:
            self.assertIn(t, self.screen)
        self.assertNotIn('.onDisappear', self.section)
    def test_source_copy_and_handle_note_line(self):
        self.assertIn('Text("profile.complaintProgress.handleNote \\(note)")', self.section)
        self.assertIn('Text("profile.complaint.sourceEmpty").accessibilityIdentifier("profile.complaint.empty")', self.screen)
        self.assertIn('.navigationTitle("profile.complaint.pageTitle")', self.screen)
    def test_fixture_progress_uses_its_own_counter(self):
        s = read('App/ProfileComplaintPreparationFixture.swift')
        self.assertIn('if resource == .complaintProgress { return try progress() }', s)
        self.assertIn('progressCalls += 1', s)


class InviteHistoryCopyChecks(unittest.TestCase):
    def setUp(self):
        self.view = read('App/SocialInviteHistoryView.swift')
        self.core = read('Core/ProfileInviteHistoryIssue.swift')
    def test_page_specific_failure_and_empty_states(self):
        self.assertIn('ProfileInviteHistoryIssueView(error: APIError.unauthorized)', self.view)
        self.assertIn('ProfileInviteHistoryIssueView(error: error) { model.start(reader, permit: permit, reset: model.pagination.members.isEmpty) }', self.view)
        self.assertIn('model.error == nil { ProfileInviteHistoryEmptyView() }', self.view)
        self.assertIn('Text("profile.inviteHistory.nicknameUnknown")', self.view)
    def test_403_is_its_own_state_and_only_failures_retry(self):
        self.assertIn('case SocialAccountFailure.rejected(code: 403, message: _): self = .denied', self.core)
        self.assertIn('public var canRetry: Bool { self == .failed }', self.core)
    def test_new_keys_do_not_change_social_catalog_count(self):
        fragment = json.loads(read('Resources/W204MemberToolsLocalizations.fragment.json'))['strings']
        self.assertFalse([k for k in fragment if k.startswith('social.')])


class LocalizationChecks(unittest.TestCase):
    def test_fragment_is_bilingual_and_merged(self):
        fragment = json.loads(read('Resources/W204MemberToolsLocalizations.fragment.json'))['strings']
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        for key, row in fragment.items():
            self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'})
            self.assertEqual(catalog.get(key), row, key)
    def test_source_chinese_copy(self):
        fragment = json.loads(read('Resources/W204MemberToolsLocalizations.fragment.json'))['strings']
        zh = {k: v['localizations']['zh-Hans']['stringUnit']['value'] for k, v in fragment.items()}
        self.assertEqual(zh['profile.complaint.pageTitle'], '投诉与建议')
        self.assertEqual(zh['profile.complaintProgress.unavailable'], '处理进展不可查看')
        self.assertEqual(zh['profile.complaint.sourceEmpty'], '暂无可投诉的活动')


if __name__ == '__main__':
    unittest.main()
