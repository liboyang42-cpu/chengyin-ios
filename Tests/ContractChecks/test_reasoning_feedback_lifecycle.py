"""Source wiring checks only; authored Swift tests require the Apple test lane."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReasoningFeedbackLifecycleChecks(unittest.TestCase):
    def test_reasoning_form_and_generic_footer_share_the_same_visibility(self):
        form = (ROOT / 'App/PlayKitReasoningForms.swift').read_text()
        screen = (ROOT / 'App/PlayKitScreen.swift').read_text()
        self.assertIn('showResult: reasoningFeedback.showsResult(for: projection)', form)
        self.assertIn('if showResult, let resultKey = PlayKitScreenProjection', form)
        self.assertIn('onDirty: { reasoningFeedback.markEdited(projection); dirty = true }', form)
        footer = screen.split('@ViewBuilder var authoritativeResult:', 1)[1].split('@ViewBuilder private var recovery:', 1)[0]
        self.assertIn('if reasoningFeedback.showsResult(for: projection)', footer)
        self.assertLess(footer.index('reasoningFeedback.showsResult'), footer.index('projection.reportedPass'))
        self.assertLess(footer.index('reasoningFeedback.showsResult'), footer.index('projection.feedback'))

    def test_all_edit_paths_are_guarded_and_invalidate_only_on_actual_changes(self):
        form = (ROOT / 'App/PlayKitReasoningForms.swift').read_text()
        self.assertEqual(form.count('guard enabled, value != (placement[item.id] ?? "") else { return }'), 2)
        self.assertIn('guard enabled, index != destination, order.indices.contains(index)', form)
        self.assertEqual(form.count('onDirty()'), 3)
        self.assertIn('.disabled(!enabled || !valid)', form)
        self.assertIn('placement = placement.filter { $0.key == item.id || $0.value != value }', form)

    def test_scope_reset_clears_feedback_and_reasoning_draft_together(self):
        form = (ROOT / 'App/PlayKitReasoningForms.swift').read_text()
        screen = (ROOT / 'App/PlayKitScreen.swift').read_text()
        self.assertIn('.id(lifetime)', form)
        cleanup = screen.split('private func clearTransient()', 1)[1].split('@MainActor struct PlayKitPayloadReadback', 1)[0]
        self.assertIn('reasoningFeedback = .init()', cleanup)
        self.assertIn('lifetime = UUID()', cleanup)
        self.assertIn('if sessionIdentity != next { clearTransient()', screen)
        self.assertIn('if !current { clearTransient() }', screen)
        self.assertIn('.onDisappear { clearTransient() }', screen)

    def test_background_preserves_reasoning_draft_and_feedback_identity(self):
        form = (ROOT / 'App/PlayKitReasoningForms.swift').read_text()
        screen = (ROOT / 'App/PlayKitScreen.swift').read_text()
        self.assertIn('.id(lifetime)', form)
        self.assertNotIn('.id(childReset)', form)
        background = screen.split('.onChange(of: scenePhase)', 1)[1].split('.onDisappear', 1)[0]
        self.assertIn('if phase == .background { childReset = UUID() }', background)
        for token in ['lifetime =', 'reasoningFeedback =', 'clearTransient()']:
            self.assertNotIn(token, background)
        # The existing screen lifetime is reset only at actual scope cleanup.
        self.assertEqual(screen.count('lifetime = UUID()'), 2)  # declaration + clearTransient

    def test_feedback_is_presentation_only_and_attempt_cap_is_not_a_receipt(self):
        core = (ROOT / 'Core/PlayKitScreenContracts.swift').read_text()
        state = core.split('public struct PlayKitReasoningFeedbackState:', 1)[1].split('/// A bounded picker', 1)[0]
        for token in ['[.sort, .match, .classify]', '!projection.complete', 'if projection.complete { return true }', 'attempts > max(0, editedAttempt ?? 0)']:
            self.assertIn(token, state)
        for token in ['maxAttempts', 'lastCorrect', 'answerOrder', 'score', 'xp', 'SUBMIT_', 'version']:
            self.assertNotIn(token, state)
        screen = (ROOT / 'App/PlayKitScreen.swift').read_text()
        self.assertIn('model.canInteract && !projection.complete && review == nil', screen)


if __name__ == '__main__':
    unittest.main()
