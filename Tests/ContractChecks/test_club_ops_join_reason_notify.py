"""Source contracts for mini-program pages/club/join-requests + pages/club/notify parity (native run is separate)."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def text(path): return (ROOT / path).read_text()


class ClubOpsJoinNotifyContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.join_core = text('Core/ClubOpsJoinRequestPresentation.swift')
        cls.notify_core = text('Core/ClubOpsNotifyPresentation.swift')
        cls.join_ui = text('App/ClubOpsJoinRequestSections.swift')
        cls.notify_ui = text('App/ClubOpsNotifySections.swift')
        cls.management = text('App/ClubManagementView.swift')
        cls.contracts = text('Core/ClubManagementContracts.swift')
        cls.service = text('Core/ClubManagementService.swift')
        cls.coordinator = text('Core/ClubManagementCoordinator.swift')
        cls.views = text('App/ClubGovernanceViews.swift')
        cls.form = text('App/ClubGovernanceCommandForm.swift')
        cls.audience = text('App/ClubNotificationAudienceView.swift')
        cls.catalog = json.loads(text('Resources/ClubOpsJoinNotify.xcstrings'))
        cls.tests = text('Tests/CoreTests/ClubOpsJoinNotifyTests.swift')

    def zh(self, key): return self.catalog['strings'][key]['localizations']['zh-Hans']['stringUnit']['value']

    def test_sources_catalog_and_tests_are_registered(self):
        project = text('Questify.xcodeproj/project.pbxproj')
        for path in ['Core/ClubOpsJoinRequestPresentation.swift', 'Core/ClubOpsNotifyPresentation.swift', 'App/ClubOpsJoinRequestSections.swift',
                     'App/ClubOpsNotifySections.swift', 'Resources/ClubOpsJoinNotify.xcstrings']:
            self.assertEqual(project.count('"path" = "' + path + '";'), 1, path)
        for core in [self.join_core, self.notify_core]:
            self.assertNotIn('import SwiftUI', core)
            for forbidden in ['URLSession', 'transport', 'UserDefaults']:
                self.assertNotIn(forbidden, core)

    def test_catalog_is_bilingual_prefixed_and_covers_every_key(self):
        self.assertEqual(self.catalog['sourceLanguage'], 'en'); self.assertEqual(self.catalog['version'], '1.0')
        strings = self.catalog['strings']
        for key, entry in strings.items():
            self.assertTrue(key.startswith(('clubOpsJN.', 'clubOpsJoin.', 'clubOpsNotify.')), key)
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][lang]['stringUnit']['value'].strip())
        sources = re.sub(r'\.accessibilityIdentifier\([^)]*\)', '', self.join_ui + self.notify_ui + self.views + self.audience)
        sources = re.sub(r'row\("(clubOpsJN\.[A-Za-z0-9.]+)"', r'Text("\1"', sources)
        used = set(re.findall(r'"(clubOpsJN\.[A-Za-z0-9.]+)(?: \\\(|")', sources))
        for prefix, values in [('clubOpsJN.notify.phase.', ['completed', 'partialFailed', 'delivering']),
                               ('clubOpsJN.notify.issue.', ['title', 'content'])]:
            used.discard(prefix); used.update(prefix + value for value in values)
        literal = {key.split(' ')[0] for key in strings}
        self.assertFalse(used - literal, used - literal)
        self.assertIn('clubOpsJN.join.intro.pending %lld', strings)
        self.assertIn('clubOpsJN.notify.people %lld', strings)

    def test_exact_mini_program_copy(self):
        for key, value in {
            'clubOpsJN.join.intro.pending %lld': '%lld 条待审 · 可直接通过或拒绝',
            'clubOpsJN.join.intro.none': '可直接通过或拒绝',
            'clubOpsJN.join.playerFallback': '城瘾玩家',
            'clubOpsJN.join.approve.body': '通过后，对方将成为正式成员，可查看成员名单并使用成员功能。',
            'clubOpsJN.join.reject.reapply': '对方之后仍可以重新提交申请',
            'clubOpsJN.join.reason.title': '拒绝原因（选填）',
            'clubOpsJN.join.reason.placeholder': '会随未通过通知告诉对方，可不填',
            'clubOpsJN.join.reason.tooLong': '拒绝原因不能超过500字',
            'clubOpsJN.notify.audience.title': '选择受众',
            'clubOpsJN.notify.people %lld': '%lld 人',
            'clubOpsJN.notify.eventDenied': '当前角色没有本场通知权限',
            'clubOpsJN.notify.placeholder.title': '例如：周六集合提醒',
            'clubOpsJN.notify.placeholder.content': '写清集合时间、地点与需要准备的物品',
            'clubOpsJN.notify.issue.title': '标题需为 1–80 字',
            'clubOpsJN.notify.issue.content': '内容需为 1–1000 字',
            'clubOpsJN.notify.preview.empty': '这个分群暂时没有可发送的成员，换一个分群看看。',
            'clubOpsJN.notify.status.title': '投递状态',
            'clubOpsJN.notify.phase.completed': '已投递完成',
            'clubOpsJN.notify.phase.partialFailed': '部分未送达',
            'clubOpsJN.notify.phase.delivering': '投递中',
            'clubOpsJN.notify.total': '总人数', 'clubOpsJN.notify.success': '已送达站内', 'clubOpsJN.notify.pending': '待投递',
            'clubOpsJN.notify.processing': '后台还在投递', 'clubOpsJN.notify.failed': '失败',
            'clubOpsJN.notify.retryOnlyFailed': '只重试失败项',
            'clubOpsJN.notify.sent.completed': '站内通知已发送', 'clubOpsJN.notify.sent.partialFailed': '部分发送失败',
            'clubOpsJN.notify.sent.delivering': '通知已提交，正在投递',
            'clubOpsJN.notify.retried.stillFailed': '仍有失败项', 'clubOpsJN.notify.retried.done': '失败项已重试',
        }.items():
            self.assertEqual(self.zh(key), value, key)

    def test_review_reason_reaches_reject_body_only_through_existing_write(self):
        self.assertIn('public static let maximumUTF16Count = 500', self.join_core)
        self.assertIn('func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, reviewReason: String?,', self.contracts)
        default = self.contracts.split('public extension ClubManagementAccess {', 1)[1]
        self.assertIn('guard reviewReason == nil else { throw ClubActionWriteError.notSent(.invalidRequest) }', default)
        perform = self.service.split('func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, token: String, reviewReason: String? = nil)', 1)[1].split('private func makeRequest', 1)[0]
        self.assertIn('reviewReason == nil || action == .reject', perform)
        self.assertIn('ClubOpsJoinReviewReason.isDispatchable(reviewReason) else { throw APIError.invalidRequest }', perform)
        self.assertIn('if let reviewReason { fields["reviewReason"] = reviewReason }', perform)
        self.assertEqual(perform.count('transport.send('), 1)
        for retry in ['while ', 'for ', 'Task.sleep']:
            self.assertNotIn(retry, perform)
        session = self.service.split('public final class ClubManagementSessionAccess', 1)[1]
        self.assertIn('try await perform(action, clubID: clubID, memberID: memberID, reviewReason: nil, expectedIdentity: expectedIdentity)', session)
        self.assertIn('fresh.allows(action, memberID: memberID)', session)
        self.assertIn('token: session.token, reviewReason: reviewReason)', session)

    def test_confirmation_freezes_reason_and_keeps_review_locks(self):
        self.assertIn('public private(set) var reviewReason: String? = nil', self.coordinator)
        self.assertIn('copy.reviewReason = action == .reject ? ClubOpsJoinReviewReason.normalized(reason) : nil', self.coordinator)
        confirm = self.coordinator.split('public func confirm(', 1)[1].split('public func leaveScreen(', 1)[0]
        self.assertIn('records[key]?.id == confirmation.id, records[key]?.state == .awaitingConfirmation', confirm)
        self.assertLess(confirm.index('records[key]?.state = .submitting'), confirm.index('ClubOpsJoinReviewReason.isDispatchable(confirmation.reviewReason)'))
        self.assertIn('reviewReason: confirmation.reviewReason, expectedIdentity: confirmation.identity', confirm)
        self.assertIn('case .outcomeUnknown(let issue): next = .outcomeUnknown(issue)', confirm)
        m = self.management
        self.assertIn('let pending = item.confirmation.reviewing(reason: reviewReasonDraft)', m)
        self.assertIn('if pending.action == .reject { ClubOpsJoinRejectReasonField(text: $reviewReasonDraft).disabled(state == .submitting || state.preventsNewAction) }', m)
        self.assertIn('.disabled(pending.action == .reject && !ClubOpsJoinReviewReason.isValid(reviewReasonDraft))', m)
        self.assertIn('state = .checking; reviewReasonDraft = ""', m)
        self.assertEqual(m.count('coordinator.confirm(pending)'), 1)
        self.assertLess(m.index('guard reviewOwner.claim(item'), m.index('Task { await confirm(pending, item: item) }'))

    def test_join_list_copy_is_display_only(self):
        self.assertIn('ClubOpsJoinRequestsIntro(count: snapshot.requests.count)', self.management)
        self.assertIn('ClubOpsJoinRequestRowText(request: request)', self.management)
        self.assertIn('else { ClubOpsJoinReviewNotes(action: pending.action) }', self.management)
        for forbidden in ['perform(', 'coordinator', 'access.']:
            self.assertNotIn(forbidden, self.join_ui)
        self.assertIn('"&(?:(lt|gt|amp|quot|#39)|#0*(60|62|38|34|39)|#[xX]0*(3[cCeE]|26|22|27));"', self.join_core)

    def test_notify_wiring_keeps_existing_gates(self):
        self.assertIn('if let rows = try? ClubOpsNotifyPresentation.audienceRows(value) { ClubOpsNotifyAudienceRows(rows: rows) }', self.views)
        self.assertIn('} else if operation == .notificationStatus, let campaign = try? ClubOpsNotifyCampaign(value: value) {', self.views)
        branch = self.views.split('} else if operation == .notificationStatus, let campaign', 1)[1].split('} else {', 1)[0]
        self.assertIn('if campaign.canRetryFailed {', branch)
        self.assertIn('edit(.retryNotification)', branch)
        self.assertIn('ClubOpsNotifyContentFields(title: textBinding("title"), content: textBinding("content"))', self.form)
        self.assertIn('(route.operation != .sendNotification || !["title", "content"].contains(key))', self.form)
        self.assertIn('(route.operation != .sendNotification || key != "audienceType")', self.form)
        self.assertIn('if route.operation == .sendNotification { ClubOpsNotifyPreviewSummary(value: review.snapshot.value) }', self.form)
        self.assertIn('ClubOpsNotifyCampaignRows(campaign: campaign, outcome: route.operation)', self.form)
        self.assertIn('content.utf16.count <= 1000', text('Core/ClubGovernanceCommands.swift'))
        for forbidden in ['perform(', 'coordinator', 'access.read', 'canDispatch', 'requestId']:
            self.assertNotIn(forbidden, self.notify_ui)
        self.assertIn('ClubNotificationAudienceReadModel.eventAudienceIDs.contains(option.id)', self.audience)
        self.assertIn('LabeledContent("club.gov.field.totalCount", value: String(count))', self.audience)

    def test_core_cases_are_authored(self):
        for name in ['testRejectSendsReviewReasonOnlyWhenPresent', 'testInvalidOrMisplacedReasonNeverDispatches',
                     'testConfirmationFreezesReasonForRejectOnly', 'testOverlongReasonIsNotSentAndLegacyAccessRefusesReason',
                     'testDisplayTextDecodesFiveEntitiesInOnePass', 'testCampaignPhasePendingAndProcessing',
                     'testAudienceRowsKeepNullUnknownAndOrder', 'testDraftIssueMatchesMiniProgramOrderAndBounds']:
            self.assertIn('func ' + name, self.tests)
        self.assertIn('@testable import QuestifyCore', self.tests)


if __name__ == '__main__':
    unittest.main()
