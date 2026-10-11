"""Focused source/registration contracts. These do not execute Swift or iOS UI."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NarrationAudioClearContracts(unittest.TestCase):
    def test_existing_voice_module_has_one_explicit_guarded_clear_action(self):
        text = (ROOT / "App/TemplateAuthoringDetailForms.swift").read_text()
        voice = text.split('Section("templateAuthor.voice")', 1)[1].split("@MainActor struct TemplateAuthoringStoryView", 1)[0]
        self.assertIn("if model.draft.voiceEnabled", voice)
        self.assertEqual(voice.count('Button("templateNarration.clear"'), 1)
        self.assertIn("action: model.clearNarrationAudioAction()", voice)
        self.assertIn(".disabled(!model.canClearNarrationAudio)", voice)
        self.assertIn('.accessibilityIdentifier("templateNarration.clear")', voice)

    def test_action_checks_the_captured_lease_before_any_write(self):
        text = (ROOT / "App/TemplateNarrationAudioClear.swift").read_text()
        write = text.index("self.draft = next")
        for guard in ["self.canEdit", "self.metadataGeneration == generation", "self.mediaReviewGeneration == mediaGeneration",
                      "self.coordinator.session == session", "self.coordinator.identity == identity", "removal.applying(to: self.draft)"]:
            self.assertLess(text.index(guard), write)
        self.assertLess(text.index("self.mediaReferencesWillChange()"), write)
        self.assertGreater(text.index("self.changed()"), write)

    def test_core_removal_only_clears_the_paired_audio_fields(self):
        text = (ROOT / "Core/TemplateNarrationAudioRemoval.swift").read_text()
        writes = [line.strip() for line in text.splitlines() if line.strip().startswith("next.")]
        self.assertEqual(writes, ["next.audioUrl = nil", "next.audioDuration = nil"])
        self.assertIn("Data($0.utf8)", text)
        self.assertIn("draft.audioDuration == duration", text)
        self.assertIn("guard canRemove, draft.voiceEnabled", text)
        self.assertNotIn("trimmingCharacters", text)

    def test_existing_story_image_removal_ui_is_retained(self):
        text = (ROOT / "App/TemplateAuthoringDetailForms.swift").read_text()
        self.assertIn("action: editor.removeImageAction(beat.id, at: imageIndex)", text)
        self.assertIn('"templateStory.beat.\\(index).removeImage.\\(imageIndex)"', text)
        self.assertIn(".onDisappear { editor.retire() }", text)

    def test_new_implementation_has_no_transport_or_permission_switch(self):
        for path in ["App/TemplateNarrationAudioClear.swift", "Core/TemplateNarrationAudioRemoval.swift"]:
            text = (ROOT / path).read_text()
            for forbidden in ["URLSession", "AVPlayer", "upload(", "submit(", "canSubmit =", "allowProduction", "UserDefaults"]:
                self.assertNotIn(forbidden, text, (path, forbidden))

    def test_localization_fragment_contains_both_languages(self):
        fragment = json.loads((ROOT / "docs/localization/template-narration-audio-clear.json").read_text())
        row = fragment["strings"]["templateNarration.clear"]["localizations"]
        self.assertEqual(row["en"]["stringUnit"]["value"], "Clear narration audio")
        self.assertEqual(row["zh-Hans"]["stringUnit"]["value"], "清除导览音频")

    def test_registration_fragment_names_existing_new_sources_and_tests(self):
        fragment = json.loads((ROOT / "docs/registration/template-narration-audio-clear.json").read_text())
        self.assertEqual(fragment["app_sources"], ["App/TemplateNarrationAudioClear.swift", "Core/TemplateNarrationAudioRemoval.swift"])
        self.assertEqual(fragment["app_unit_tests"], ["Tests/AppUnitTests/TemplateNarrationAudioClearTests.swift"])
        self.assertEqual(fragment["package_tests"], ["Tests/CoreTests/TemplateNarrationAudioRemovalTests.swift"])
        for key in ["app_sources", "app_unit_tests", "package_tests"]:
            for path in fragment[key]:
                self.assertTrue((ROOT / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
