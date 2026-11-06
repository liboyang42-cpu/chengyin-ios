"""Source contracts for w2-16 second pass: join-requests / notify copy, series topic names + 409 refresh,
appeal mode, roles 分配 label and their offline fixtures. Does not run Swift or native UI."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def text(path):
    return (ROOT / path).read_text()


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


class ClubOpsJoinNotifyContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = text('Core/ClubOpsJoinNotifyPresentation.swift')
        cls.ui = text('App/ClubOpsJoinNotifyViews.swift')
        cls.management = text('App/ClubManagementView.swift')
        cls.audience = text('App/ClubNotificationAudienceView.swift')
        cls.views = text('App/ClubGovernanceViews.swift')
        cls.form = text('App/ClubGovernanceCommandForm.swift')
        cls.editor = text('App/ClubSeriesScheduleEditor.swift')
        cls.event_core = text('Core/ClubOpsEventPresentation.swift')
        cls.event_ui = text('App/ClubOpsEventView.swift')
        cls.gov_ui = text('App/ClubOpsGovernanceSections.swift')
        cls.catalog = json.loads(text('Resources/ClubOpsJoinNotify.xcstrings'))
        cls.gov = json.loads(text('Resources/ClubOpsGovernance.xcstrings'))['strings']
        cls.event = json.loads(text('Resources/ClubOpsEvent.xcstrings'))['strings']

    @staticmethod
    def zh(strings, key):
        return strings[key]['localizations']['zh-Hans']['stringUnit']['value']

    def test_sources_and_catalog_are_registered(self):
        project = text('Questify.xcodeproj/project.pbxproj')
        for path in ['Core/ClubOpsJoinNotifyPresentation.swift', 'App/ClubOpsJoinNotifyViews.swift', 'Resources/ClubOpsJoinNotify.xcstrings']:
            self.assertIn(path, project)
        self.assertNotIn('import SwiftUI', self.core)
        self.assertIn('@testable import QuestifyCore', text('Tests/CoreTests/ClubOpsJoinNotifyPresentationTests.swift'))

    def test_catalog_is_bilingual_and_covers_literal_keys(self):
        strings = self.catalog['strings']
        self.assertEqual(self.catalog['sourceLanguage'], 'en'); self.assertEqual(self.catalog['version'], '1.0')
        for key, entry in strings.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)
            for language in ['en', 'zh-Hans']:
                unit = entry['localizations'][language]['stringUnit']
                self.assertEqual(unit['state'], 'translated'); self.assertTrue(unit['value'].strip(), key)
        sources = re.sub(r'\.accessibilityIdentifier\([^\n]*\)', '', self.ui + self.core)
        for key in set(re.findall(r'"(clubOps(?:Join|Notify)\.[A-Za-z.]+)"', sources)):
            self.assertIn(key, strings)

    def test_mini_copy_is_exact(self):
        s = self.catalog['strings']
        self.assertEqual(self.zh(s, 'clubOpsJoin.approving'), '正在通过…')
        self.assertEqual(self.zh(s, 'clubOpsJoin.rejecting'), '正在拒绝…')
        self.assertEqual(self.zh(s, 'clubOpsJoin.failed'), '入会申请加载失败')
        self.assertEqual(self.zh(s, 'clubOpsJoin.retry'), '重新加载')
        self.assertEqual(self.zh(s, 'clubOpsJoin.stale'), '入会申请暂未更新')
        self.assertEqual(self.zh(s, 'clubOpsJoin.retryStale'), '重试更新')
        self.assertEqual(self.zh(s, 'clubOpsNotify.denied.title'), '你没有发通知的权限')
        self.assertEqual(self.zh(s, 'clubOpsNotify.denied.body'), '发俱乐部通知需要「通知成员」权限,可以请主理人给你委派。')
        self.assertEqual(self.zh(s, 'clubOpsNotify.failed'), '通知工具暂时不可用')
        self.assertEqual(self.zh(self.event, 'clubOpsEvent.series.conflict'), '系列已被更新，正在刷新')
        self.assertEqual(self.zh(self.gov, 'clubOpsGov.appeal.mode'), '封禁申诉')
        self.assertEqual(self.zh(self.gov, 'clubOpsGov.failed'), '治理功能暂时不可用')
        self.assertEqual(self.zh(self.gov, 'clubOpsGov.roles.failed'), '角色管理暂时不可用')
        self.assertEqual(self.zh(self.gov, 'clubOpsGov.roles.assign.title'), '分配固定角色')
        for path in ['Resources/Localizable.xcstrings', 'Resources/ClubGovernanceLocalizations.fragment.json']:
            entry = json.loads(text(path))['strings']['club.gov.action.assignRole']['localizations']
            self.assertEqual(entry['zh-Hans']['stringUnit']['value'], '分配')
        self.assertIn('assignRole|Assign|分配', text('tools/build_club_governance_catalog.py'))

    def test_join_progress_and_load_issue_only_touch_labels_and_read_refresh(self):
        self.assertIn('submitting: state == .submitting', self.management)
        self.assertIn('ClubOpsJoinRequestActionLabel(action: action, progressKey: progressKey(action, memberID: memberID))', self.management)
        self.assertIn('ClubOpsJoinRequestActionLabel(action: pending.action, progressKey: progressKey(pending.action, memberID: pending.memberID))', self.management)
        self.assertIn('ClubOpsJoinRequestLoadIssue(issue: issue,', self.management)
        self.assertIn('{ Task { await refresh() } }', span(self.management, 'ClubOpsJoinRequestLoadIssue(issue: issue,', '\n'))
        self.assertIn('guard submitting, actingAction == action, actingMemberID == memberID else { return nil }', self.core)
        for token in ['coordinator.confirm', 'coordinator.prepare', '.perform(', 'claim(', 'ProductionApproval', 'URLSession']:
            self.assertNotIn(token, self.ui); self.assertNotIn(token, self.core)

    def test_notify_denial_has_no_retry(self):
        self.assertIn('case .audienceCounts:\n            Section { ClubOpsNotifyDeniedText() }', self.gov_ui)
        self.assertIn('if isCurrent(), permit != nil, model.failure == .forbidden { ClubOpsNotifyDeniedText() }', self.audience)
        denied = span(self.ui, 'struct ClubOpsNotifyDeniedText: View {', '\n}\n')
        self.assertNotIn('Button', denied)
        self.assertIn('guard failure != .forbidden, failure != .signedOut else { return nil }', self.core)
        self.assertIn('ClubOpsPageFailureSection(copy: copy) { Task { await load() } }', self.views)

    def test_series_topic_names_are_display_only_and_never_block_rows(self):
        self.assertIn('try? await access.read(.eventTopics, scope: scope, options: [:], check: check)', self.event_ui)
        self.assertIn('ClubOpsEventSeriesList(value: $0.value, topicNames: seriesTopicNames.names(readContext))', self.views)
        self.assertIn('await seriesTopicNames.load(context: context, access: access)', self.views)
        self.assertIn('snapshot.scope.clubID == clubID', self.event_core)
        self.assertEqual(text('Core/ClubGovernanceContracts.swift').count('case .eventTopics, .series, .seriesDetail, .occurrences, .occurrenceStatus: return "club:activity:manage"'), 1)

    def test_conflict_refresh_is_read_only_and_requires_definite_conflict(self):
        self.assertIn('guard operation == .updateSeries, state == .conflict, case .conflict? = failure else { return false }', self.event_core)
        owner = self.editor.split('@MainActor final class ClubSeriesUpdateReturn:', 1)[1]
        conflicted = span(owner, 'func conflicted(', 'func consumeConflict(')
        for token in ['submissionID == review.id', 'acknowledgedID == nil', 'conflictedID == nil',
                      'ClubOpsEventSeriesConflict.qualifies(operation: review.command.operation, failure: failure, state: state)']:
            self.assertIn(token, conflicted)
        consume = span(owner, 'func consumeConflict(', 'func retire()')
        self.assertIn('guard visible, active, !isPresented, didDismiss, acknowledgedID == nil, conflictedID != nil', consume)
        catch = span(self.form, 'private func confirm(_ review:', '\n}\n').split('} catch {', 1)[1]
        self.assertIn('locked = coordinator.isLocked(review.command, identity: review.identity)', catch)
        self.assertIn('submittedRequestID == draft.requestID, !locked, let definite = failure', catch)
        self.assertLess(catch.index('locked = coordinator.isLocked'), catch.index('seriesUpdateReturn?.conflicted('))
        finish = span(self.views, 'private func finishSeriesUpdateReturn()', 'private var terminalSource:')
        self.assertIn('seriesUpdateReturn.consumeConflict(source: seriesUpdateSource', finish)
        for forbidden in ['coordinator.confirm(', 'access.send(', 'coordinator.prepare(']:
            self.assertNotIn(forbidden, finish); self.assertNotIn(forbidden, conflicted + consume)
        self.assertIn('seriesUpdateReturn.conflictNotice == readContext { ClubOpsEventSeriesConflictNotice() }', self.views)

    def test_appeal_mode_and_roles_title(self):
        self.assertIn('public var appealMode: Bool { !canReport || canAppeal }', text('Core/ClubOpsGovernancePresentation.swift'))
        self.assertIn('if list.appealMode {', self.gov_ui)
        self.assertIn('if route.operation == .assignRole { return Text("clubOpsGov.roles.assign.title", tableName: "ClubOpsGovernance") }',
                      text('App/ClubOpsEventFormFields.swift'))

    def test_offline_fixtures_reach_each_new_state(self):
        host = text('App/ClubGovernanceFixtureHost.swift')
        self.assertIn('ClubOpsFixtureControls(access: store.access)', host)
        self.assertIn('.audienceCounts, .roster, .cases, .bans]', host)
        fixtures = span(self.ui, '#if DEBUG', '#endif')
        for token in ['writeFailure = .conflict(message: nil)', 'removing: ["club:notify:send", "club:event:operate"]',
                      'readFailure = .malformed', '"active":false', '"activeBan":{"id":161']:
            self.assertIn(token, fixtures)
        self.assertIn('if readCount == 1, scenario == .loadFailure { throw APIError.malformedResponse }', text('App/ClubManagementFixtureSupport.swift'))
        tests = text('Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift')
        self.assertIn('func testDefiniteConflictClosesOnceForReadOnlyRefreshWithoutResend(', tests)
        self.assertIn('func testUnknownOrRejectedOutcomeNeverQualifiesAsConflictRefresh(', tests)

    def test_no_long_hex_literals(self):
        for path in ['Core/ClubOpsJoinNotifyPresentation.swift', 'App/ClubOpsJoinNotifyViews.swift', 'Resources/ClubOpsJoinNotify.xcstrings']:
            self.assertIsNone(re.search(r'[0-9a-fA-F]{32}', text(path)), path)


if __name__ == '__main__':
    unittest.main()
