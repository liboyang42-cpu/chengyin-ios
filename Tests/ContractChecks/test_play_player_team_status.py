"""Source contracts only: no Swift compilation, runtime or live acceptance."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PlayPlayerTeamStatusContract(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / 'Core/PlayPlayerTeamReadback.swift').read_text()
        self.view = (ROOT / 'App/PlayPlayerTeamStatusView.swift').read_text()
        self.host = (ROOT / 'App/PlayPlayerAndCircleViews.swift').read_text().split('@MainActor struct PlayCircleView')[0]
        self.runtime = (ROOT / 'Core/PlayGameSessionRuntime.swift').read_text()

    def test_source_field_is_preserved_without_reinterpreting_submission_or_write_logic(self):
        self.assertIn('public let teamActions: PlayWireValue', self.runtime)
        self.assertIn('teamActions = raw["player"]["teamActions"]', self.runtime)
        self.assertIn('submissions = raw["player"]["mySubmissions"].array ?? []', self.runtime)
        self.assertIn('PlayPlayerTeamState.read(projection.teamActions)', self.core)

    def test_all_seven_source_statuses_have_distinct_bilingual_labels(self):
        expected = {'joined': '待分配', 'assigned': '待确认身份', 'confirmed': '身份已确认',
                    'in_progress': '行动中', 'submitted': '等待核验', 'completed': '已完成',
                    'fallback_completed': '已通过兜底完成'}
        data = json.loads((ROOT / 'Resources/PlayPlayerTeamStatusLocalizations.fragment.json').read_text())
        for status, label in expected.items():
            self.assertIn('"' + status.upper() + '"', self.core)
            entry = data['strings']['playerTeam.status.' + status]['localizations']
            self.assertEqual(entry['zh-Hans']['stringUnit']['value'], label)
            self.assertTrue(entry['en']['stringUnit']['value'])
        self.assertEqual(len(data['strings']), 12)

    def test_missing_malformed_unknown_and_duplicate_rows_are_unconfirmed(self):
        for expression in ['guard let rows = value.array else { return .unconfirmed }',
                           'seen.insert(id).inserted', 'let id = row["memberId"].integer, id > 0',
                           'PlayPlayerTeamMember.Status(rawValue: rawStatus)',
                           'return members.isEmpty ? .empty : .members(members)']:
            self.assertIn(expression, self.core)
        self.assertNotIn('?? .completed', self.core)
        self.assertNotIn('?? .assigned', self.core)
        self.assertNotIn('.sorted', self.core)

    def test_rows_retain_exactly_four_public_fields(self):
        member = self.core.split('public enum PlayPlayerTeamState')[0]
        self.assertEqual(re.findall(r'public let (\w+):', member), ['id', 'displayName', 'roleCode', 'status'])
        for forbidden in ['["phone"]', '["latitude"]', '["longitude"]', '["realName"]', '["evidenceUrls"]']:
            self.assertNotIn(forbidden, self.core + self.view)
        self.assertIn('Text(verbatim: name)', self.view)
        self.assertIn('Text(verbatim: role)', self.view)

    def test_owner_session_team_revision_and_revocation_precede_readback(self):
        for expression in ['owner = model.currentSession()', 'owner == model.currentSession()',
                           'model.service.enabled.contains(.reads)', 'model.service.hasCurrentReadLifetime',
                           'model.hasCurrentProjection', 'model.phase == "ready"', 'model.pending == nil',
                           'sessionID == projection.sessionID', 'teamID == projection.teamID',
                           'projection.activityID == model.activityID', 'projection.revision >= minimumRevision',
                           'minimumRevision = max(minimumRevision ?? 0, projection.revision)']:
            self.assertIn(expression, self.core)
        self.assertIn('guard currentAuthority, let projection = model.projection', self.core)

    def test_no_new_network_read_commands_member_navigation_or_matching(self):
        for forbidden in ['URLSession', 'transport.send', 'api/', 'await model.load()', 'submit(', 'playerCommand(',
                          'Button(', 'NavigationLink', 'interest', 'matching', 'award(', 'redeem(']:
            self.assertNotIn(forbidden, self.core + self.view)
        self.assertIn('if let readback = submissionReadback { Task { await readback.refresh() } }', self.host)
        self.assertEqual(self.host.count('await readback.open()'), 1)

    def test_lifecycle_uses_fresh_read_and_never_reactivates_dismissed_lease(self):
        self.assertIn('let team = PlayPlayerTeamReadback(model: model)', self.host)
        self.assertIn('await readback.open()\n                team.acceptFreshRead()', self.host)
        self.assertIn('.onChange(of: model.phase)', self.host)
        self.assertIn('if phase == "ready" { teamReadback?.acceptFreshRead() }', self.host)
        self.assertIn('.onDisappear { teamReadback?.dismiss() }', self.host)
        self.assertIn('public func dismiss() { retired = true }', self.core)
        self.assertIn('guard currentAuthority, !Task.isCancelled', self.core)
        self.assertNotIn('retired = false', self.core.split('public init(model:')[1])

    def test_mounts_public_progress_in_existing_player_screen(self):
        self.assertIn('PlayPlayerTeamStatusView(state: teamReadback?.state ?? .unconfirmed)', self.host)
        self.assertIn('if model.hasCurrentProjection, let projection = model.projection', self.host)
        self.assertIn('.privacySensitive()', self.view)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', self.view)
        self.assertIn('.accessibilityElement(children: .combine)', self.view)

    def test_authored_apple_tests_cover_failure_interruptions_and_reopen(self):
        tests = (ROOT / 'Tests/CoreTests/PlayPlayerTeamReadbackTests.swift').read_text()
        for name in ['testReadLifetimeRevocation', 'testUnknownWrite', 'testInitialFailure', 'testRefreshFailure',
                     'testLateReadAfterDismissal', 'testReopenRequiresFreshRead', 'testDifferentGameOrTeam',
                     'testRevisionRollback', 'testAccountEpochNamespaceRoleToken']:
            self.assertIn(name, tests)
        app = (ROOT / 'Tests/AppUnitTests/PlayPlayerTeamStatusTests.swift').read_text()
        self.assertIn('accessibility5', app)
        self.assertIn('["en", "zh-Hans"]', app)


if __name__ == '__main__':
    unittest.main()
