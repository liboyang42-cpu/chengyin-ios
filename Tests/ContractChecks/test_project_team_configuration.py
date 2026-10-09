"""Bounded source contracts; these do not execute Swift or render a UI."""
from pathlib import Path
import json,re,unittest
R=Path(__file__).resolve().parents[2]
C=(R/'Core/ProjectTeamConfiguration.swift').read_text()
W=(R/'Core/ProjectEditContract.swift').read_text()
U=(R/'App/ProjectTeamConfigurationEditor.swift').read_text()
H=(R/'App/ProjectEditView.swift').read_text()
CT=(R/'Tests/CoreTests/ProjectTeamConfigurationTests.swift').read_text()
AT=(R/'Tests/AppUnitTests/ProjectTeamConfigurationPresentationTests.swift').read_text()
class TeamConfigurationContracts(unittest.TestCase):
    def test_readback_and_payload_share_exact_two_carryover_fields(self):
        self.assertIn('fields = ["teamMode", "teamMaxMembers"]',C)
        self.assertIn('ProjectEditStoryContract.topicFields + ProjectTeamConfiguration.fields',W)
        self.assertIn('for key in topicCarryOver { if let value = topic[key] { d.preserved[key] = value } }',W)
        self.assertIn('for key in topicCarryOver { if let value = draft.preserved[key] { payload[key] = value } }',W)
    def test_whitelist_returns_before_new_full_guard(self):
        self.assertLess(W.index('if scope == .whitelist'),W.index('guard ProjectTeamConfiguration.canSubmit'))
        self.assertIn('ProjectTeamConfiguration.canSubmit(draft, baseline: baseline)',W)
    def test_source_modes_and_global_bounds_are_exact(self):
        self.assertIn('case off = 0, atRegistration = 1, afterRegistration = 2',C)
        self.assertIn('[("teamMode", 0...2), ("teamMaxMembers", 2...4)]',C)
        self.assertIn('guard let integer = raw.integer, bounds.contains(integer)',C)
    def test_missing_null_and_unknown_are_not_coerced_at_submission(self):
        validation=C.split('public static func canSubmit',1)[1].split('public mutating func',1)[0]
        self.assertIn('raw != .null',validation);self.assertNotIn('??',validation)
        self.assertNotRegex(validation, r'draft\.preserved\[key\]\s*=(?!=)')
    def test_old_local_envelope_cannot_erase_fresh_baseline_fields(self):
        self.assertIn('for key in fields where baseline.draft.preserved[key] != nil',C)
        self.assertIn('if draft.preserved[key] == nil { return false }',C)
        self.assertIn('OldLocalEnvelopeCannotEraseFreshSavedTeamSettings',CT)
    def test_explicit_changes_only_touch_two_fields_and_noop_stays_raw(self):
        self.assertIn('if mode != originalMode',C);self.assertIn('if maximum != originalMaximum',C)
        self.assertEqual(C.count('result.preserved['),2)
        self.assertNotIn('removeValue',C)
    def test_apply_is_city_and_exact_source_bound(self):
        self.assertIn('draft.product == .city',C)
        self.assertIn('ProjectEditPendingMaterials.exactData(draft) == sourceBytes',C)
        self.assertIn('guard !readOnly',C)
    def test_one_existing_host_entry_keeps_preview(self):
        self.assertEqual(H.count('ProjectTeamConfigurationEntry(model: model)'),1)
        self.assertEqual(H.count('ProjectDraftStoryPreviewEntry(model: model)'),1)
        self.assertIn('ProjectClubLeadFields(model: model)',H)
    def test_full_owner_lease_baseline_and_exact_draft_fences(self):
        for x in ['model.fullEdit && model.draft.product == .city','capture.controller == identity','capture.generation == generation','model.isCurrentStarterLease(capture.lease)','model.draftMutationRevision == capture.revision','ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes','== capture.baselineBytes']:
            self.assertIn(x,U)
    def test_capture_retires_on_departure_change_and_reopen(self):
        for x in ['guard presentation == nil, current(capture)','presentation?.id == original.id','generation += 1','.onDisappear { controller.retire() }','.onDisappear { controller.close(original) }','model.draftMutationRevision','model.editorIncarnation','model.coordinator.session']:
            self.assertIn(x,U)
    def test_only_explicit_apply_assigns_draft_and_noop_avoids_setter(self):
        self.assertEqual(U.count('model.draft = next'),1)
        self.assertIn('if ProjectEditPendingMaterials.exactData(next) != original.capture.bytes',U)
        self.assertIn('let next = try? buffer.applying(to: model.draft)',U)
    def test_no_membership_permission_route_storage_or_network_actions(self):
        for x in ['URLSession','URLRequest','Task {','.submit(','.saveLocal(','.register(','AppSession','ProjectEditHTTPService','/api/','ticket.teamSize']:
            self.assertNotIn(x,C+U)
    def test_picker_stages_and_readonly_can_only_cancel(self):
        self.assertIn('controller.selectMode($0, in: original)',U)
        self.assertIn('controller.selectMaximum($0, in: original)',U)
        self.assertIn('controller.buffer?.readOnly != false',U)
        self.assertIn('if buffer.readOnly { text("unsupported") }',U)
    def test_actual_core_regressions_target_payload_and_readback(self):
        for x in ['UnrelatedNameEditRetainsExistingEnabledTeam','BothProductsRetainKnown','MissingNullAndMixedShapes','UnknownValuesTypesAndOutOfBounds','WhitelistPayloadRemainsTheExactOldShape','PreparedReviewFreezesBothSettings']:
            self.assertIn(x,CT)
        self.assertIn('ProjectEditContract.decodeEditDetail',CT);self.assertIn('ProjectEditContract.payload',CT)
    def test_hosted_regressions_use_actual_controller_and_lifetime(self):
        for x in ['ProjectTeamConfigurationController','NoOpApplyPreservesPreparedReview','QueuedOpenAfterDeparture','AccountEpochLogoutRestoreABAAndLeave','OldCloseAndApplyCannotAffectNew','UnsupportedWireValueIsReadOnly']:
            self.assertIn(x,AT)
    def test_named_catalog_has_all_bilingual_labels(self):
        strings=json.loads((R/'Resources/ProjectTeamConfiguration.xcstrings').read_text())['strings']
        expected={'projectTeamConfiguration.'+x for x in re.findall(r'text\("([A-Za-z]+)"\)',U)}
        self.assertFalse(expected-set(strings));self.assertEqual(len(strings),13)
        for row in strings.values():
            self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
            for v in row['localizations'].values():self.assertTrue(v['stringUnit']['value'].strip())
if __name__=='__main__':unittest.main()
