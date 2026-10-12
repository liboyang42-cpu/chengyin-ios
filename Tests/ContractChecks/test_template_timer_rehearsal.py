import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TemplateTimerRehearsalContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateTimerRehearsal.swift').read_text()
        cls.app = (ROOT / 'App/TemplateTimerRehearsalView.swift').read_text()
        cls.config = (ROOT / 'App/TemplateAdvancedGameConfigurationView.swift').read_text()
        cls.browser = (ROOT / 'App/TemplateAdditionalSampleBrowserView.swift').read_text()

    def test_grouped_core_controller_and_exact_four_entry_modes(self):
        self.assertEqual(self.core.count('public struct TemplateTimerRehearsal:'), 1)
        self.assertEqual(self.app.count('final class TemplateTimerRehearsalController:'), 1)
        for kind in ['countdown', 'stopwatch']:
            self.assertEqual(self.config.count(f'TemplateTimerRehearsalView(model: model, kind: .{kind}, mode: .currentConfiguration)'), 1)
            self.assertEqual(self.browser.count(f'TemplateTimerRehearsalView(model: model, kind: .{kind}, mode: .sourceExample)'), 1)
        self.assertIn('TemplateCoinFlipRehearsalView(model: model, mode: .sourceExample)', self.browser)
        self.assertIn('TemplateAdditionalSamplePreview.Choice.allCases', self.browser)

    def test_actual_source_examples_only_replace_pristine_copy_fields(self):
        data = json.loads(self.core.split('private static let demoJSON = #"""\n', 1)[1].split('\n"""#', 1)[0])
        self.assertEqual(data, {'countdown': {'kicker': '一钟油', 'doneText': '时间到。'}, 'stopwatch': {'kicker': '盲停在 10 秒'}})
        for token in ['let current = fields[key]', 'let expected = defaults[key]', 'bytes == Self.bytes(expected)', 'var copy = original', 'TemplateAuthoringStory.sourceTrim(value)']:
            self.assertIn(token, self.core)

    def test_selected_configuration_range_and_absence_validation(self):
        for token in ['number("seconds", 5...3600)', 'number("targetSeconds", 3...120)', 'number("toleranceMs", 50...5000)', 'number("tries", 0...10)', 'attempts.rounded() == attempts', '!value.isEmpty', 'value.utf16.count <= 60', 'title.utf16.count <= 32']:
            self.assertIn(token, self.core)

    def test_absolute_monotonic_clock_and_two_source_tick_intervals(self):
        self.assertIn('ProcessInfo.processInfo.systemUptime * 1000', self.app)
        self.assertIn('clock: @escaping @MainActor () -> Double', self.app)
        self.assertIn('accumulatedMs + (now - anchor)', self.core)
        self.assertIn('kind == .countdown ? 1 : 0.05', self.app)
        self.assertIn('Int(ceil(targetSeconds - elapsedMs / 1000))', self.core)
        for token in ['elapsedMs +=', 'remainingSeconds -=', 'Date.now', 'Date().timeInterval']:
            self.assertNotIn(token, self.core + self.app)

    def test_countdown_completion_has_no_pause_or_verdict(self):
        self.assertIn('kind == .stopwatch && (phase == .running || phase == .paused)', self.core)
        self.assertIn('kind == .stopwatch && phase == .running', self.core)
        self.assertIn('phase = .finished', self.core)
        self.assertIn('Text(verbatim: state.doneText)', self.app)
        self.assertNotIn('stage.win', self.core + self.app)

    def test_stopwatch_blind_pause_timeout_and_source_readout_math(self):
        for token in ['elapsedMs >= 1000', 'elapsedMs > (targetSeconds + 30) * 1000', 'accumulatedMs = elapsedMs', 'phase = .paused', 'guard canStop else', 'abs(elapsedMs / 1000 - targetSeconds)', 'diff <= tolerance', 'min(0.05, tolerance / 2)', 'diff < 0.005', 'if !matched { misses += 1 }']:
            self.assertIn(token, self.core)
        self.assertIn('} else if state.isMasked {', self.app)
        self.assertIn('.disabled(!state.canStop)', self.app)

    def test_scheduler_cancel_and_queued_tick_identity_precedes_lease(self):
        self.assertIn('protocol TemplateTimerRehearsalScheduler', self.app)
        self.assertIn('subscription.cancel()', self.app)
        self.assertIn('tickGeneration = UUID(); cancelTick?(); cancelTick = nil', self.app)
        tick = self.app.split('private func startTicks()', 1)[1].split('func action(', 1)[0]
        self.assertLess(tick.index('self.tickGeneration == stamp'), tick.index('self.hasLease'))
        self.assertIn('if next.phase != .running { self.stopTicks(); self.generation = UUID() }', tick)
        self.assertIn('[weak self]', tick)

    def test_owner_exact_draft_locks_and_background_retirement(self):
        for token in ['model.objectWillChange.sink', 'self?.retire()', 'owner == model.coordinator.session', 'identity == model.coordinator.identity', 'metadata == model.metadataGeneration', 'media == model.mediaReviewGeneration', 'source == TemplateSamplePreview.snapshot(model.draft)', '!model.busy && model.review == nil', '.onDisappear { controller.viewDisappeared() }', 'controller.sceneChanged(isActive: phase == .active)']:
            self.assertIn(token, self.app)
        self.assertIn('self.generation == stamp', self.app)

    def test_clock_damage_and_invalid_actions_fail_closed(self):
        self.assertIn('now.isFinite && now >= 0', self.core)
        self.assertIn('now >= lastClock!', self.core)
        self.assertIn('return abortReason == .timeout', self.core)
        self.assertIn('guard next.canStart else { return }', self.app)
        self.assertIn('guard next.canStop else { return }', self.app)

    def test_no_task_reward_network_media_or_device_side_effects(self):
        for token in ['URLSession', 'AsyncImage', 'UserDefaults', 'FileManager', 'CoreLocation', 'AVFoundation', 'CoreMotion', 'haptic(', 'START_CHALLENGE', 'SUBMIT_STOPWATCH', 'SUBMIT_COUNTDOWN', 'model.draft =', 'model.changed(', 'model.prepare(', 'model.confirm(', 'requestAuthorization', 'capabilityGrant']:
            self.assertNotIn(token, self.core + self.app)
        self.assertIn('.privacySensitive()', self.app)

    def test_registration_and_thirty_three_bilingual_keys(self):
        strings = json.loads((ROOT / 'docs/localization/template-timer-rehearsal.json').read_text())['strings']
        self.assertEqual(len(strings), 33)
        for item in strings.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'])
        used = set(re.findall(r'(?:Text|Button|Section|LabeledContent|NavigationLink)\("(templateTimer\.[a-zA-Z.]+)"', self.app + self.config + self.browser))
        self.assertTrue(used.issubset(strings), used - set(strings))
        registration = json.loads((ROOT / 'docs/registration/template-timer-rehearsal.json').read_text())
        self.assertEqual(len(registration['dependencies']), 3)
        for name in registration['app_sources'] + registration['package_tests'] + registration['app_unit_tests']:
            self.assertTrue((ROOT / name).is_file())

    def test_native_inventory_includes_cancelled_tick_execution_and_limits(self):
        for name, count in [('Tests/CoreTests/TemplateTimerRehearsalTests.swift', 20), ('Tests/AppUnitTests/TemplateTimerRehearsalViewTests.swift', 19)]:
            self.assertEqual(len(re.findall(r'func test', (ROOT / name).read_text())), count)
        tests = (ROOT / 'Tests/AppUnitTests/TemplateTimerRehearsalViewTests.swift').read_text()
        self.assertIn('func fire(_ index: Int) { jobs[index].tick() }', tests)
        self.assertIn('testQueuedOldTickCannotModifyResetAndNewRun', tests)
        doc = (ROOT / 'docs/template-timer-rehearsal.md').read_text()
        for token in ['NOT_RUN', 'No generic timer-modifier', 'monotonic', 'not by counting ticks', 'Both kinds retire on background', '3-2-1 animation is not reproduced']:
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
