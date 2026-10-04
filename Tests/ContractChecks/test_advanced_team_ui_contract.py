"""Source-only regressions; no Swift runtime claim."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class AdvancedTeamContract(unittest.TestCase):
    def read(self, p): return (ROOT/p).read_text()
    def test_current_backend_roles_and_no_guessed_turn_order(self):
        source = self.read('Core/PlayAdvancedTeamProjection.swift')
        for term in ['roleAssignments','myRole','leaderMemberId','state.ownerType == 2','assignment == "LEADER"']:
            self.assertIn(term, source)
        self.assertNotIn('turnOrder', source)
    def test_normal_advanced_view_has_team_and_distinct_board(self):
        source = self.read('App/PlayAdvancedView.swift')
        for term in ['PlayAdvancedTeamControls(model: model, surfaceID: teamSurfaceID)', 'PlayAdvancedLeaderboardView(model: model, surfaceID: teamSurfaceID)', 'model.endTeamSurface(id: teamSurfaceID)']:
            self.assertIn(term, source)
    def test_inline_story_has_shared_mechanics_outside_kit_selection(self):
        source = self.read('App/ChapterStoryView.swift')
        self.assertIn('PlayAdvancedInlineTeamHost(model: advanced)', source)
        self.assertIn('state.inline && (state.isMultiplayer || state.config["leaderboard"]["enabled"].bool == true)', source)
        runtime = self.read('Core/PlayAdvancedRuntime.swift')
        self.assertIn('guard teamSurfaceOwner == (id ?? defaultTeamSurfaceID) else { return }', runtime)
    def test_disappeared_hosts_cannot_reclaim_surface_on_foreground(self):
        normal = self.read('App/PlayAdvancedView.swift')
        inline = self.read('App/PlayAdvancedTeamViews.swift')
        self.assertIn('phase == .active && teamSurfaceVisible', normal)
        self.assertIn('teamSurfaceVisible = false; model.endTeamSurface', normal)
        self.assertIn('phase == .active && surfaceVisible', inline)
        self.assertIn('surfaceVisible = false; model.endTeamSurface', inline)
    def test_frozen_review_and_late_board_guards(self):
        source = self.read('Core/PlayAdvancedRuntime.swift')
        for term in ['review.surfaceRevision == teamSurfaceRevision', 'state?.version == review.version', 'request == leaderboardGeneration','currentSession() == session', 'rows.count <= 100']:
            self.assertIn(term, source)
    def test_ui_never_displays_owner_id_or_fabricated_role(self):
        source = self.read('App/PlayAdvancedTeamViews.swift')
        self.assertIn('if team.isLeader', source)
        self.assertNotIn('row["ownerId"]', source)
        self.assertNotIn('turnOrder', source)
