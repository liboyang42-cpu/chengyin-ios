"""Supplementary STORY-READ-01 structure checks; no Swift or Apple execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class TemplateStoryReadbackChecks(unittest.TestCase):
    def test_model_read_lease_uses_captured_owner_without_write_lock(self):
        model = (ROOT / 'App/TemplateAuthoringView.swift').read_text()
        lease = model.split('var canReadStoryDraft: Bool {', 1)[1].split('}', 1)[0]
        for guard in ['coordinator.session != nil', 'epoch == coordinator.session', 'draftIdentity == coordinator.identity']:
            self.assertIn(guard, lease)
        self.assertNotIn('canEdit', lease); self.assertNotIn('locked', lease)

    def test_getters_and_rendered_metadata_share_current_read_lease(self):
        editor = (ROOT / 'App/TemplateStoryEditor.swift').read_text()
        lease = editor.split('private var hasCurrentReadLease: Bool {', 1)[1].split('}', 1)[0]
        for guard in ['model.canReadStoryDraft', 'session != nil', 'modelGeneration == model.storyEditorGeneration',
                      'session == model.coordinator.session', 'identity == model.coordinator.identity', 'originalJSON == model.draft.storyJson']:
            self.assertIn(guard, lease)
        self.assertNotIn('canEdit', lease)
        self.assertIn('var canRead: Bool { supported && hasCurrentReadLease }', editor)
        self.assertIn('var visibleBeats: [TemplateStoryBeat] { canRead ? beats : [] }', editor)
        self.assertIn('var visibleIssueKey: String? { hasCurrentReadLease ? issueKey : nil }', editor)
        for name in ['text', 'images']:
            body = editor.split('func ' + name + '(', 1)[1].split('\n    }', 1)[0]
            getter = body.split('return .init(get: {', 1)[1].split('}, set:', 1)[0]
            self.assertIn('guard self.generation == stamp, self.canRead else { return "" }', getter)
            self.assertNotIn('canEdit', getter)
            self.assertIn('guard self.generation == stamp else { return }', body)
            self.assertIn('self.apply', body)
        forms = (ROOT / 'App/TemplateAuthoringDetailForms.swift').read_text().split('struct TemplateAuthoringStoryView:', 1)[1].split('struct TemplateAuthoringAdvancedView:', 1)[0]
        self.assertIn('ForEach(Array(editor.visibleBeats.enumerated()), id: \\.element.id)', forms)
        self.assertIn('if let issue = editor.visibleIssueKey', forms)
        self.assertNotIn('ForEach(editor.beats)', forms)
        self.assertNotIn('if let issue = editor.issueKey', forms)

    def test_authored_regressions_cover_locks_drift_and_local_generation(self):
        tests = (ROOT / 'Tests/AppUnitTests/TemplateStoryReadbackTests.swift').read_text()
        for token in ['.submitting', '.simulated', '.uncertain', '.acknowledged', 'try owner(912)',
                      'try owner(epoch: 2)', 'try owner(role: "merchant")', 'session = nil',
                      'testNewEditorCannotLeaseOldModelDraftAfterCoordinatorIdentityReplacement',
                      'testSameOwnerModelAndEditorReloadRevokeOldBindingsWithoutChangingRawDraft',
                      'testRestoreAndDiscardRevokeReadLeasesAndPreserveHistoricalBytes',
                      'testRawReplacementAndCachedIssueCannotLeakThroughPriorReadLease']:
            self.assertIn(token, tests)
        self.assertNotIn('URLSession', tests)
        self.assertIn('Tests/AppUnitTests/TemplateStoryReadbackTests.swift', (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text())

if __name__ == '__main__': unittest.main()
