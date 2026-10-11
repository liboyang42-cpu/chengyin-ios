"""Focused source contracts only. These checks do not execute Swift or Photos."""
from pathlib import Path
import json
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RoamSharePhotoSaveSourceTests(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/RoamHistoryShareView.swift').read_text()
        self.model = (ROOT / 'App/RoamSharePhotoSaveModel.swift').read_text()
        self.state = (ROOT / 'Core/RoamSharePhotoSaveState.swift').read_text()

    def test_only_prepared_image_enters_direct_save_and_share(self):
        self.assertRegex(self.view, r'if let image, renderedRecord == record, renderedIncludeRoute == includeRoute,\s+renderedOwner == RoamHistoryLiveOwner\(reader: reader\)')
        self.assertIn('photoSaveControls(image)', self.view)
        self.assertIn('photoSave.save(image, selection: selection)', self.view)
        self.assertIn('ShareLink(item: Image(uiImage: image)', self.view)

    def test_route_privacy_projection_is_still_used_for_preview_and_render(self):
        self.assertIn('ImageRenderer(content: card.frame', self.view)
        self.assertIn('RoamShareRoutePrivacy.sketch(for: record)', self.view)
        self.assertIn('if includeRoute { privateRoute }', self.view)
        self.assertIn('@State private var includeRoute = false', self.view)
        self.assertNotIn('record.pois', self.view)
        self.assertNotIn('record.track.enumerated()', self.view)

    def test_source_rechecks_exact_owner_and_complete_record(self):
        self.assertIn('presentationOwner == RoamHistoryLiveOwner(reader: reader)', self.view)
        self.assertIn('presentationOwner.isAuthorized', self.view)
        self.assertIn('(try? reader.history().first { $0.ts == record.ts }) == record', self.view)
        self.assertIn('selection.includeRoute == includeRoute', self.view)
        self.assertIn('renderedOwner == presentationOwner', self.view)
        self.assertIn('RoamHistoryShareView(record: record, reader: reader)', (ROOT / 'App/RoamHistoryViews.swift').read_text())

    def test_card_context_and_dismissal_cancel_pending_permission(self):
        self.assertIn('photoSave.invalidate()', self.view)
        self.assertIn('.onDisappear { invalidateImage() }', self.view)
        self.assertIn('.onChange(of: record)', self.view)
        self.assertIn('.onChange(of: RoamHistoryLiveOwner(reader: reader))', self.view)
        self.assertIn('onChange(of: includeRoute)', self.view)
        self.assertIn('state.invalidate(); task?.cancel()', self.model)

    def test_permission_is_add_only_and_never_fetches_library(self):
        self.assertIn('PHPhotoLibrary.authorizationStatus(for: .addOnly)', self.model)
        self.assertIn('PHPhotoLibrary.requestAuthorization(for: .addOnly)', self.model)
        self.assertIn('PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)', self.model)
        for forbidden in ['.readWrite', 'fetchAssets', 'PHAsset.fetch', 'location =', 'URLSession', 'CLLocationManager']:
            self.assertNotIn(forbidden, self.model)

    def test_permission_starts_only_inside_explicit_save(self):
        save = self.model.split('    func save(', 1)[1]
        self.assertIn('guard !inFlight else { return }', save)
        self.assertIn('guard isCurrent() else { state.rejectSource(); return }', save)
        self.assertLess(save.index('self.isCurrent(attempt, source: isCurrent)'), save.index('self.writer.authorizationStatus()'))
        self.assertNotIn('.task {', self.view)
        self.assertIn('guard isConfigured else { return .unavailable }', self.model)

    def test_post_permission_and_post_write_results_are_guarded(self):
        save = self.model.split('    func save(', 1)[1]
        request = save.index('await self.writer.requestAuthorization()')
        write = save.index('try await self.writer.add(image)')
        self.assertIn('self.isCurrent(attempt, source: isCurrent)', save[request:write])
        self.assertIn('self.isCurrent(attempt, source: isCurrent)', save[write:save.index('self.state.complete(saved: true')])
        self.assertIn('!Task.isCancelled, state.accepts(attempt)', self.model)
        self.assertIn('guard source() else { state.rejectSource(); return false }', self.model)
        self.assertIn('if state.accepts(attempt) { state.invalidate() }', self.model)

    def test_one_flight_is_retained_until_callback_even_on_invalidation(self):
        self.assertIn('inFlight = true', self.model)
        self.assertIn('defer { self.inFlight = false; self.task = nil }', self.model)
        invalidate = self.model.split('    func invalidate() {', 1)[1]
        self.assertNotIn('inFlight = false', invalidate)
        self.assertIn('phase != .saved', self.state)
        self.assertIn('selection == attempt.selection && generation == attempt.generation', self.state)

    def test_ui_distinguishes_errors_and_never_opens_settings_automatically(self):
        for key in ['photoPermissionDenied', 'photoPermissionRestricted', 'photoSaveUnavailable', 'photoSaveSourceChanged', 'photoSaveFailed', 'retrySavePhotos', 'savedPhotos']:
            self.assertIn('roam.share.' + key, self.view)
        self.assertIn('if phase == .permissionDenied, !photoSave.inFlight', self.view)
        self.assertIn('Button("roam.share.openPhotoSettings")', self.view)
        self.assertNotIn('UIApplication.shared.open', self.model)

    def test_add_only_usage_description_and_localization_fragments_exist(self):
        info = plistlib.loads((ROOT / 'Config/Info.plist').read_bytes())
        self.assertTrue(info['NSPhotoLibraryAddUsageDescription'])
        self.assertNotIn('NSPhotoLibraryUsageDescription', info)
        fragment = json.loads((ROOT / 'tools/roam_share_photo_save_localizations.json').read_text())
        keys = set(re.findall(r'"(roam\.share\.[^"]+)"', self.view))
        for key in keys & fragment.keys():
            self.assertTrue(fragment[key]['en']); self.assertTrue(fragment[key]['zh-Hans'])
        self.assertEqual(len(fragment), 10)
        registration = json.loads((ROOT / 'docs/roam-share-photo-save-registration.json').read_text())
        self.assertIn('NSPhotoLibraryAddUsageDescription', registration['info_plist_catalog_fragment'])
        self.assertFalse(registration['central_files_edited'])

    def test_authored_native_tests_cover_interruptions_and_retry(self):
        native = (ROOT / 'Tests/AppUnitTests/RoamSharePhotoSaveModelTests.swift').read_text()
        for name in ['testDeniedPermissionNeverWritesAndCanRetryWithoutRerendering',
                     'testRepeatedTapsUseOnePermissionRequestAndOneWrite',
                     'testDismissBeforeTaskStartsNeverRequestsPermission',
                     'testDismissDuringPermissionPreventsLaterPhotoWrite',
                     'testAccountOrRecordChangeDuringPermissionPreventsWriteWithoutViewCallback',
                     'testInvalidateDuringSubmittedWriteDropsCompletionAndKeepsFlightLock',
                     'testWriteFailureCanRetryPreparedImage']:
            self.assertIn(name, native)


if __name__ == '__main__':
    unittest.main()
