"""Offline structure checks only; these do not execute Swift or demonstrate iOS parity."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class TemplateStoryProjectionChecks(unittest.TestCase):
    def test_projection_is_explicit_and_local_marker_is_not_wire_data(self):
        domain = read('Core/TemplateAuthoringDomain.swift')
        core = read('Core/TemplateAuthoringStory.swift')
        contract = read('Core/TemplateAuthoringContract.swift')
        self.assertIn('public var storyTimelineEdited: Bool?', domain)
        self.assertIn('storyJson = encoded; storyTimelineEdited = true', domain)
        self.assertIn('guard storyTimelineEdited == true else { return storyText }', core)
        self.assertIn('string("storyText", try d.preparedStoryText())', contract)
        self.assertNotIn('storyTimelineEdited', contract)
        self.assertIn('if let issue = storyProjectionIssue { result.append(issue) }', domain)

    def test_unknown_rows_and_oversized_history_are_not_silently_pruned(self):
        core = read('Core/TemplateAuthoringStory.swift')
        self.assertIn('Set(row.keys) == Set(["text", "tag", "imgs"])', core)
        self.assertIn('throw Issue.unsupportedTimeline', core)
        self.assertIn('maximumImagesPerBeat = 6', core)
        self.assertIn('validateImageEdits', core)
        self.assertIn('isSubsequence', core)
        self.assertNotIn('prefix(maximumImagesPerBeat)', core)
        domain = read('Core/TemplateAuthoringDomain.swift').split('public mutating func setStory(')[1].split('public func storyBeats')[0]
        self.assertLess(domain.index('validateImageEdits'), domain.index('storyJson ='))
        self.assertNotIn('storyText =', domain)

    def test_source_utf16_projection_and_explicit_unpaired_surrogate_limit(self):
        core = read('Core/TemplateAuthoringStory.swift')
        for text in ['maximumSummaryUTF16Length = 500', 'joined(separator: "\\n")',
                     'Array(joined.utf16)', '0xFEFF', '0xD800...0xDBFF', '0xDC00...0xDFFF',
                     'throw Issue.summarySurrogateBoundary', 'String(decoding: units.prefix(limit), as: UTF16.self)']:
            self.assertIn(text, core)
        self.assertNotIn('joined.prefix(', core)

    def test_editor_uses_explicit_guarded_mutations_not_load_normalization(self):
        ui = read('App/TemplateStoryEditor.swift')
        load = ui.split('func load()')[1].split('func text(')[0]
        self.assertNotIn('setStory(', load); self.assertNotIn('model.changed()', load)
        for text in ['guard canEdit else', 'session == model.coordinator.session',
                     'identity == model.coordinator.identity', 'originalJSON == model.draft.storyJson',
                     'modelGeneration == model.storyEditorGeneration', 'guard self.generation == stamp',
                     'try draft.setStory(next)', 'model.changed()', 'templateStory.imageLimit']:
            self.assertIn(text, ui)
        form = read('App/TemplateAuthoringDetailForms.swift').split('struct TemplateAuthoringStoryView:')[1].split('struct TemplateAuthoringAdvancedView:')[0]
        self.assertNotIn('.onChange(of: beats)', form)
        self.assertIn('.onAppear { editor.load() }', form)
        self.assertIn('.disabled(!editor.canEdit)', form)
        for name in ['func load()', 'func restore()', 'func discard()']:
            method = read('App/TemplateAuthoringView.swift').split(name)[1].split('\n    func ')[0]
            self.assertIn('storyEditorGeneration += 1', method)

    def test_new_files_never_activate_media_or_writers(self):
        for path in ['Core/TemplateAuthoringStory.swift', 'App/TemplateStoryEditor.swift']:
            source = read(path)
            for forbidden in ['URLSession', 'URLRequest', 'HTTPTransport', 'openURL', 'AsyncImage', 'AVPlayer', 'api/', 'confirm(', 'prepare(']:
                self.assertNotIn(forbidden, source)
        factory = read('App/AppSession.swift').split('func templateAuthoringEditor(')[1].split('private let creatorContentService')[0]
        self.assertIn('TemplateAuthoringAdapter()', factory)
        self.assertNotIn('transport:', factory)

    def test_labels_match_actual_bilingual_catalog(self):
        labels = json.loads(read('tools/template_story_localizations.json'))
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        for key, translations in labels.items():
            self.assertEqual(set(translations), {'en', 'zh-Hans'})
            for language, value in translations.items():
                self.assertTrue(value)
                self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], value)
        used = set()
        for path in ['Core/TemplateAuthoringStory.swift', 'App/TemplateStoryEditor.swift', 'App/TemplateAuthoringDetailForms.swift']:
            used.update(re.findall(r'"(templateStory\.[A-Za-z]+)"', read(path)))
        self.assertLessEqual(used - {'templateStory.issue', 'templateStory.open', 'templateStory.summary'}, labels.keys())

    def test_apple_test_vectors_exist_without_claiming_execution(self):
        core = read('Tests/CoreTests/TemplateAuthoringStoryTests.swift')
        for text in ['testExactECMAScriptTrimWhitespaceSet', 'testNewSeventhImageIsRejectedAtomically',
                     'testSplitSurrogateBlocksRequestWithoutCorruptingFullText',
                     'testUnknownMalformedAndMissingFieldsStayUntouchedAndCannotBeEdited',
                     'testReadingAndPreparingUneditedSupportedTimelineKeepsOriginalBytes',
                     'testOptionalMarkerRoundTripsAndOldEnvelopeStillDecodes',
                     'testStoreRestoresExplicitMarkerAndOriginalIndependentText']:
            self.assertIn(text, core)
        app = read('Tests/AppUnitTests/TemplateStoryEditorLifecycleTests.swift')
        for text in ['testExplicitEditCommitsBeforeParentReappearanceAndSurvivesRestore',
                     'testDiscardInvalidatesStaleBindingEvenWhenIdentityAndRawJSONAreUnchanged',
                     'testStaleBindingCannotWriteAfterEpochChangeOrReload']:
            self.assertIn(text, app)
        self.assertIn('Tests/AppUnitTests/TemplateStoryEditorLifecycleTests.swift', read('Questify.xcodeproj/project.pbxproj'))


if __name__ == '__main__':
    unittest.main()
