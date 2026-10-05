"""Static regressions only; native UI behavior requires the authored Apple tests."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class PresentationStateContracts(unittest.TestCase):
    def test_editor_keyboard_and_dirty_cancel_are_explicit(self):
        source = (ROOT / "App/SocialActionViews.swift").read_text()
        for token in ["@FocusState", ".scrollDismissesKeyboard(.interactively)", "social.editor.keyboardDone", "if hasDraft { confirmsDiscard = true }", ".interactiveDismissDisabled(hasDraft || preparing)", "social.editor.keepEditing", "social.editor.discard", "if !initialized", "guard review == nil else { return }", ".interactiveDismissDisabled(busy)"]:
            self.assertIn(token, source)
    def test_copy_feedback_is_local_explicit_and_resets(self):
        source = (ROOT / "App/NativeCopyTextButton.swift").read_text()
        self.assertIn("try copyText(text); status = .copied", source)
        self.assertIn("catch { status = .failed }", source)
        self.assertIn("UIAccessibility.post(notification: .announcement", source)
        self.assertIn(".onChange(of: text)", source)
        self.assertIn(".onDisappear { status = nil }", source)
        for token in ["URLSession", "openURL", "UIApplication.shared", "tel:"]:
            self.assertNotIn(token, source)
    def test_new_copy_and_editor_labels_are_bilingual(self):
        fragment = json.loads((ROOT / "Resources/PresentationStateLocalizations.fragment.json").read_text())
        catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        for key, value in fragment.items():
            self.assertEqual(catalog[key], value)
            for locale in ["en", "zh-Hans"]:
                self.assertTrue(value["localizations"][locale]["stringUnit"]["value"].strip())
