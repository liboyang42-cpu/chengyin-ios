"""Source contracts for the mini event-ops (活动运营) parity. Does not run Swift or native UI."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def text(path):
    return (ROOT / path).read_text()


class ClubOpsEventContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = text('Core/ClubOpsEventPresentation.swift')
        cls.hub = text('App/ClubOpsEventView.swift')
        cls.fields = text('App/ClubOpsEventFormFields.swift')
        cls.views = text('App/ClubGovernanceViews.swift')
        cls.form = text('App/ClubGovernanceCommandForm.swift')
        cls.draft = text('Core/ClubGovernanceFormDraft.swift')
        cls.roster = text('App/ClubRosterBucketContent.swift')
        cls.catalog = json.loads(text('Resources/ClubOpsEvent.xcstrings'))
        cls.localizable = json.loads(text('Resources/Localizable.xcstrings'))['strings']

    def test_section_order_and_permission_rule(self):
        self.assertIn('if canManage && (scope.activityID ?? 0) > 0 { result.append(.occurrence) }', self.core)
        self.assertIn('if canCheckin { result.append(.roster) }', self.core)
        self.assertIn('if canManage { result += [.series, .recurrence, .capacity] }', self.core)
        self.assertIn('canCheckin = (scope.activityID ?? 0) > 0 && permissions?.allows("club:event:checkin", scope: scope) == true', self.core)
        self.assertIn('case occurrence, roster, series, recurrence, capacity', self.core)

    def test_hub_is_reachable_from_workspace_and_event_view(self):
        access = self.views.split('Section("club.gov.workspace") {', 1)[1].split('Section("club.gov.delegatedEvents")', 1)[0]
        self.assertIn('if read == .series, ClubOpsEventAccess(permissions: snapshot.permissions, scope: scope).permitted', access)
        self.assertIn('ClubOpsEventView(scope: scope, identity: identity, access: access, coordinator: coordinator)', access)
        event = self.views.split('struct ClubGovernanceEventView: View {', 1)[1].split('/// Route/play display', 1)[0]
        self.assertIn('ClubOpsEventView(scope: scope,', event)
        self.assertIn('"clubOpsEvent.entry.event"', event)

    def test_hub_only_composes_existing_reads_and_never_writes(self):
        self.assertIn('ClubGovernanceReadView(operation: read, scope: target', self.hub)
        self.assertIn('try await access.read(.access, scope: accessScope, options: [:], check: check)', self.hub)
        self.assertIn('.navigationTitle(Text("clubOpsEvent.title", tableName: "ClubOpsEvent"))', self.hub)
        for token in ['.send(', 'coordinator.confirm', 'coordinator.prepare', 'ProductionApproval', 'allowsOfflineWrites', 'URLSession']:
            self.assertNotIn(token, self.hub)
            self.assertNotIn(token, self.core)

    def test_attendance_arrived_is_derived_not_a_default_toggle(self):
        self.assertIn('case .correctAttendance: anchorKeys = ["expectedVersion", "arrived"]', self.draft)
        self.assertNotIn('flags["arrived"] = false', self.draft)
        self.assertIn('"arrived": .bool(target.arrived)', self.roster)
        self.assertIn('case .registered, .noShow: return true; case .arrived: return false; case .waitlist: return nil', self.core)
        self.assertIn('review.command.fields["arrived"] == expected.route.seed["arrived"]', text('App/ClubAttendanceCorrectionReturn.swift'))
        self.assertIn('ClubOpsEventFormCopy.title(route)', self.form)
        self.assertIn('"clubOpsEvent.roster.title \\(roster.rosterTotal)"', self.roster)
        self.assertIn('ClubOpsEventClock.correctionRange(start: roster.correctionStart, end: roster.correctionEnd', self.roster)
        self.assertIn('"clubOpsEvent.roster.closed"', self.roster)

    def test_cancel_keeps_review_confirm_and_adds_second_confirmation(self):
        self.assertIn('if route.operation == .cancelOccurrence { cancelConfirmReview = review } else { Task { await confirm(review) } }', self.form)
        self.assertIn('guard let pending = cancelConfirmReview, pending.id == review?.id', self.form)
        self.assertIn('ClubOpsEventCancellationReceipt(receipt: readback.receipt, confirmed: occurrenceCancellationReturn.confirmed', self.views)
        self.assertIn('ClubOpsEventOccurrenceStatusRows(value: value, activityID: scope.activityID)', self.views)
        self.assertIn('guard cancelled, publish == 0 else { return nil }', self.core)
        self.assertIn('guard !cancelled, publish == 1 else { return nil }', self.core)

    def test_series_defaults_edit_lock_and_owner_default_lead(self):
        self.assertIn('flags["waitlistEnabled"] = seed["waitlistEnabled"]?.bool ?? (operation == .createSeries)', self.draft)
        self.assertIn('"occurrenceCount": operation == .createSeries ? "4" : "1"', self.draft)
        self.assertIn('if operation == .createSeries, key == "defaultLeadMemberId", value == Self.ownerDefaultLead { values[key] = .null; continue }', self.draft)
        commands = text('Core/ClubGovernanceCommands.swift')
        self.assertIn('!(operation == .createSeries && key == "defaultLeadMemberId" && result[key] == .null)', commands)
        self.assertIn('(5...1440).contains(result["offerMinutes"]?.int ?? 0)', commands)
        self.assertIn('result["capacity"] == .null || (1...10000).contains(result["capacity"]?.int ?? 0)', commands)
        self.assertIn('$0["isOwner"] == .bool(true)', text('Core/ClubGovernanceCoordinator.swift'))
        self.assertIn('ownerDefault ? (row["memberId"].int ?? 0) > 0 && row["isOwner"] == .bool(true)', text('Core/ClubGovernanceService.swift'))
        self.assertIn('(!isSeries || key != "capacity") && (route.operation != .updateSeries || key != "defaultLeadMemberId")', self.form)
        self.assertIn('private var showsOfferWindow: Bool { route.operation == .createSeries && draft.flags["waitlistEnabled"] == true }', self.form)
        self.assertIn('if operation == .updateSeries {', self.fields)

    def test_every_table_key_is_bilingual(self):
        strings = self.catalog['strings']
        self.assertEqual(self.catalog['sourceLanguage'], 'en')
        used = set()
        for path in ['App/ClubOpsEventView.swift', 'App/ClubOpsEventFormFields.swift', 'App/ClubRosterBucketContent.swift',
                     'App/ClubSeriesOccurrenceBrowser.swift', 'App/ClubSeriesLeadPicker.swift', 'App/ClubGovernanceCommandForm.swift',
                     'App/ClubSeriesScheduleEditor.swift', 'App/ClubGovernanceViews.swift']:
            source = re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', '', text(path))
            for key in re.findall(r'"(clubOpsEvent\.[A-Za-z.]+(?: \\\([^"]*)?)"', source):
                if key.endswith('.'):
                    continue
                used.add(re.sub(r'\\\([^)]*\)', '%', key))
        for raw in ['refund.notRequired', 'refund.manualReview', 'refund.acceptedWithManualReview', 'refund.accepted',
                    'refund.pending', 'notify.notRequired', 'notify.queued']:
            used.add('clubOpsEvent.' + raw)
        normalized = {re.sub(r'%(?:\d\$)?(?:lld|@)', '%', key): key for key in strings}
        for key in used:
            self.assertIn(key, normalized)
        for key, value in strings.items():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'], key)

    def test_mini_copy_is_exact(self):
        zh = {k: v['localizations']['zh-Hans']['stringUnit']['value'] for k, v in self.catalog['strings'].items()}
        self.assertEqual(zh['clubOpsEvent.title'], '活动运营')
        self.assertEqual(zh['clubOpsEvent.denied.title'], '你没有活动运营的权限')
        self.assertEqual(zh['clubOpsEvent.denied.body'], '场次编排、签到与出勤更正需要「活动运营」或「本场核销」权限。')
        self.assertEqual(zh['clubOpsEvent.cancel.confirmBody'], '会下架本场、处理退款并终止候补。已核销的部分不退。')
        self.assertEqual(zh['clubOpsEvent.roster.window %@'], '签到更正仅限活动开始至结束后 48 小时，本场可更正时段：%@')
        self.assertEqual(zh['clubOpsEvent.refund.acceptedWithManualReview'], '退款任务已受理，部分需人工跟进')
        self.assertEqual(zh['clubOpsEvent.occurrences.signupsLocked %lld'], '%lld 人已报名 · 不可编辑')
        labels = {'club.gov.field.recurrenceType': '重复方式', 'club.gov.field.occurrenceCount': '场次数',
                  'club.gov.field.customDates': '日期清单', 'club.gov.field.startTime': '集合时刻',
                  'club.gov.field.capacity': '容量（可选）', 'club.gov.field.defaultLeadMemberId': '默认负责人',
                  'club.gov.field.waitlistEnabled': '满员后开启候补', 'club.gov.action.updateSeries': '编辑未来场次'}
        fragment = json.loads(text('Resources/ClubGovernanceLocalizations.fragment.json'))['strings']
        for key, value in labels.items():
            self.assertEqual(self.localizable[key]['localizations']['zh-Hans']['stringUnit']['value'], value)
            self.assertEqual(fragment[key], self.localizable[key])

    def test_new_sources_are_registered(self):
        project = text('Questify.xcodeproj/project.pbxproj')
        for path in ['App/ClubOpsEventView.swift', 'App/ClubOpsEventFormFields.swift', 'Core/ClubOpsEventPresentation.swift',
                     'Resources/ClubOpsEvent.xcstrings']:
            self.assertIn(path, project)
        self.assertTrue((ROOT / 'Tests/CoreTests/ClubOpsEventPresentationTests.swift').exists())


if __name__ == '__main__':
    unittest.main()


class ClubOpsEventAnchorChecks(unittest.TestCase):
    def test_roster_anchor_cannot_be_replaced_by_a_draft_flag(self):
        draft = (ROOT / 'Core/ClubGovernanceFormDraft.swift').read_text()
        self.assertIn('case .correctAttendance: anchorKeys = ["expectedVersion", "arrived"]', draft)
        self.assertIn('for (key, flag) in flags where anchors[key] == nil {', draft)

    def test_owner_default_lead_reviews_as_owner_not_unknown(self):
        form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        self.assertIn('LabeledContent("club.gov.field.defaultLeadMemberId") { Text("clubOpsEvent.lead.ownerDefault", tableName: "ClubOpsEvent") }', form)
