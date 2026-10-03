"""Finite P1/S1/L1 source regressions only. Apple compilation/runtime are separate gates."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def source(path): return (ROOT / path).read_text()

class NativePresentationReuseChecks(unittest.TestCase):
    def test_media_keeps_single_full_screen_owner_and_no_container_id(self):
        text = source('App/NativeMediaGallery.swift')
        self.assertEqual(text.count('.fullScreenCover('), 1)
        self.assertNotIn('.sheet(', text)
        self.assertNotIn('accessibilityIdentifier("media.gallery.fullscreen")', text)
        for key in ['media.gallery.close', 'media.gallery.previous', 'media.gallery.next', 'media.gallery.position']:
            self.assertIn('accessibilityIdentifier("' + key + '")', text)

    def test_media_failure_cannot_return_to_infinite_decode_loading(self):
        text = source('App/NativeMediaGallery.swift')
        self.assertIn('guard let decoded = UIImage(data: clean.jpeg) else { throw RetainedImageFailure.invalid }', text)
        self.assertIn('catch { if !Task.isCancelled { failed = true } }', text)
        self.assertIn('Button("action.retry") { revision += 1 }', text)
        self.assertIn('else if !reader.enabled', text)
        self.assertNotIn('AsyncImage', text)

    def test_media_maximum_text_and_scope_focus_invalidation(self):
        text = source('App/NativeMediaGallery.swift')
        self.assertIn('dynamicTypeSize.isAccessibilitySize', text)
        self.assertIn('returnFocusIndex = nil; focusedImageIndex = nil; selection = nil', text)
        self.assertIn('.onChange(of: scope)', text)
        self.assertIn('.onChange(of: sources)', text)
        self.assertIn('@AccessibilityFocusState', text)
        self.assertIn('UIAccessibility.isReduceMotionEnabled', text)

    def test_participation_nested_destinations_keep_current_stack(self):
        text = source('App/PlayerJourneyViews.swift')
        for destination in ['SessionNativeVerificationView()', 'SessionMemberTemplateDetailView(id: id)', 'ParticipationSupportView()']:
            self.assertIn('NavigationLink { ' + destination + ' }', text)
        self.assertIn('.presentationDetents([.large])', text)
        self.assertIn('OrderLifecycleView(id: id, coordinator: lifecycle).id(lifecycle.scope)', text)
        self.assertNotIn('open(.support)', text)
        self.assertNotIn('open(.verification)', text)
        self.assertNotIn('open(.memberTemplate(id))', text)

    def test_pending_root_route_is_scope_bound_and_consumed_once(self):
        text = source('App/PlayerJourneyViews.swift')
        self.assertIn('let pending = nextRoute; nextRoute = nil', text)
        self.assertIn('guard selected.scope == reader.scope, reader.isAuthenticated else { resetPresentation(); return }', text)
        self.assertIn('PendingRoute(target: target, scope: selected.scope)', text)
        self.assertIn('guard pending.scope == reader.scope, reader.isAuthenticated else { return }', text)
        self.assertIn('nextRoute = nil; returnFocusID = nil; focusedParticipationID = nil; selected = nil', text)
        self.assertIn('.onChange(of: reader.scope)', text)
        self.assertIn('route = nil; login = false', text)

    def test_camera_and_scanner_remain_full_screen_and_cancelable(self):
        for filename, binding in [('RoamStampCameraView.swift', 'showingCamera'), ('RoamPosterScanView.swift', 'showingScanner')]:
            text = source('App/' + filename)
            self.assertIn('.fullScreenCover(isPresented: $' + binding + ', onDismiss:', text)
            self.assertNotIn('.sheet(', text)
            self.assertIn('@AccessibilityFocusState', text)
            self.assertIn('scenePhase == .active, cameraEnabled', text)
            self.assertIn('.onChange(of: cameraEnabled)', text)
        stamp = source('App/RoamStampCameraView.swift')
        callback = stamp.split('RoamNativeStampCamera { result in', 1)[1].split('switch result', 1)[0]
        self.assertLess(callback.index('guard ticket == captureGeneration'), callback.index('showingCamera = false'))
        self.assertIn('imagePickerControllerDidCancel', stamp)
        self.assertIn('Button("action.cancel")', source('App/NativeQRScanner.swift'))

    def test_poster_callback_is_generation_gated_and_background_clears_review(self):
        text = source('App/RoamPosterScanView.swift')
        self.assertIn('guard ticket == scanGeneration, scenePhase == .active,', text)
        self.assertIn('cameraEnabled, purposeAccepted, coordinator.available else { return }', text)
        self.assertIn('phase == .background { invalidateScan() }', text)
        self.assertIn('if shouldCancel { coordinator?.cancel() }', text)
        self.assertIn('work?.cancel(); work = nil', text)
        self.assertNotIn('requestAccess', text)

    def test_only_busy_media_phases_spin_and_receipt_semantics_remain(self):
        stamp = source('App/RoamStampCameraView.swift')
        poster = source('App/RoamPosterScanView.swift')
        self.assertIn('coordinator?.phase == .uploading || coordinator?.phase == .creating', stamp)
        self.assertIn('phase == .locating || phase == .preflighting || phase == .submitting', poster)
        for text in [stamp, poster]:
            self.assertIn('if isBusy { ProgressView(', text)
            self.assertIn('case .unknown:', text)
            self.assertIn('case .unavailable:', text)
            self.assertIn('case .failed:', text)
        self.assertIn('.disabled(!coordinator.canUpload)', stamp)
        self.assertIn('.disabled(!coordinator.canCreate)', stamp)

    def test_settings_still_has_one_language_owner_and_read_only_region(self):
        text = source('App/SettingsView.swift')
        self.assertEqual(text.count('@AppStorage("preferences.language")'), 1)
        self.assertIn('Form {', text)
        self.assertIn('LabeledContent { Text(verbatim:RegionalLaunchConfiguration.market?', text)
        self.assertNotIn('Picker("region.market"', text)
        self.assertNotIn('AppLanguage', source('Core/SettingsSourceLegalCatalog.swift'))
        self.assertIn('SettingsAttributionsSection()', source('App/SettingsSupportSections.swift'))
        self.assertIn('case .loaded(.missing(let reason)):', source('App/SettingsLegalDocumentView.swift'))

    def test_uses_existing_bilingual_strings_and_no_new_dependency(self):
        strings = json.loads(source('Resources/Localizable.xcstrings'))['strings']
        fragment = json.loads(source('Resources/NativePresentationReuseLocalizations.fragment.json'))['strings']
        for key, entry in fragment.items():
            self.assertEqual(strings[key], entry)
        keys = ['media.destination.previous', 'media.destination.next', 'media.destination.failed', 'media.destination.unavailable', 'action.retry', 'action.close']
        keys += ['media.stamp.phase.' + key for key in ['uploading', 'creating', 'failed', 'unknown', 'unavailable']]
        keys += ['media.poster.phase.' + key for key in ['locating', 'preflighting', 'submitting', 'unknown', 'unavailable', 'failed']]
        for key in keys:
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(strings[key]['localizations'][locale]['stringUnit']['value'])
        for filename in ['Package.swift', 'App/PlayerJourneyViews.swift', 'App/NativeMediaGallery.swift', 'App/RoamStampCameraView.swift', 'App/RoamPosterScanView.swift']:
            text = source(filename)
            for forbidden in ['Shimmer', 'ActivityKit', 'startUpdatingLocation', 'beginBackgroundTask']:
                self.assertNotIn(forbidden, text)

    def test_independent_fixture_uses_real_views_and_no_external_calls(self):
        text = source('App/NativePresentationFixtureSupport.swift')
        self.assertTrue(text.startswith('#if DEBUG'))
        for view in ['NativeMediaGalleryEntry(', 'NativeMediaGallery(', 'ParticipationHistoryView(', 'RoamStampCameraView()', 'RoamPosterScanView(node: node)']:
            self.assertIn(view, text)
        for forbidden in ['URLSession', 'requestAccess', 'Task.sleep', 'DispatchQueue', 'asyncAfter']:
            self.assertNotIn(forbidden, text)
        self.assertIn('images.onRead = { mediaScope = UUID(); expired = true }', text)

    def test_authored_ui_waits_for_state_and_restores_navigation(self):
        text = source('Tests/AppUITests/NativePresentationPatternFlowTests.swift') + source('Tests/AppUITests/NativeSettingsReuseFlowTests.swift')
        self.assertIn('XCTNSPredicateExpectation', text)
        self.assertIn('label == \'2\'', text)
        self.assertNotRegex(text, r'\b(?:sleep|usleep)\s*\(')
        self.assertNotIn('Thread.sleep', text)
        self.assertIn('testFollowSystemPersistsAcrossRelaunchWithoutChangingUSMarket', text)
        self.assertIn('testParticipationPlayWaitsForSheetDismissal', text)
        self.assertIn('testMaximumTextLegalMissingStateBackAndReopenInBothLanguages', text)

    def test_scope_callback_cannot_erase_a_fast_accepted_participation_read(self):
        text = source('App/PlayerJourneyViews.swift').split('@MainActor struct ParticipationHistoryView: View {', 1)[1].split('private struct ParticipationRow: View {', 1)[0]
        self.assertIn('else if let rows, rowsScope == reader.scope', text)
        self.assertIn('rows = values; rowsScope = scope', text)
        self.assertIn('.onChange(of: reader.scope) { _, _ in resetPresentation() }', text)
        self.assertNotIn('.onChange(of: reader.scope) { _, _ in resetPresentation(); rows = nil }', text)
        load = text.split('private func load() async {', 1)[1]
        self.assertLess(load.index('scope == reader.scope, !Task.isCancelled'), load.index('rows = values; rowsScope = scope'))
        ui = source('Tests/AppUITests/NativePresentationPatternFlowTests.swift')
        self.assertIn('testParticipationFailureRetriesAndScopeExpiryDismisses', ui)
        self.assertIn('app.terminate(); launch("journeyScope")', ui)

    def test_completed_history_does_not_use_participation_scope_state(self):
        text = source('App/PlayerJourneyViews.swift').split('@MainActor struct CompletedPlayHistoryView: View {', 1)[1].split('private struct PlayerJourneyCount: View {', 1)[0]
        self.assertNotIn('rowsScope', text)

    def test_settings_legal_reveals_lazy_form_rows_before_asserting_existence(self):
        source_text = source('Tests/AppUITests/NativeSettingsReuseFlowTests.swift')
        helper = source_text.split('private func openLegal(', 1)[1].split('\n    func test', 1)[0]
        self.assertIn('let form = app.collectionViews.firstMatch', helper)
        self.assertIn('form.waitForExistence(timeout: 10)', helper)
        self.assertIn('app.navigationBars[rootTitle].exists', helper)
        self.assertIn('let button = form.buttons["settingsNative.openLegal.\\(type)"]', helper)
        self.assertIn('for _ in 0..<12 { if button.exists && button.isHittable { break }; form.swipeUp() }', helper)
        self.assertLess(helper.index('form.swipeUp()'), helper.index('XCTAssertTrue(button.exists'))
        self.assertLess(helper.index('XCTAssertTrue(button.exists'), helper.index('button.tap()'))
        self.assertLess(helper.index('XCTAssertTrue(button.isHittable'), helper.index('button.tap()'))
        self.assertNotIn('button.waitForExistence', helper)
        self.assertNotIn('app.swipeUp()', helper)

    def test_maximum_settings_legal_flow_keeps_bilingual_missing_and_back_checks(self):
        text = source('Tests/AppUITests/NativeSettingsReuseFlowTests.swift')
        case = text.split('func testMaximumTextLegalMissingStateBackAndReopenInBothLanguages()', 1)[1]
        for token in ['for language in ["en", "zh-Hans"]', 'language == "en" ? "Settings" : "设置"',
                      '"--uitesting-max-text"', 'dynamicTypeSize: "accessibility5"',
                      'XCTAssertFalse(app.staticTexts["settingsNative.legal.loading"].exists)',
                      'XCTAssertFalse(app.buttons["Accept"].exists)', 'XCTAssertFalse(app.buttons["同意"].exists)',
                      'XCTAssertFalse(app.staticTexts["settingsNative.legal.version"].exists)']:
            self.assertIn(token, case)
        agreement = case.index('openLegal("user_agreement", rootTitle: rootTitle)')
        back = case.index('app.navigationBars.buttons.firstMatch.tap()')
        privacy = case.index('openLegal("privacy_policy", rootTitle: rootTitle)')
        self.assertLess(agreement, back)
        self.assertLess(back, privacy)
        self.assertEqual(case.count('app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 10)'), 2)
        self.assertNotIn('XCTSkip', case)
