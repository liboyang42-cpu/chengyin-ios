"""Native-local structural checks only; these do not execute Swift or its UI."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubEnrollmentContractChecks(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_scope_and_nested_projection_are_required(self):
        code = self.text('Core/ClubEnrollmentContracts.swift')
        for fragment in ['clubID == scope.clubID, topicID == scope.topicID', 'value["canRefund"].bool', 'ClubEnrollmentDecode.rows(value["omsTicketList"])', 'ClubEnrollmentDecode.rows(value["cmsRegistrationList"])', 'unique(tickets.flatMap(\\.registrants).map(\\.id))']:
            self.assertIn(fragment, code)
        self.assertIn('ClubEnrollmentRoster(value: value, scope: scope)', self.text('Core/ClubGovernanceValidation.swift'))
    def test_unknown_status_counts_and_capacity_are_preserved(self):
        code = self.text('Core/ClubEnrollmentContracts.swift')
        self.assertIn('case 0: return .pending; case 1: return .done; default: return .unknown', code)
        self.assertIn('public let signupCount: Int?', code)
        self.assertIn('public var refundableCount: Int?', code)
        self.assertIn('public let mode: Int?', code)
        self.assertIn('public let capacity: Int?', code)
    def test_roster_has_no_financial_dispatch(self):
        code = self.text('Core/ClubEnrollmentReader.swift') + self.text('App/ClubEnrollmentView.swift')
        for fragment in ['access.send(', 'cancel-by-owner', 'coordinator.confirm(', 'refund()']:
            self.assertNotIn(fragment, code)
        self.assertIn('club.enroll.refundUnavailable', code)
    def test_identity_and_generations_gate_all_receipts(self):
        code = self.text('Core/ClubEnrollmentReader.swift')
        for fragment in ['access.identity == expected', 'generation == revision', '!Task.isCancelled', 'detailGenerations[topicID] == detailRevision', 'if clearsSnapshot(issue) { clear()', '"club:member:list:read"']:
            self.assertIn(fragment, code)
    def test_refresh_does_not_leave_collapsed_detail_cache(self):
        code = self.text('Core/ClubEnrollmentReader.swift')
        self.assertIn('rosters = rosters.filter { expanded.contains($0.key) }', code)
        self.assertIn('await loadDetail(topicID: id)', code)
        self.assertIn('expanded.insert(focusTopicID)', code)
    def test_real_destinations_and_topic_focus_are_wired(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        for fragment in ['SocialPublicProfileView(memberID: memberID', 'operation: .checkin', 'registrationID: registrant.id', 'returningFromCheckin = true', 'await reader.refresh()', '.onDisappear { reader.suspend() }']:
            self.assertIn(fragment, ui)
        routes = self.text('App/ClubGovernanceViews.swift')
        self.assertIn('enrollmentLink(focusTopicID: scope.topicID)', routes)
        self.assertIn('enrollmentLink()', routes)
        self.assertNotIn('link(.registrations)', routes)
        self.assertIn('enrollmentProfile: .init(reader: socialAccountReader, squareReader: squareReader', self.text('App/AppSession.swift'))
    def test_additive_fragment_is_bilingual_and_covers_ui(self):
        fragment = json.loads(self.text('Resources/ClubEnrollmentLocalizations.fragment.json'))['strings']
        for key, entry in fragment.items():
            self.assertTrue(key.startswith('club.enroll.'))
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
        ui = self.text('App/ClubEnrollmentView.swift')
        ui = re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', '', ui)
        keys = set(re.findall(r'"(club\.enroll\.[A-Za-z.]+)"', ui))
        for key in keys:
            if not key.endswith('.'): self.assertIn(key, fragment)
        for status in ['unknown', 'pending', 'done']: self.assertIn('club.enroll.checkin.' + status, fragment)
        for status in ['0', '1', '2']: self.assertIn('club.enroll.teamStatus.' + status, fragment)
    def test_existing_fixture_satisfies_new_root_identity_contract(self):
        code = self.text('Core/ClubGovernanceSyntheticFixtures.swift')
        line = next(line for line in code.splitlines() if 'case .registrations:' in line)
        fixture = json.loads(line.split('json(#"', 1)[1].split('"#)', 1)[0])
        self.assertEqual((fixture['clubId'], fixture['topicId']), (81, 91))
        self.assertIsInstance(fixture['canRefund'], bool)
        self.assertGreater(fixture['omsTicketList'][0]['id'], 0)

if __name__ == '__main__': unittest.main()
