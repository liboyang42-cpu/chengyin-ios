"""Focused source contracts, not Swift execution or end-to-end acceptance."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class StoryImageRemovalContracts(unittest.TestCase):
    def test_actual_view_calls_editor_and_retires_actions(self):
        source = (ROOT / 'App/TemplateAuthoringDetailForms.swift').read_text()
        self.assertIn('action: editor.removeImageAction(beat.id, at: imageIndex)', source)
        self.assertIn('.onDisappear { editor.retire() }', source)
        self.assertIn('.onDisappear { media.retire() }', source)
        self.assertIn('ForEach(Array(beat.imgs.enumerated()), id: \\.offset)', source)
        self.assertIn('Text(verbatim: reference)', source)
        self.assertIn('.buttonStyle(.borderless)', source)

    def test_editor_uses_local_commit_and_existing_lease(self):
        source = (ROOT / 'App/TemplateStoryEditor.swift').read_text()
        block = source.split('func removeImageAction', 1)[1].split('func add()', 1)[0]
        for required in ['[weak self]', 'self.generation == stamp', 'self.canEdit',
                         'self.apply', '$0.id == beatID', 'removal.applying(to: rows[row].imgs)',
                         'func retire() { generation += 1 }']:
            self.assertIn(required, block)
        self.assertIn('modelGeneration == model.storyEditorGeneration', source)
        self.assertIn('identity == model.coordinator.identity', source)
        self.assertIn('session == model.coordinator.session', source)
        self.assertIn('model.mediaReferencesWillChange()', source)
        self.assertIn('model.changed()', source)

    def test_occurrence_and_exact_snapshot_guard(self):
        source = (ROOT / 'Core/TemplateStoryImageRemoval.swift').read_text()
        for required in ['images.indices.contains(index)', 'images.count == snapshot.count',
                         'utf8.elementsEqual', 'result.remove(at: index)']:
            self.assertIn(required, source)
        for forbidden in ['URLSession', 'FileManager', 'upload(', 'deleteAsset', 'filter(']:
            self.assertNotIn(forbidden, source)

    def test_localization_fragment_and_runtime_test_coverage(self):
        fragment = json.loads((ROOT / 'docs/localization/template-story-image-removal.json').read_text())
        for key in ['templateStory.removeImage', 'templateStory.removeImageNumber %lld']:
            self.assertEqual(set(fragment['strings'][key]['localizations']), {'en', 'zh-Hans'})
        tests = (ROOT / 'Tests/AppUnitTests/TemplateStoryImageRemovalLifecycleTests.swift').read_text()
        self.assertEqual(tests.count('    func test'), 6)
        for required in ['unknown://a', 'cancelled()', 'session = try owner(2)', 'model.discard()', 'editor.load()', 'model.save()', 'unknown":true']:
            self.assertIn(required, tests)

if __name__ == '__main__':
    unittest.main()
