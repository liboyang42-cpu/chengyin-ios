import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TemplateReactionRehearsalContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateReactionRehearsal.swift').read_text()
        cls.app = (ROOT / 'App/TemplateReactionRehearsalView.swift').read_text()
        cls.config = (ROOT / 'App/TemplateAdvancedGameConfigurationView.swift').read_text()
        cls.browser = (ROOT / 'App/TemplateAdditionalSampleBrowserView.swift').read_text()

    def test_one_core_and_two_exact_entry_modes_preserve_existing_views(self):
        self.assertEqual(self.core.count('public struct TemplateReactionRehearsal:'), 1)
        self.assertEqual(self.app.count('final class TemplateReactionRehearsalController:'), 1)
        self.assertEqual(self.config.count('TemplateReactionRehearsalView(model: model, mode: .currentConfiguration)'), 1)
        self.assertEqual(self.browser.count('TemplateReactionRehearsalView(model: model, mode: .sourceExample)'), 1)
        for name in ['TemplateCoinFlipRehearsalView', 'TemplateTimerRehearsalView']:
            self.assertIn(name, self.config); self.assertIn(name, self.browser)
        self.assertIn('TemplateAdditionalSamplePreview.Choice.allCases', self.browser)

    def test_actual_source_demo_is_pristine_copy_only(self):
        for token in ['fields["kicker"] = .string("屏幕一变色就点")', 'let current = fields["kicker"]', 'bytes == Self.bytes(expected)', 'var copy = original', 'TemplateAuthoringStory.sourceTrim(rawTitle)', '"变绿就点"']:
            self.assertIn(token, self.core)
        self.assertNotIn('copy = TemplateAdvancedDraft()', self.core)

    def test_source_native_configuration_intersection(self):
        for token in ['number("rounds", 1...10)', 'count.rounded() == count', 'number("goalMs", 120...2000)', 'title.utf16.count <= 32', 'guard let value = fields[key]?.number', 'value.isFinite']:
            self.assertIn(token, self.core)
        self.assertIn('3000', self.core)

    def test_deterministic_wait_and_actual_signal_anchor(self):
        for token in ['(1400 + unit * 2800).rounded()', '(0...1).contains(unit)', 'now >= deadline', 'signalAt = now', 'let elapsed = now - signalAt']:
            self.assertIn(token, self.core)
        self.assertIn('delayUnit: @escaping @MainActor () -> Double', self.app)
        self.assertIn('floor(ProcessInfo.processInfo.systemUptime * 1000)', self.app)
        self.assertNotIn('elapsed = now - deadline', self.core)

    def test_early_rounds_best_and_inclusive_goal(self):
        for token in ['markEarly(.beforeSignal)', 'guard elapsed >= 120', 'markEarly(.belowHumanMinimum)', 'times.append(elapsed)', 'times.count >= rounds', 'times.min()', '$0 <= goalMs', 'phase == .finished ?']:
            self.assertIn(token, self.core)
        early = self.core.split('private mutating func markEarly', 1)[1].split('private mutating func abort', 1)[0]
        self.assertNotIn('times', early)

    def test_reuses_28_clock_scheduler_without_duplicate_implementation(self):
        for token in ['any TemplateTimerRehearsalScheduler', 'TemplateTimerSystemScheduler()', 'TemplateTimerCancellation?']:
            self.assertIn(token, self.app)
        for token in ['protocol TemplateTimerRehearsalScheduler', 'Timer.publish', 'DispatchQueue', 'Task.sleep']:
            self.assertNotIn(token, self.app)
        self.assertIn('scheduler.schedule(interval: milliseconds / 1000)', self.app)

    def test_cancelled_wait_identity_precedes_lease_and_early_tick_reschedules(self):
        tick = self.app.split('private func scheduleSignal(', 1)[1].split('func action(', 1)[0]
        self.assertLess(tick.index('self.waitGeneration == stamp'), tick.index('self.hasLease'))
        for token in ['self.stopWait()', 'self.scheduleSignal(after: deadline - now)', 'if next.phase != .waiting { self.generation = UUID() }', '[weak self]']:
            self.assertIn(token, tick)
        self.assertIn('waitGeneration = UUID(); cancelWait?(); cancelWait = nil', self.app)

    def test_owner_draft_metadata_and_scene_fences(self):
        for token in ['model.objectWillChange.sink', 'self?.retire()', 'owner == model.coordinator.session', 'identity == model.coordinator.identity', 'metadata == model.metadataGeneration', 'media == model.mediaReviewGeneration', 'source == TemplateSamplePreview.snapshot(model.draft)', '!model.busy && model.review == nil', '.onDisappear { controller.viewDisappeared() }', 'controller.sceneChanged(isActive: phase == .active)', 'self.generation == stamp']:
            self.assertIn(token, self.app)

    def test_invalid_clock_and_closed_stage_fail_closed(self):
        for token in ['now.isFinite && now >= 0', 'now >= lastClock!', '(now + delay).isFinite, now + delay > now', 'phase = .aborted', 'guard canArm else', 'guard phase == .waiting || phase == .signal else']:
            self.assertIn(token, self.core)
        self.assertIn('if case .tap = action, !next.canTap { return }', self.app)
        self.assertIn('case .reset: next.reset()', self.app)

    def test_no_production_network_sensors_or_draft_mutation(self):
        for token in ['URLSession', 'AsyncImage', 'UserDefaults', 'FileManager', 'CoreLocation', 'AVFoundation', 'CoreMotion', 'haptic(', 'triggerEvent(', 'SUBMIT_REACTION', 'model.draft =', 'model.changed(', 'model.prepare(', 'model.confirm(', 'requestAuthorization', 'capabilityGrant']:
            self.assertNotIn(token, self.core + self.app)
        self.assertIn('.privacySensitive()', self.app)

    def test_stage_has_text_accessibility_and_no_advance_countdown(self):
        for token in ['.accessibilityIdentifier("templateReaction.stage")', '.accessibilityLabel(LocalizedStringKey(stageKey(state)))', '.accessibilityHint(LocalizedStringKey(hintKey(state)))', '.frame(maxWidth: .infinity, minHeight: 180)', 'case .waiting: return "templateReaction.wait"', 'case .signal: return "templateReaction.tap"']:
            self.assertIn(token, self.app)
        self.assertNotIn('waitUntil', self.app.split('@MainActor struct TemplateReactionRehearsalView', 1)[1])

    def test_all_thirty_strings_and_registration_fragments(self):
        strings = json.loads((ROOT / 'docs/localization/template-reaction-rehearsal.json').read_text())['strings']
        self.assertEqual(len(strings), 30)
        for item in strings.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'])
        used = set(re.findall(r'"(templateReaction\.[a-zA-Z.]+)"', self.app + self.config + self.browser))
        identifiers = set(re.findall(r'accessibilityIdentifier\("([^"]+)"', self.app + self.config + self.browser))
        self.assertTrue((used - identifiers).issubset(strings), used - identifiers - set(strings))
        registration = json.loads((ROOT / 'docs/registration/template-reaction-rehearsal.json').read_text())
        self.assertEqual(len(registration['dependencies']), 4)
        for name in registration['app_sources'] + registration['package_tests'] + registration['app_unit_tests']:
            self.assertTrue((ROOT / name).is_file())

    def test_native_test_inventory_and_cancelled_callback_probe(self):
        for name, count in [('Tests/CoreTests/TemplateReactionRehearsalTests.swift', 20), ('Tests/AppUnitTests/TemplateReactionRehearsalViewTests.swift', 23)]:
            self.assertEqual(len(re.findall(r'func test', (ROOT / name).read_text())), count)
        tests = (ROOT / 'Tests/AppUnitTests/TemplateReactionRehearsalViewTests.swift').read_text()
        for name in ['func fire(_ index: Int) { jobs[index].tick() }', 'testEarlyCallbackReschedulesRemainingAndOldJobCannotSignal', 'testDraftABARetiresAndOldCallbackCannotRetireFreshLease', 'testRetireBackgroundAndReentryDiscardPartialRunAndQueuedWait', 'testOldResetCannotClearFreshAcceptedResult']:
            self.assertIn(name, tests)

    def test_scope_limits_are_explicit(self):
        doc = (ROOT / 'docs/template-reaction-rehearsal.md').read_text()
        for token in ['NOT_RUN', '120...2000', '3000', 'No 3-2-1', 'stricter than Mini hide', 'not verified player scores', 'Private Mini commit', 'physical display latency', 'without modifying that sealed file']:
            self.assertIn(token, doc)

    def test_retained_hidden_destination_cannot_reactivate_on_foreground(self):
        for token in ['private(set) var isVisible = false', 'private var sceneActive = false',
                      'var canReload: Bool { isVisible && sceneActive && model.canReadStoryDraft',
                      'func viewDisappeared() { isVisible = false; retire() }',
                      'guard isVisible && sceneActive else { retire(); return }',
                      'if !active { reload() }', 'if becameActive || !active { reload() }',
                      'controller.viewAppeared(sceneIsActive: scenePhase == .active)',
                      'controller.sceneChanged(isActive: phase == .active)']:
            self.assertIn(token, self.app)
        self.assertNotIn('.onAppear { controller.reload() }', self.app)
        self.assertNotIn('if phase == .active { controller.reload() }', self.app)
