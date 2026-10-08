"""Focused source checks, not Swift execution, UI screenshots or live acceptance."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PlayerSubmissionStatusContract(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def setUp(self):
        self.core = self.read('Core/PlayPlayerSubmissionReadback.swift')
        self.view = self.read('App/PlayPlayerSubmissionStatusView.swift')
        self.host = self.read('App/PlayPlayerAndCircleViews.swift').split('@MainActor struct PlayCircleView')[0]

    def test_normal_player_screen_mounts_readback_at_task(self):
        self.assertIn('if node.task.object != nil', self.host)
        self.assertIn('PlayPlayerSubmissionStatusView(state: submissionReadback?.state(nodeID: node.id)', self.host)
        self.assertIn('if model.hasCurrentProjection, let projection = model.projection', self.host)

    def test_exact_task_and_current_projection_scope(self):
        for expression in ['projection.nodes.first(where:', 'row["taskCode"].text == task',
                           'sessionID: projection.sessionID', 'activityID: projection.activityID',
                           'teamID: projection.teamID', 'revision: projection.revision',
                           'sessionID == projection.sessionID', 'projection.activityID == model.activityID']:
            self.assertIn(expression, self.core)

    def test_newest_unknown_cannot_fall_back_to_old_approval(self):
        self.assertIn('projection.submissions.first(where:', self.core)
        self.assertIn('Status(rawValue: statusText) else { return .unconfirmed }', self.core)
        self.assertIn('seen.insert(id).inserted', self.core)
        self.assertIn('if let previousID, id >= previousID { return .unconfirmed }', self.core)
        self.assertNotIn('.sorted', self.core)

    def test_missing_empty_and_malformed_container_are_not_conflated(self):
        runtime = self.read('Core/PlayGameSessionRuntime.swift')
        self.assertIn('case missing, array, malformed', self.core)
        self.assertIn('if let value = raw["player"].object?["mySubmissions"]', runtime)
        self.assertIn('value.array != nil ? .array : .malformed', runtime)
        self.assertIn('else { submissionContainerShape = .missing }', runtime)
        self.assertIn('guard projection.submissionContainerShape == .array', self.core)
        self.assertIn('submissions = raw["player"]["mySubmissions"].array ?? []', runtime)

    def test_four_states_are_distinct(self):
        for value in ['"PENDING"', '"APPROVED"', '"REJECTED"', '"RECORDED"']:
            self.assertIn(value, self.core)
        self.assertIn('if record.status == .recorded', self.view)
        self.assertIn('playerSubmission.recordedNotice', self.view)

    def test_private_reason_only_in_rejected_and_pending_number_only_pending(self):
        self.assertIn('if status == .rejected', self.core)
        self.assertIn('["reason", "decisionReason"]', self.core)
        self.assertIn('if record.status == .rejected, let reason = record.rejectionReason', self.view)
        self.assertIn('Text(verbatim: reason)', self.view)
        self.assertIn('if record.status == .pending', self.view)
        self.assertNotIn('reasonCode', self.view)

    def test_no_new_api_or_write_authority(self):
        self.assertEqual(self.core.count('await model.load()'), 1)
        for forbidden in ['URLSession', 'transport.send', 'api/', 'submit(', 'allows(', 'playerCommand(', 'redeem(', 'award(', 'qr']:
            self.assertNotIn(forbidden, self.core + self.view)

    def test_original_owner_and_read_grant_rechecked(self):
        for term in ['owner = model.currentSession()', 'owner == model.currentSession()',
                     'model.service.enabled.contains(.reads)', 'model.service.hasCurrentReadLifetime',
                     'model.hasCurrentProjection', 'model.phase == "ready"', 'model.pending == nil']:
            self.assertIn(term, self.core)

    def test_hidden_and_cancelled_screen_cannot_refresh(self):
        self.assertIn('guard isCurrent, !Task.isCancelled, model.phase != "submitting" else { return }', self.core)
        self.assertIn('public func dismiss() { active = false; generation &+= 1 }', self.core)
        self.assertIn('generation == revision', self.core)
        self.assertIn('.onDisappear { submissionReadback?.dismiss() }', self.host)
        self.assertIn('guard !Task.isCancelled else { return }', self.host)

    def test_reopen_has_new_lease_and_refresh_uses_that_lease(self):
        self.assertIn('let readback = PlayPlayerSubmissionReadback(model: model)', self.host)
        self.assertIn('await readback.open()', self.host)
        self.assertIn('if let readback = submissionReadback { Task { await readback.refresh() } }', self.host)
        self.assertNotIn('await model.load()', self.host)

    def test_bilingual_fragment_covers_every_display_key(self):
        data = json.loads(self.read('Resources/PlayPlayerSubmissionStatusLocalizations.fragment.json'))
        keys = set(re.findall(r'"(playerSubmission\.[a-zA-Z]+)"', self.view)) - {'playerSubmission.readback'}
        keys |= {'playerSubmission.status.' + status for status in ['pending', 'approved', 'rejected', 'recorded']}
        self.assertEqual(keys, set(data['strings']))
        for entry in data['strings'].values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])

    def test_dynamic_type_and_privacy_markers(self):
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', self.view)
        self.assertIn('.privacySensitive()', self.view)
        self.assertIn('PlayPlayerSubmissionStatusTests', self.read('Tests/AppUnitTests/PlayPlayerSubmissionStatusTests.swift'))


if __name__ == '__main__':
    unittest.main()
