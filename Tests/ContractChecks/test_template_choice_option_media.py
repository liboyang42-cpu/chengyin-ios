"""Choice attachment source checks; these do not execute Swift or Apple UI."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class TemplateChoiceOptionMediaChecks(unittest.TestCase):
    def test_typed_inert_projection_preserves_raw_and_rejects_unknown_edit(self):
        core = read('Core/TemplateChoiceOptionMedia.swift')
        for text in ['case a = "A", b = "B", c = "C", d = "D"', 'case image = "img", audio',
                     'public let originalText: String?', 'originalText = raw', 'raw.utf8.count <= 65_536',
                     'Letter(rawValue: letter) != nil', 'Kind(rawValue: key) != nil',
                     'guard isSupported else', 'return originalText', 'return ""',
                     'maximumReferenceLength = 500', 'maximumJSONLength = 2_000',
                     'value.utf16.count <= Self.maximumReferenceLength', 'serialized.utf16.count <= Self.maximumJSONLength']:
            self.assertIn(text, core)
        for text in ['URLSession', 'URLRequest', 'HTTPTransport', 'Codable', 'api/', 'Task {']:
            self.assertNotIn(text, core)

    def test_existing_professional_editor_preview_and_owner_share_fields(self):
        forms = read('App/TemplateAuthoringDetailForms.swift')
        self.assertIn('model.draft.validationMethod == .choice', forms)
        self.assertIn('field: { model.optionMedia($0, $1) }, issueKey: model.optionMediaIssue).disabled(!model.canEdit)', forms)
        self.assertIn('.disabled(readOnly || !configuration.isSupported)', forms)
        self.assertIn('readOnly && configuration.isSupported && configuration.text(letter, kind) == nil', forms)
        self.assertIn('TemplateChoiceOptionMediaFields(configuration: draft.choiceOptionMedia', read('App/TemplateAuthoringView.swift'))
        owner = read('App/OwnedTemplateConfigurationView.swift')
        self.assertIn('if method == .choice', owner)
        self.assertIn('TemplateChoiceOptionMediaFields(configuration: media', owner)
        self.assertIn('.constant(media.text(letter, kind) ?? "") }, readOnly: true)', owner)
        for text in ['AsyncImage', 'AVPlayer', 'openURL', 'URLSession']:
            self.assertNotIn(text, forms)

    def test_new_binding_fences_session_draft_and_completion_method(self):
        binding = read('App/TemplateAuthoringView.swift').split('func optionMedia(')[1].split('\n}\n')[0]
        for text in ['bindingEpoch = epoch', 'bindingIdentity = draftIdentity', 'self.canEdit',
                     'self.epoch == bindingEpoch', 'self.draftIdentity == bindingIdentity',
                     'self.draft.validationMethod == .choice', 'self.optionMediaGeneration == bindingGeneration',
                     'try self.draft.setChoiceOptionMedia', 'self.changed()']:
            self.assertIn(text, binding)
        self.assertNotIn('prepare(', binding); self.assertNotIn('confirm(', binding)

    def test_owner_projection_stays_after_identity_gate_and_public_projection_unchanged(self):
        core = read('Core/OwnedTemplateConfiguration.swift')
        self.assertLess(core.index('fields["memberId"]?.integer == accountID'),
                        core.index('questionOptionMediaJson = .read'))
        self.assertIn('private let originalResponse: Data', core)
        self.assertNotIn('questionOptionMedia', read('Core/MemberTemplateDetail.swift'))
        for text in ['testChoiceOptionMediaIsOwnerOnlyExactReadWithMissingAndUnsupportedStates',
                     'snapshot.hasExactBaseline(bytes)', 'accountID: 8']:
            self.assertIn(text, read('Tests/CoreTests/OwnedTemplateConfigurationTests.swift'))

    def test_actual_catalog_matches_additive_bilingual_source(self):
        labels = json.loads(read('tools/template_choice_option_media_localizations.json'))
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(labels), 6)
        for key, translations in labels.items():
            self.assertEqual(set(translations), {'en', 'zh-Hans'})
            for language, text in translations.items():
                self.assertTrue(text)
                self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], text)

    def test_authored_lifecycle_and_lossless_vectors_exist(self):
        core = read('Tests/CoreTests/TemplateChoiceOptionMediaTests.swift')
        for name in ['testAbsentEmptyAndExplicitEmptyObjectRemainDistinctUntilEdited',
                     'testExplicitEditAndClearKeepOtherMediaAndOptionValues',
                     'testUnknownMalformedAndOversizeRawAreNeverReplacedByEditor',
                     'testDraftEnvelopeRoundTripDoesNotNormalizeRaw',
                     'testExistingChoicePayloadAndInactiveOmissionAreUnchanged',
                     'testExplicitLastAttachmentClearUsesExistingEmptyStringWireValue',
                     'testReference500501BoundaryAndRelativeOpaqueFormatsUseSourceRules',
                     'testAggregate20002001BoundaryPreservesExactHistoricalAndRejectedDraft',
                     'testSupplementaryUnicodeUsesUTF16RatherThanGraphemeOrUTF8Count']:
            self.assertIn(name, core)
        app = read('Tests/AppUnitTests/TemplateCompositionLifecycleTests.swift')
        for name in ['testChoiceOptionMediaBindingSurvivesLocalSaveAndParentReappearance',
                     'testChoiceOptionMediaBindingCannotChangeUnsupportedRawOrOtherMethods',
                     'testRetainedChoiceOptionMediaBindingCannotChangeNewAccountDraft',
                     'testDiscardFencesRetainedChoiceMediaBindingWithinSameSession',
                     'testChoiceOptionMediaLimitFailureIsVisibleWithoutReplacingDraft']:
            self.assertIn(name, app)
