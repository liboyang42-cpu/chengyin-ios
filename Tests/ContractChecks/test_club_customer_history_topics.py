"""Native-local structural guards; these do not execute Swift or establish UI behavior."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubCustomerHistoryTopicContracts(unittest.TestCase):
    def test_session_uses_existing_topic_detail(self):
        source = (ROOT / 'App/AppSession.swift').read_text().split('var clubGovernanceContext:')[1].split('private var currentClubOperationsSession:')[0]
        self.assertIn('topicDestination:', source)
        self.assertIn('SessionTopicDetailView(id: id, session: self)', source)
        self.assertNotIn('topicOverview', source)
    def test_workspace_and_member_entry_inherit_identical_context(self):
        self.assertIn('customerTopics: governance.customerTopics', (ROOT / 'App/ClubDetailView.swift').read_text())
        self.assertIn('.environment(\\.clubCustomerTopics, governance.customerTopics)', (ROOT / 'App/ClubMembersView.swift').read_text())
        self.assertIn('.environment(\\.clubCustomerTopics, customerTopics)', (ROOT / 'App/ClubGovernanceViews.swift').read_text())
        context = (ROOT / 'App/ClubGovernanceContext.swift').read_text()
        self.assertIn('.init(viewerRevision: viewerRevision, destination: topicDestination)', context)
    def test_scoped_read_and_late_response_guards(self):
        view = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        for token in ['.task(id: readContext)', '.onChange(of: readContext)', 'context == readContext',
                      'context.accepts(result)', 'snapshotContext == readContext', 'access.identity == expected',
                      'authorizationGeneration: access.authorizationGeneration', '.onDisappear { generation &+= 1 }']:
            self.assertIn(token, view)
        self.assertGreaterEqual(view.count('context == readContext'), 2)
    def test_navigation_rechecks_selection_and_does_not_invent_endpoint(self):
        view = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.assertIn('guard customerTopic == nil, current(target)', view)
        self.assertIn('if let destination = customerTopics.destination, current(target)', view)
        self.assertIn('destination(target.topicID).id(target.id)', view)
        route = (ROOT / 'Core/ClubCustomerHistoryTopicRoute.swift').read_text()
        for token in ['Self.positiveID(record["topicId"])', 'records.contains(record)', 'snapshot.permissions?.allows(',
                      'snapshot.scope == scope', 'snapshot.value["summary"]["memberId"].int == context.scope.memberID',
                      'self.snapshotGeneration == snapshotGeneration', 'record["clubId"]', 'record["memberId"]', '9_007_199_254_740_991']:
            self.assertIn(token, route)
        self.assertNotIn('api/', route)
        self.assertNotIn('transport', route)
    def test_push_does_not_invalidate_its_own_accepted_snapshot(self):
        view = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.assertIn('snapshotGeneration: snapshotGeneration', view)
        self.assertIn('snapshotContext = context; snapshotGeneration = revision; snapshot = result', view)
        self.assertNotIn('.onDisappear { snapshot = nil', view)
    def test_authored_swift_tests_cover_negative_and_interrupted_flows(self):
        tests = (ROOT / 'Tests/CoreTests/ClubCustomerHistoryTopicRouteTests.swift').read_text()
        for name in ['testMissingMalformedFractionalAndUnsafeIDsRemainNonNavigable', 'testMissingTopicDoesNotInvalidateOtherwiseValidHistory',
                     'testForeignOrSubstitutedRowCannotCreateRoute', 'testWrongCustomerClubOperationAndMissingAuthorityFailClosed',
                     'testAccountEpochRoleAndAuthorityChangesInvalidateSelection', 'testNewerReadNilSnapshotAndDifferentTargetsInvalidateSelection',
                     'testRemovedOrRetargetedRecordCannotRenderAnOldSelection', 'testReadContextRejectsLateResponseForDifferentCustomerOrOperation']:
            self.assertIn(name, tests)
        ui = (ROOT / 'Tests/AppUITests/ModuleFlowTests.swift').read_text()
        for name in ['testClubCustomerHistoryOpensReturnedTopicAndCanReopenAfterBack', 'testClubCustomerHistoryMissingAndForeignIDsRemainReadOnly',
                     'testClubCustomerHistoryTopicClearsOnAccountAndRoleChanges']:
            self.assertIn(name, ui)
    def test_invalid_history_fixture_is_an_authorized_read_only_customer(self):
        fixture = (ROOT / 'App/ClubFixtureSupport.swift').read_text()
        owner_line = next(line for line in fixture.splitlines() if 'let owned =' in line and 'scenario' in line)
        self.assertIn('.customerInvalidHistory', owner_line)
        self.assertIn('governanceAccess.allowsOfflineWrites = false', fixture)
        self.assertIn('Missing topic history', fixture)
        self.assertIn('Foreign scope history', fixture)

class ClubCustomerHistoryReadLifecycleContracts(unittest.TestCase):
    def test_session_read_rechecks_context_before_unauthorized_side_effect(self):
        service = (ROOT / 'Core/ClubGovernanceService.swift').read_text()
        read = service.split('public func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue], check readCheck:')[1].split('public func send(')[0]
        self.assertIn('let revision = viewerRevision(), authorization = authorizationGeneration', read)
        catch = read.split('} catch {')[1]
        self.assertLess(catch.index('try checkRead('), catch.index('onUnauthorized(session.identity)'))
        self.assertIn('self.viewerRevision() == viewerRevision, authorizationGeneration == authorization', service)
        self.assertIn('try check(session); try readCheck()', service)
    def test_composition_supplies_monotonic_viewer_revision(self):
        session = (ROOT / 'App/AppSession.swift').read_text().split('lazy var clubGovernanceAccess =')[1].split('// Session-lived:')[0]
        self.assertIn('viewerRevision: { [weak self] in self?.compositionViewerRevision ?? 0 }', session)
    def test_view_supplies_read_generation_fence_to_access(self):
        view = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        check = view.split('let result = try await access.read(operation, scope: scope, options: options) {')[1].split('\n            }')[0]
        for token in ['revision == generation', 'context == readContext', 'access.identity == expected', 'throw CancellationError()']:
            self.assertIn(token, check)
    def test_authored_delayed_transport_tests_keep_valid_requests(self):
        tests = (ROOT / 'Tests/CoreTests/ClubGovernanceReadLifecycleTests.swift').read_text()
        for name in ['testDelayed401AfterSameSessionRoleChangeDoesNotExpireCurrentViewer',
                     'testDelayed401AfterUnobservedRoleABAUsesMonotonicViewerFence',
                     'testDelayed401AfterAuthorityChangeWithSameViewerRevisionIsDiscarded',
                     'testDelayed401AfterNewerReadOrBackUsesCallerGenerationFence',
                     'testDelayed401AfterSessionReplacementCannotExpireNewSession',
                     'testCurrent401StillExpiresExactlyOnceAtAccessAndDetailBoundaries',
                     'testCurrentCustomerReadStillReturnsPermissionCheckedSnapshot']:
            self.assertIn(name, tests)

if __name__ == '__main__': unittest.main()
