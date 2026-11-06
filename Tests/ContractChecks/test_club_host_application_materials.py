from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubHostApplicationMaterialsContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/ClubHostApplicationMaterials.swift').read_text()
        self.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()

    def test_normal_existing_host_apply_owns_the_material_model(self):
        self.assertIn('@StateObject private var hostMaterials = ClubHostApplicationMaterials()', self.form)
        self.assertIn('if route.operation == .hostApply {\n                    ClubHostApplicationMaterialsRows(', self.form)
        self.assertIn('(route.operation != .hostApply || key != "certImages")', self.form)

    def test_only_host_pending_materials_gate_review_and_prepare(self):
        self.assertIn('|| !hostMaterialsReady || !notificationAudienceReady).accessibilityIdentifier("club.gov.prepare")', self.form)
        self.assertIn('guard roleAssignmentReady && seriesScheduleReady && seriesLeadReady && hostMaterialsReady else', self.form)
        self.assertIn('route.operation != .hostApply || (hostMaterials.isCurrent(hostMaterialsContext, allowed: { hostMaterialsAllowed }) && !hostMaterials.blocksSubmission)', self.form)

    def test_no_uploader_request_or_fabricated_reference(self):
        for term in ['URLRequest(', 'HTTPTransport', 'RetainedImageHTTPUploader(', '.upload(', 'requestId', 'certImages']:
            self.assertNotIn(term, self.source)
        self.assertNotIn('draft.text["certImages"] =', self.form)
        self.assertIn('var blocksSubmission: Bool { !items.isEmpty || presentation != nil }', self.source)

    def test_reuses_selected_item_native_picker_and_existing_limits(self):
        self.assertIn('RetainedNativeImagePicker(enabled: true', self.source)
        self.assertIn('picker.selectBatch(limit: self.limit, byteLimit: self.byteLimit)', self.source)
        self.assertIn('static let maximumCount = 9', self.source)
        self.assertIn('static let maximumBytes = MerchantGalleryBatchLimits.maximumRetainedBytes', self.source)
        native = (ROOT / 'App/RetainedNativeImagePicker.swift').read_text()
        self.assertIn('RetainedImageSanitizer.sanitize', native)
        self.assertIn('RetainedSelectedImage.maximumInputBytes', native)

    def test_atomic_count_bytes_and_duplicate_rejection(self):
        self.assertIn('images.count <= remaining, Set(ids).count == ids.count', self.source)
        self.assertIn('images.reduce(0, { $0 + $1.jpeg.count }) <= remainingBytes', self.source)
        self.assertLess(self.source.index('images.count <= remaining'), self.source.index('items.append(contentsOf:'))

    def test_cancel_leaves_existing_selection(self):
        self.assertIn('guard let images else { close(value); return false }', self.source)
        close = self.source.split('    func close(', 1)[1].split('    @discardableResult', 1)[0]
        self.assertNotIn('items =', close)
        self.assertIn('presentation?.id == value.id, attachment == value.attachment', close)

    def test_picker_and_preview_have_concrete_stable_owner(self):
        self.assertIn('if let value = hostMaterials.presentation', self.form)
        self.assertIn('allowed: { hostMaterialsAllowed }, changed: { dirty = true }).id(value.id)', self.form)
        self.assertIn('.sheet(item: model.binding(value, allowed: allowed)', self.source)
        self.assertIn('self.current(value, allowed: allowed) ? value : nil', self.source)
        self.assertIn('self.presentation?.id == value.id', self.source)

    def test_rows_never_own_sheet_or_leave_lifecycle(self):
        rows = self.source.split('struct ClubHostApplicationMaterialsRows', 1)[1].split('struct ClubHostApplicationMaterialsOwner', 1)[0]
        for term in ['@State', '.sheet(', '.onDisappear', 'model.retire(']: self.assertNotIn(term, rows)
        self.assertIn('.buttonStyle(.borderless).accessibilityElement(children: .contain)', rows)

    def test_actual_departure_is_distinct_from_modal_cover(self):
        self.assertIn('if let attachment = hostMaterials.attachment', self.form)
        self.assertIn('hostMaterials.depart(context, attachment: attachment)', self.form)
        self.assertIn('.frame(width: 0, height: 0).id(attachment)', self.form)
        self.assertIn('controller.isBeingDismissed || controller.isMovingFromParent', self.source)
        self.assertIn('else if wasAttached { leave() }', self.source)
        self.assertNotIn('.onDisappear { hostMaterials.retire()', self.form)

    def test_context_binds_form_identity_reader_authorization_namespace(self):
        for term in ['formID: route.id', 'identity == access.identity', 'hostMaterials.context == hostMaterialsContext', 'scenePhase == .active']:
            self.assertIn(term, self.form)
        for term in ['authorizationGeneration: access.authorizationGeneration', 'ObjectIdentifier(access)', 'namespace: access.storageNamespace']:
            self.assertIn(term, self.source)

    def test_late_callback_requires_live_presentation(self):
        self.assertIn('guard current(value, allowed: allowed), value.kind == .picker else', self.source)
        self.assertIn('guard !Task.isCancelled, self.isCurrent() else', self.source)
        self.assertIn('presentation == value && attachment == value.attachment', self.source)
        self.assertIn('if let expectedAttachment, attachment != expectedAttachment { return }', self.source)

    def test_table_binding_matches_all_nine_localized_keys(self):
        table = json.loads((ROOT / 'Resources/ClubHostApplicationMaterials.xcstrings').read_text())['strings']
        self.assertEqual(len(table), 9)
        self.assertTrue(all(set(item['localizations']) == {'en', 'zh-Hans'} for item in table.values()))
        for line in self.source.splitlines():
            if 'Text("club.materials.' in line: self.assertIn('tableName: "ClubHostApplicationMaterials"', line)
        self.assertIn('club.materials.preview %lld', table)

    def test_upload_boundary_and_optional_empty_are_explicit(self):
        table = json.loads((ROOT / 'Resources/ClubHostApplicationMaterials.xcstrings').read_text())['strings']
        self.assertIn('not available', table['club.materials.unavailable']['localizations']['en']['stringUnit']['value'])
        self.assertIn('尚未上传', table['club.materials.pending']['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('选填', table['club.materials.optional']['localizations']['zh-Hans']['stringUnit']['value'])

    def test_no_privilege_or_retained_core_destination_added(self):
        core = (ROOT / 'Core/RetainedImageContracts.swift').read_text()
        self.assertNotIn('case hostApplication', core)
        self.assertNotIn('approvedOrigins', self.source)
        self.assertNotIn('canDispatch', self.source)

    def test_authored_negative_controls_cover_scope_and_old_callbacks(self):
        tests = (ROOT / 'Tests/AppUnitTests/ClubHostApplicationMaterialsTests.swift').read_text()
        for name in ['testOldNilBindingCannotCloseReopenedPicker', 'testIdentityChangeRejectsLateSelectionBeforeLifecycleCallback',
                     'testOldDepartureCannotRetireNewAttachment', 'testBackgroundRetirementDropsBytesAndBlocksLateCallback',
                     'testLocalMaterialNeverCreatesServerReferenceOrServiceCall']:
            self.assertIn('func ' + name + '(', tests)
        self.assertEqual(len(re.findall(r'func (test\w+)\(', tests)), 24)

    def test_hidden_scene_or_context_cannot_reactivate_departed_form(self):
        self.assertIn('guard hostVisible else { return }', self.source)
        self.assertIn('func hide() { hostVisible = false }', self.source)
        self.assertIn('hostVisible = false; retire(expected, attachment: expectedAttachment)', self.source)
        self.assertIn('.onAppear { activateHostMaterials(appearing: true) }', self.form)
        self.assertIn('.onDisappear { hostMaterials.hide() }', self.form)
        self.assertIn('hostMaterialAttachment != nil && hostMaterials.attachment == hostMaterialAttachment', self.form)
        self.assertIn('(hostVisible || presentation != nil)', self.source)

if __name__ == '__main__': unittest.main()
