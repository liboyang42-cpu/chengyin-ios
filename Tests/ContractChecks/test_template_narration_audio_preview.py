"""Focused wiring checks only; playback and iOS lifecycle require Apple execution."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NarrationPreviewContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "App/TemplateNarrationAudioPreview.swift").read_text()

    def test_existing_voice_module_mounts_preview_and_preserves_clear(self):
        source = (ROOT / "App/TemplateAuthoringDetailForms.swift").read_text()
        voice = source.split('Section("templateAuthor.voice")', 1)[1].split("@MainActor struct TemplateAuthoringStoryView", 1)[0]
        self.assertIn("TemplateNarrationAudioPreviewEntry(model: model)", voice)
        self.assertIn("action: model.clearNarrationAudioAction()", voice)
        self.assertIn("action: editor.removeImageAction(beat.id, at: imageIndex)", source)

    def test_reuses_gated_session_player_without_new_driver_or_consent_bypass(self):
        for required in ["PlatformAudioPlayback", "PlatformAudioConsumerView", "@Environment(\\.projectChapterAudioPlayback)"]:
            self.assertIn(required, self.source)
        for forbidden in ["AVPlayer", "AVAudioPlayer", "NativePlatformAudioDriver(", "URLSession", "approveSelectedMedia()", "enabled: true", "approvedOrigins:"]:
            self.assertNotIn(forbidden, self.source)
        select = self.source.split("func select(", 1)[1].split("func close(", 1)[0]
        self.assertIn("selection.player.state == .playing || selection.player.state == .paused", select)
        self.assertIn("guard let makePlayer else { return }", select)
        self.assertIn("player.select(", select)
        self.assertNotIn("player.toggle()", select.split("guard let makePlayer", 1)[1])

    def test_draft_is_read_only_and_source_is_strictly_parsed(self):
        for forbidden in ["model.draft =", "model.changed()", "audioDuration =", "audioUrl =", "upload(", "submit("]:
            self.assertNotIn(forbidden, self.source)
        for required in ["reference.utf8.count <= 8192", '$0 >= 33 && $0 != 127', 'url.scheme?.lowercased() == "https"',
                         "url.user == nil", "url.password == nil", "url.fragment == nil", "Data(reference.utf8)"]:
            self.assertIn(required, self.source)

    def test_lifecycle_retires_before_model_change_and_on_departure_background(self):
        self.assertIn("model.objectWillChange.sink { [weak self] _ in self?.retire() }", self.source)
        self.assertIn("selection?.player.dispose()", self.source)
        self.assertIn(".onDisappear { controller.deactivate() }", self.source)
        self.assertIn("if phase == .active { controller.activate() } else { controller.deactivate() }", self.source)
        for required in ["capture.controllerID == controllerID", "capture.generation == generation", "capture.modelGeneration == model.metadataGeneration",
                         "capture.mediaGeneration == model.mediaReviewGeneration", "capture.session == model.coordinator.session", "capture.identity == model.coordinator.identity"]:
            self.assertIn(required, self.source)

    def test_fragments_are_additive_bilingual_and_register_only_preview(self):
        local = json.loads((ROOT / "docs/localization/template-narration-audio-preview.json").read_text())
        self.assertEqual(set(local["strings"]), {"templateNarration.preview", "templateNarration.closePreview", "templateNarration.previewUnavailable"})
        for row in local["strings"].values():
            self.assertEqual(set(row["localizations"]), {"en", "zh-Hans"})
        registry = json.loads((ROOT / "docs/registration/template-narration-audio-preview.json").read_text())
        self.assertEqual(registry["app_sources"], ["App/TemplateNarrationAudioPreview.swift"])
        self.assertEqual(registry["app_unit_tests"], ["Tests/AppUnitTests/TemplateNarrationAudioPreviewTests.swift"])


if __name__ == "__main__":
    unittest.main()
