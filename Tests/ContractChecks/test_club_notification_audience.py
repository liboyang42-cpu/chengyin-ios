"""Read-only audience source contracts; no Swift or app execution."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


def require_read_fences(source):
    load = span(source, 'func load(_ permit:', '@MainActor struct ClubNotificationAudienceView')
    for token in ['guard accepts(permit), isCurrent(), !Task.isCancelled', 'clear(); let request = generation',
                  'guard isCurrent(), accepts(permit), generation == request',
                  'live(permit.context, access: access), !Task.isCancelled',
                  'access.read(.access', 'access.read(.audienceCounts',
                  'options = nil; loaded = nil; failure =']:
        if token not in load:
            raise AssertionError('Missing read fence: ' + token)
    for operation in ['.access', '.audienceCounts']:
        start = load.index('let ' + ('authority' if operation == '.access' else 'counts') + ' = try await')
        end = load.index('try check()', start)
        if 'check: check)' not in load[start:end]:
            raise AssertionError('Missing read validator')
    if load.index('access.read(.access') >= load.index('access.read(.audienceCounts'):
        raise AssertionError('Counts before authority')


class ClubNotificationAudienceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.view = (ROOT / 'App/ClubNotificationAudienceView.swift').read_text()
        cls.host = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        cls.tests = (ROOT / 'Tests/AppUnitTests/ClubNotificationAudienceTests.swift').read_text()

    def test_exact_six_finite_audiences_and_no_person_collection(self):
        self.assertIn('audienceIDs = ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"]', self.view)
        self.assertIn('eventAudienceIDs: Set<String> = ["REGISTERED", "WAITLIST", "NO_SHOW"]', self.view)
        for token in ['memberID', 'recipientIDs', '.members', 'memberPicker']:
            self.assertNotIn(token, self.view)

    def test_counts_are_strict_optional_display_values(self):
        project = span(self.view, 'static func project(', 'func load(_ permit:')
        for token in ['case .integer(let value)', 'value >= 0', 'count = value', 'count = nil', 'enabled']:
            self.assertIn(token, project)
        self.assertNotIn('?? 0', project.split('let count: Int?', 1)[1])
        self.assertIn('else { Text("club.gov.unknownValue")', self.view)
        self.assertIn('LabeledContent("club.gov.field.totalCount", value: String(count))', self.view)

    def test_permission_and_exact_scope_are_proved_before_choices(self):
        project = span(self.view, 'static func project(', 'func load(_ permit:')
        for token in ['snapshot.operation == operation', 'snapshot.scope == scope', 'let permissions = snapshot.permissions',
                      'permissions.allows("club:notify:send", scope: scope)',
                      '(scope.activityID ?? 0) > 0 && permissions.allows("club:event:operate", scope: scope)',
                      'guard clubAllowed || eventAllowed', 'eventOnly ? eventAllowed : clubAllowed']:
            self.assertIn(token, project)

    def test_each_await_has_live_owner_and_generation_fences(self):
        require_read_fences(self.view)

    def test_removing_each_critical_fence_is_detected(self):
        mutations = ['isCurrent(), accepts(permit)', 'generation == request,',
                     'live(permit.context, access: access), !Task.isCancelled',
                     'check: check)', 'guard accepts(permit), isCurrent(), !Task.isCancelled']
        for token in mutations:
            with self.subTest(token=token):
                self.assertIn(token, self.view)
                with self.assertRaises(AssertionError):
                    require_read_fences(self.view.replace(token, '', 1))

    def test_current_identity_authorization_namespace_and_reader_required(self):
        live = span(self.view, 'private func live(', 'func accepted(')
        for token in ['read.identity?.isSignedIn == true', 'access.isConfigured', 'read.identity == access.identity',
                      'read.authorizationGeneration == access.authorizationGeneration',
                      'read.accessIdentity == ObjectIdentifier(access)', 'context.namespace == access.storageNamespace']:
            self.assertIn(token, live)

    def test_optional_count_failure_does_not_mask_authorization_failure(self):
        load = span(self.view, 'func load(_ permit:', '@MainActor struct ClubNotificationAudienceView')
        self.assertIn('[.forbidden, .signedOut, .notConfigured, .targetChanged, .staleReview].contains(failure)', load)
        self.assertIn('options = authorized; countsUnavailable = true', load)
        self.assertNotIn('.send(', load)
        self.assertNotIn('coordinator', load)

    def test_old_snapshot_row_cannot_select_after_refresh_or_leave(self):
        select = span(self.view, 'func canSelect(', 'func canPrepare(')
        self.assertIn('accepts(permit) && self.snapshotID == snapshotID', select)
        self.assertIn('accepted(permit.context, access: access)', select)
        self.assertIn('$0.id == id && $0.enabled', select)
        self.assertIn('visibility = nil; clear()', self.view)
        self.assertIn('snapshotID = UUID(); loaded = nil; options = nil', self.view)

    def test_stable_form_owns_model_and_visibility_not_lazy_row(self):
        self.assertIn('@StateObject private var notificationAudience = ClubNotificationAudienceReadModel()', self.host)
        self.assertIn('@ObservedObject var model: ClubNotificationAudienceReadModel', self.view)
        for token in ['.task(id: AudienceTrigger(', '.onAppear { audienceVisible = true }',
                      'if phase != .active { notificationAudience.leave(audienceContext) }',
                      '.onDisappear { audienceVisible = false; notificationAudience.leave(audienceContext)',
                      'isCurrent: { audienceIsCurrent && audienceContext == expected }']:
            self.assertIn(token, self.host)
        for token in ['.sheet(', '@StateObject', '.onDisappear']:
            self.assertNotIn(token, self.view)

    def test_normal_form_uses_existing_local_binding_and_review_pipeline(self):
        self.assertIn('selection: textBinding("audienceType")', self.host)
        self.assertIn('(route.operation != .sendNotification || key != "audienceType")', self.host)
        self.assertIn('|| !notificationAudienceReady).accessibilityIdentifier("club.gov.prepare")', self.host)
        self.assertIn('draft.text[key] = $0; dirty = true; review = nil; coordinator.cancelReview()', self.host)
        self.assertIn('try await coordinator.prepare(draft.command())', self.host)
        self.assertIn('try await coordinator.confirm(review)', self.host)
        self.assertIn('if selection != option.id { selection = option.id }', self.view)

    def test_rows_use_current_stamp_and_borderless_hit_regions(self):
        for token in ['guard canEdit(), isCurrent(), model.canSelect(option.id, snapshotID: snapshot, permit: permit, access: access)',
                      '.disabled(!canEdit() || !option.enabled)', '.contentShape(Rectangle())',
                      '.buttonStyle(.borderless).accessibilityElement(children: .contain)',
                      'Task { await model.load(permit, access: access, isCurrent: isCurrent) }']:
            self.assertIn(token, self.view)

    def test_new_catalog_has_both_languages_and_only_own_key(self):
        strings = json.loads((ROOT / 'Resources/ClubNotificationAudience.xcstrings').read_text())['strings']
        self.assertEqual(set(strings), {'club.audience.chooseEvent'})
        for lang in ['en', 'zh-Hans']:
            self.assertTrue(strings['club.audience.chooseEvent']['localizations'][lang]['stringUnit']['value'])

    def test_project_registers_app_test_and_catalog_once(self):
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        for path in ['App/ClubNotificationAudienceView.swift', 'Tests/AppUnitTests/ClubNotificationAudienceTests.swift',
                     'Resources/ClubNotificationAudience.xcstrings']:
            self.assertEqual(project.count('"path" = "' + path + '";'), 1)

    def test_native_negatives_are_authored_with_actual_models_and_held_reads(self):
        self.assertEqual(len(re.findall(r'^    func test', self.tests, re.M)), 23)
        for name in ['testHiddenOwnerDuringAuthorityCannotStartCountsWithoutLeave',
                     'testInactiveOwnerDuringCountsCannotPublishWithoutLeave',
                     'testCountsScopeMismatchCannotPublishOrFallBack',
                     'testLeaveAndReopenRejectOldPermitAndQueuedRetry',
                     'testOlderCountResponseCannotReplaceNewerCounts',
                     'testCancelledAuthorityCannotStartCounts']:
            self.assertIn('func ' + name, self.tests)
        self.assertIn('CheckedContinuation<ClubGovernanceSnapshot, Error>', self.tests)
        self.assertIn('XCTFail("Audience selection must not send")', self.tests)


if __name__ == '__main__':
    unittest.main()
