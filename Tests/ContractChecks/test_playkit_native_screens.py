"""Native-local source contracts. These are not Swift compilation or device tests."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class PlayKitNativeScreenChecks(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_all_source_screen_kinds_are_registered_and_dispatched(self):
        contracts = self.read('Core/PlayKitScreenContracts.swift')
        view = self.read('App/PlayKitScreen.swift')
        expected = ['coinFlip','diceRoll','reaction','ballShake','quietHold','countdown','stopwatch','qa','branch','estimate','pricePair','hiddenObject','predict','random','scan','walk','bingo','profile','photoCheck','note','typeIn','dailySign','sort','match','classify','compass','shout']
        for kind in expected:
            self.assertRegex(contracts, r'\b'+kind+r'\b')
            self.assertIn('.'+kind, view)
        self.assertIn('NavigationLink', self.read('App/PlayAdvancedView.swift'))
        self.assertIn('PlayKitScreenKind.present(in: state)', self.read('App/PlayAdvancedView.swift'))
    def test_review_is_immutable_session_and_version_bound(self):
        runtime = self.read('Core/PlayAdvancedRuntime.swift')
        for check in ['state.sessionID == review.sessionID', 'state.version == review.version', 'currentSession() == review.owner', 'key: review.id.uuidString', 'payload: review.payload']:
            self.assertIn(check, runtime)
        self.assertIn('lifetime == expectedLifetime', self.read('App/PlayKitScreen.swift'))
    def test_no_live_grants_were_added(self):
        self.assertIn('enabled: Set<PlayExperienceCapability> = []', self.read('Core/PlayExperienceService.swift'))
        self.assertIn('grants: Set<PlayKitSensorKind> = []', self.read('App/PlayKitNativeSensorProvider.swift'))
        self.assertIn('approvedArtworkHosts: Set<String> = []', self.read('App/PlayKitScreen.swift'))
        self.assertIn('makeSensorProvider?() ?? PlayKitDormantSensorProvider()', self.read('App/PlayKitSensorChallengeView.swift'))
    def test_no_new_network_routes_or_local_reward_mutation(self):
        code = '\n'.join(p.read_text() for p in (ROOT/'App').glob('PlayKit*.swift'))
        for forbidden in ['api/play/', 'SUBMIT_BINGO', 'CLAIM_BINGO', 'URLSession.shared', 'passed = true', 'readyForBase = true']:
            self.assertNotIn(forbidden, code)
    def test_photo_has_separate_capture_upload_and_task_review(self):
        code = self.read('App/PlayKitPersonalForms.swift')
        for token in ['await model.capture(.photo)', 'await model.uploadPhoto()', 'model.reviewedPhoto()', 'capturedIdentity == identity', 'bytes.count > 10 * 1024 * 1024', 'SUBMIT_PHOTO_CHECK']:
            self.assertIn(token, code)
        self.assertIn('model.cancel()', code)
    def test_quiet_uses_audio_and_ball_uses_real_motion(self):
        native = self.read('App/PlayKitNativeSensorProvider.swift')
        for token in ['startAccelerometerUpdates', '9.80665', 'installTap', 'floatChannelData', 'startUpdatingHeading', 'NSMicrophoneUsageDescription']:
            self.assertIn(token, native)
        for forbidden in ['AVAudioRecorder', 'write(to:', 'uploadPhoto(', 'startUpdatingLocation']:
            self.assertNotIn(forbidden, native)
    def test_timing_is_acknowledgement_gated_and_lifecycle_bound(self):
        code = self.read('App/PlayKitTimedChallengeView.swift')
        for token in ['requestReview("START_CHALLENGE"', 'beginAfterAcknowledgement', 'currentRevisionIdentity?()', '.onDisappear', 'scenePhase', 'reaction.tick(now: now)']:
            self.assertIn(token, code)
        self.assertIn('SUBMIT_COUNTDOWN", [:]', code)
    def test_bingo_reads_real_server_progress_and_walk_locks_goal(self):
        code = self.read('Core/PlayKitScreenContracts.swift')+self.read('App/PlayKitDecisionProgressViews.swift')
        for token in ['filledPositions', 'completedLines', 'cellSpecs', 'todaySteps', 'goalLocked', 'providerGate']:
            self.assertIn(token, code)
        self.assertNotIn('filled.insert', code)
    def test_multi_select_and_five_source_additions_are_bounded(self):
        core = self.read('Core/PlayKitScreenContracts.swift')
        for key in ['optionIds', 'order', 'pairs', 'placement', 'bearing', 'heldMs']:
            self.assertIn('"'+key+'"', core)
        self.assertIn('Set(rows.map { $0[0] }) == left', core)
        self.assertIn('case .bingo, .walk, .steps: throw PlayExperienceError.unsupported', core)
    def test_inline_has_no_nested_navigation_or_scroller(self):
        code = self.read('App/PlayKitScreen.swift')
        self.assertIn('if presentation == .inline { contents }', code)
        inline = code.split('struct PlayKitInlineHost',1)[1]
        self.assertNotIn('NavigationStack', inline)
        self.assertNotIn('ScrollView', inline)
        self.assertIn('presentation: .inline', inline)
    def test_localization_fragment_covers_all_new_visible_literals(self):
        catalog = json.loads(self.read('Resources/PlayKitScreenLocalizations.fragment.json'))['strings']
        docs = json.loads(self.read('docs/playkit-screen-localizations.json'))
        self.assertEqual(set(catalog),set(docs))
        for path in (ROOT/'App').glob('PlayKit*.swift'):
            code=path.read_text()
            keys=re.findall(r'(?:Text|Button|Label|Section|LabeledContent|TextField|ProgressView|navigationTitle)\("(playkit\.[A-Za-z0-9_.-]+)"',code)
            for key in keys:
                self.assertIn(key,catalog,(path.name,key))
                for language in ['en','zh-Hans']:
                    self.assertTrue(catalog[key]['localizations'][language]['stringUnit']['value'])
    def test_apple_and_live_acceptance_are_not_claimed(self):
        evidence=json.loads(self.read('docs/playkit-screen-verification.json'))
        for key in ['swift_tests','ios_build','ui_tests','device_acceptance','backend_acceptance','visual_accessibility_acceptance']:
            self.assertEqual(evidence[key],'NOT_RUN')
        self.assertGreaterEqual(evidence['authored_core_tests'],43)

if __name__ == '__main__': unittest.main()
