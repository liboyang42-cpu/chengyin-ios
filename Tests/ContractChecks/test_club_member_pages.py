"""w2-15 static parity checks for club enroll, topic-story answer, check-in and group-code. Not Swift runtime evidence."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path): return (ROOT / path).read_text()


def zh(catalog, key): return catalog[key]['localizations']['zh-Hans']['stringUnit']['value']


class ClubMemberPageContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']

    def test_enroll_copy_matches_mini_program(self):
        view = read('App/ClubEnrollmentView.swift')
        for key in ['club.enroll.escrow', 'club.enroll.emptyTeamsHint']:
            self.assertIn(f'"{key}"', view)
        self.assertEqual(zh(self.catalog, 'club.enroll.escrow'), '报名费由平台担保托管')
        self.assertEqual(zh(self.catalog, 'club.enroll.emptyTeams'), '还没有城市定向团')
        self.assertEqual(zh(self.catalog, 'club.enroll.checkin.done'), '已核销')

    def test_node_answer_has_labelled_sections_and_notice(self):
        content = read('App/ClubNodeAnswerContent.swift')
        for key in ['club.gov.field.question', 'club.gov.field.answerReveal', 'club.story.answer.hints', 'club.gov.field.feedbackText',
                    'club.story.answer.none', 'club.story.answer.notice']:
            self.assertIn(f'"{key}"', content)
        self.assertNotIn('send(', content)
        self.assertIn('} else if operation == .nodeAnswer {\n            ClubNodeAnswerContent(value: value)', read('App/ClubGovernanceViews.swift'))
        self.assertEqual(zh(self.catalog, 'club.gov.field.question'), '题面')
        self.assertEqual(zh(self.catalog, 'club.gov.nodeAnswer'), '查看答案')

    def test_governance_copy_is_generator_owned(self):
        generator = read('tools/build_club_governance_catalog.py')
        fragment = json.loads(read('Resources/ClubGovernanceLocalizations.fragment.json'))['strings']
        for row, key in [('topicCustomers|Participants|报名参与者', 'club.gov.topicCustomers'), ('checkin|Check-in detail|核销详情', 'club.gov.checkin')]:
            self.assertIn(row, generator)
            self.assertEqual(self.catalog[key]['localizations'], fragment[key]['localizations'])

    def test_group_code_absent_ttl_defaults_to_five_minutes(self):
        core = read('Core/ClubGovernanceGroupCode.swift')
        self.assertIn('public static let defaultTTLMilliseconds = 300_000', core)
        self.assertIn('if receipt["ttlMs"] == .null { ttl = Self.defaultTTLMilliseconds }', core)
        self.assertIn('testAbsentGroupCodeTTLUsesMiniProgramFiveMinuteDefault', read('Tests/CoreTests/ClubGovernanceContractTests.swift'))


if __name__ == '__main__':
    unittest.main()
