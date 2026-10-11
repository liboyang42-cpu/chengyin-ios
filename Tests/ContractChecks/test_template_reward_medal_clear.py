"""Focused P036 clearMedal source checks; not Swift or native execution."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RewardMedalClearContracts(unittest.TestCase):
    def test_clear_action_is_in_the_existing_reward_module(self):
        forms = (ROOT / "App/TemplateAuthoringDetailForms.swift").read_text()
        reward = forms.split('Section("templateAuthor.reward")', 1)[1].split('Section("templateAuthor.story")', 1)[0]
        self.assertIn("if model.draft.rewardEnabled", reward)
        self.assertEqual(reward.count('Button("templateReward.clearMedal"'), 1)
        self.assertIn("action: model.clearRewardMedalAction()", reward)
        self.assertIn(".disabled(!model.canClearRewardMedal)", reward)
        self.assertIn('.accessibilityIdentifier("templateReward.clearMedal")', reward)

    def test_snapshot_only_changes_three_medal_fields(self):
        core = (ROOT / "Core/TemplateRewardMedalRemoval.swift").read_text()
        writes = [line.strip() for line in core.splitlines() if line.strip().startswith("next.")]
        self.assertEqual(writes, ["next.medalImg = nil", "next.medalName = nil", 'next.medalStyle = "glow"'])
        self.assertIn("Self.bytes(draft) == original", core)
        self.assertIn("Data($0.utf8)", core)
        self.assertIn("guard canRemove, draft.rewardEnabled", core)
        self.assertNotIn("trimmingCharacters", core)

    def test_action_checks_owner_lifecycle_and_lock_before_writing(self):
        app = (ROOT / "App/TemplateRewardMedalClear.swift").read_text()
        write = app.index("self.draft = next")
        for token in ["self.canEdit", "self.metadataGeneration == generation", "self.mediaReviewGeneration == mediaGeneration",
                      "self.coordinator.session == session", "self.coordinator.identity == identity", "removal.applying(to: self.draft)"]:
            self.assertLess(app.index(token), write)
        self.assertGreater(app.index("self.changed()"), write)

    def test_feature_has_no_service_factory_transport_or_permission_changes(self):
        for path in ["App/TemplateRewardMedalClear.swift", "Core/TemplateRewardMedalRemoval.swift"]:
            source = (ROOT / path).read_text()
            for token in ["URLSession", "HTTPTransport", "makePlayer", "upload(", "submit(", "approve", "UserDefaults"]:
                self.assertNotIn(token, source)

    def test_prior_editor_features_are_preserved(self):
        forms = (ROOT / "App/TemplateAuthoringDetailForms.swift").read_text()
        for token in ["TemplateChoiceOptionRowsFields(model: model)", "TemplateNarrationAudioPreviewEntry(model: model)",
                      "action: model.clearNarrationAudioAction()", "action: editor.removeImageAction(beat.id, at: imageIndex)"]:
            self.assertIn(token, forms)

    def test_fragments_are_bilingual_and_register_exact_new_sources(self):
        local = json.loads((ROOT / "docs/localization/template-reward-medal-clear.json").read_text())
        self.assertEqual(set(local["strings"]), {"templateReward.clearMedal"})
        row = local["strings"]["templateReward.clearMedal"]["localizations"]
        self.assertEqual(row["en"]["stringUnit"]["value"], "Clear medal")
        self.assertEqual(row["zh-Hans"]["stringUnit"]["value"], "清除勋章")
        registry = json.loads((ROOT / "docs/registration/template-reward-medal-clear.json").read_text())
        self.assertEqual(registry["app_sources"], ["App/TemplateRewardMedalClear.swift", "Core/TemplateRewardMedalRemoval.swift"])
        self.assertEqual(registry["app_unit_tests"], ["Tests/AppUnitTests/TemplateRewardMedalClearTests.swift"])
        self.assertEqual(registry["package_tests"], ["Tests/CoreTests/TemplateRewardMedalRemovalTests.swift"])


if __name__ == "__main__":
    unittest.main()
