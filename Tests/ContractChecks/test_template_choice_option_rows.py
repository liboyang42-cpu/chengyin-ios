"""Narrow choice-row source contracts; not Swift execution or iOS UI acceptance."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ChoiceOptionRowsContracts(unittest.TestCase):
    def test_editor_route_replaces_fixed_rows_without_changing_owner_default(self):
        forms = (ROOT / "App/TemplateAuthoringDetailForms.swift").read_text()
        self.assertIn("includesHints: false, includesChoiceOptions: false", forms)
        self.assertIn("TemplateChoiceOptionRowsFields(model: model)", forms)
        self.assertIn("var includesChoiceOptions = true", forms)
        self.assertIn("if method == .choice && includesChoiceOptions", forms)
        self.assertIn("TemplateChoiceOptionMediaFields", forms)
        self.assertIn("TemplateNarrationAudioPreviewEntry(model: model)", forms)
        self.assertIn("action: model.clearNarrationAudioAction()", forms)
        self.assertIn("action: editor.removeImageAction(beat.id, at: imageIndex)", forms)

    def test_reordering_keeps_existing_schema_and_bounds(self):
        core = (ROOT / "Core/TemplateChoiceOptionRows.swift").read_text()
        for token in ["letters.count < 4", "letters.count > 2", "Self.bytes(draft) == originalFields",
                      "mediaProjection.isSupported && knownAnswer", "Data($0.utf8)",
                      "shiftedMedia[target.rawValue] = attachment", "next.correctAnswer = Letter.allCases[newCorrect].rawValue",
                      'next.questionOptionMediaJson = ""', "maximumJSONLength"]:
            self.assertIn(token, core)
        for forbidden in ["URLSession", "HTTPTransport", "api/", "UserDefaults", "trimmed", "approvedOrigins"]:
            self.assertNotIn(forbidden, core)

    def test_old_row_bindings_and_actions_are_fenced_before_remap(self):
        app = (ROOT / "App/TemplateChoiceOptionRowsEditor.swift").read_text()
        for token in ["self.generation == stamp, self.canEdit", "self.model.metadataGeneration == mutation",
                      "mediaGeneration == model.mediaReviewGeneration", "methodGeneration == model.legacyHintGeneration",
                      "session == model.coordinator.session", "identity == model.coordinator.identity",
                      "self.model.mediaReferencesWillChange()", "original.wrappedValue = value",
                      ".onDisappear { editor.retire() }"]:
            self.assertIn(token, app)
        action = app.split("func action(", 1)[1].split("@MainActor struct", 1)[0]
        self.assertLess(action.index("self.generation += 1"), action.index("self.model.draft = next"))
        self.assertLess(action.index("self.model.mediaReferencesWillChange()"), action.index("self.model.draft = next"))

    def test_text_and_media_controls_keep_accessible_identities(self):
        app = (ROOT / "App/TemplateChoiceOptionRowsEditor.swift").read_text()
        for token in ["templateChoiceRows.add", "templateChoiceRows.remove.", "templateChoiceRows.correctAnswer",
                      "templateAuthor.optionMedia.", "templateAuthor.optionMedia.unsupported", "templateAuthor.optionMedia.limit",
                      ".disabled(!editor.rows.canRemove)", ".disabled(!editor.rows.canAdd)"]:
            self.assertIn(token, app)

    def test_fragments_are_bilingual_and_register_only_this_feature(self):
        local = json.loads((ROOT / "docs/localization/template-choice-option-rows.json").read_text())
        self.assertEqual(len(local["strings"]), 5)
        for row in local["strings"].values():
            self.assertEqual(set(row["localizations"]), {"en", "zh-Hans"})
        registry = json.loads((ROOT / "docs/registration/template-choice-option-rows.json").read_text())
        self.assertEqual(registry["app_sources"], ["App/TemplateChoiceOptionRowsEditor.swift", "Core/TemplateChoiceOptionRows.swift"])
        self.assertEqual(registry["app_unit_tests"], ["Tests/AppUnitTests/TemplateChoiceOptionRowsEditorTests.swift"])
        self.assertEqual(registry["package_tests"], ["Tests/CoreTests/TemplateChoiceOptionRowsTests.swift"])
        for key in ["app_sources", "app_unit_tests", "package_tests"]:
            for path in registry[key]: self.assertTrue((ROOT / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
