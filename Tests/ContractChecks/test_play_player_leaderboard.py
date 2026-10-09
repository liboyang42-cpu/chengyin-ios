"""Static native/source contracts only; not Swift compilation or live acceptance."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PlayPlayerLeaderboardContract(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / 'Core/PlayPlayerLeaderboardReadback.swift').read_text()
        self.view = (ROOT / 'App/PlayPlayerLeaderboardView.swift').read_text()
        self.host = (ROOT / 'App/PlayPlayerAndCircleViews.swift').read_text().split('@MainActor struct PlayCircleView')[0]
        self.runtime = (ROOT / 'Core/PlayGameSessionRuntime.swift').read_text()

    def test_consumes_only_existing_player_leaderboard_field(self):
        self.assertIn('public let playerLeaderboard: PlayWireValue', self.runtime)
        self.assertIn('playerLeaderboard = raw["player"]["leaderboard"]', self.runtime)
        self.assertIn('PlayPlayerLeaderboardState.read(projection.playerLeaderboard)', self.core)
        self.assertIn('"api/game/session/view"', self.runtime)
        for forbidden in ['api/play/leaderboard', 'api/play/advanced/leaderboard', 'leaderboardVisible']:
            self.assertNotIn(forbidden, self.core + self.view)

    def test_visibility_is_explicit_and_checked_before_entries(self):
        gate = 'guard value.object != nil, value["visible"].bool == true else { return .hidden }'
        rows = 'guard let rows = value["entries"].array else { return .unconfirmed }'
        self.assertIn(gate, self.core); self.assertLess(self.core.index(gate), self.core.index(rows))
        self.assertIn('case .hidden: EmptyView()', self.view)
        self.assertIn('return entries.isEmpty ? .empty : .entries(entries)', self.core)

    def test_preserves_rank_score_and_server_order_without_sorting_or_fabrication(self):
        for token in ['let rank = safeInteger(row["rank"]), rank > previousRank',
                      'seenTeams.insert(id).inserted', 'let score = safeInteger(row["score"]), score >= 0',
                      'number <= 9_007_199_254_740_991', 'rank: rank', 'score: score']:
            self.assertIn(token, self.core)
        for forbidden in ['.sorted', '.sort(', '.enumerated()', 'rank +', 'score +', '?? 0', 'completedNodes']:
            self.assertNotIn(forbidden, self.core.split('/// A read-only screen lease.')[0])

    def test_keeps_only_four_public_fields_and_renders_name_verbatim(self):
        entry = self.core.split('public enum PlayPlayerLeaderboardState')[0]
        self.assertEqual(re.findall(r'public let (\w+):', entry), ['id', 'rank', 'displayName', 'score'])
        self.assertIn('Text(verbatim: name)', self.view)
        self.assertIn('name.count <= 80', self.core)
        self.assertIn('CharacterSet.controlCharacters', self.core)
        for private in ['["phone"]', '["latitude"]', '["longitude"]', '["realName"]', '["evidenceUrls"]']:
            self.assertNotIn(private, self.core + self.view)

    def test_original_owner_scope_revision_and_revocation_fence_readback(self):
        for token in ['owner = model.currentSession()', 'owner == model.currentSession()',
                      'model.service.enabled.contains(.reads)', 'model.service.hasCurrentReadLifetime',
                      'model.hasCurrentProjection', 'model.phase == "ready"', 'model.pending == nil',
                      'sessionID == projection.sessionID', 'teamID == projection.teamID',
                      'projection.activityID == model.activityID', 'projection.revision >= minimumRevision',
                      'minimumRevision = max(minimumRevision ?? 0, projection.revision)',
                      'public func dismiss() { retired = true }', 'guard currentAuthority, !Task.isCancelled']:
            self.assertIn(token, self.core)
        self.assertNotIn('retired = false', self.core.split('public init(model:')[1])

    def test_no_additional_network_write_cache_or_reward_action(self):
        for forbidden in ['URLSession', 'transport.send', 'api/', 'await model.load()', 'submit(',
                          'playerCommand(', 'Button(', 'NavigationLink', 'UserDefaults', 'Codable',
                          'award(', 'redeem(', 'wallet', 'points']:
            self.assertNotIn(forbidden, self.core + self.view)
        self.assertEqual(self.host.count('await readback.open()'), 1)
        self.assertIn('if let readback = submissionReadback { Task { await readback.refresh() } }', self.host)

    def test_legacy_command_and_coordinator_implementation_is_unchanged(self):
        legacy = self.runtime.split('public struct PlayPlayerCommand:', 1)[1]
        self.assertEqual(hashlib.sha256(('public struct PlayPlayerCommand:' + legacy).encode()).hexdigest(),
                         '06a747a7551f336e4e6f200e631132d627de9666888199e79886f83a2dedaab1')
        self.assertIn('submissions = raw["player"]["mySubmissions"].array ?? []', self.runtime)
        self.assertIn('let prior = submissions.first', self.runtime)

    def test_existing_host_mounts_fresh_lease_and_retires_on_exit(self):
        for token in ['PlayPlayerLeaderboardView(state: leaderboardReadback?.state ?? .hidden)',
                      'let leaderboard = PlayPlayerLeaderboardReadback(model: model)',
                      'team.acceptFreshRead()\n                leaderboard.acceptFreshRead()',
                      '.onDisappear { leaderboardReadback?.dismiss() }',
                      'if phase == "ready" { leaderboardReadback?.acceptFreshRead() }',
                      '.onChange(of: model.projection)', 'leaderboardReadback?.acceptFreshRead()']:
            self.assertIn(token, self.host)
        self.assertIn('if model.hasCurrentProjection, let projection = model.projection', self.host)

    def test_all_labels_have_exact_bilingual_resource_entries(self):
        data = json.loads((ROOT / 'Resources/PlayPlayerLeaderboardLocalizations.fragment.json').read_text())
        keys = set(re.findall(r'"(playerLeaderboard\.(?:title|rank|team|score|metric|empty|unconfirmed))"', self.view))
        self.assertEqual(set(data['strings']), keys)
        for key, entry in data['strings'].items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for language, value in entry['localizations'].items():
                self.assertTrue(value['stringUnit']['value'].strip(), (key, language))
        self.assertIn('正常完成', data['strings']['playerLeaderboard.metric']['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('Fallback completions are excluded', data['strings']['playerLeaderboard.metric']['localizations']['en']['stringUnit']['value'])
        for token in ['.privacySensitive()', '.fixedSize(horizontal: false, vertical: true)', '.accessibilityElement(children: .combine)']:
            self.assertIn(token, self.view)

    def test_authored_apple_checks_cover_real_read_interruption_and_visibility(self):
        tests = (ROOT / 'Tests/CoreTests/PlayPlayerLeaderboardReadbackTests.swift').read_text()
        for name in ['testOnlyExplicitServerVisibility', 'testVisibleEmpty', 'testRefreshRemovesBoard',
                     'testMalformedBoardDoesNotChangeLegacySubmissionEligibility', 'testReadLifetimeRevocation',
                     'testUnknownWrite', 'testLoadingHidesOldRanks', 'testInitialFailure', 'testRefreshFailure',
                     'testReopenRequiresFreshRead', 'testDifferentGameOrTeam', 'testRevisionRollback',
                     'testAccountEpochNamespaceRoleToken']:
            self.assertIn(name, tests)
        app = (ROOT / 'Tests/AppUnitTests/PlayPlayerLeaderboardViewTests.swift').read_text()
        self.assertIn('accessibility5', app); self.assertIn('["en", "zh-Hans"]', app)
        self.assertIn('testHiddenRankingDoesNotLeaveLeaderboardCard', app)


if __name__ == '__main__':
    unittest.main()
