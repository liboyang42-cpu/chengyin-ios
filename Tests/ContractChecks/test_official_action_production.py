"""Offline composition/security regression checks; not Swift runtime evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class OfficialActionProductionChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_normal_root_and_defaults(self):
        app = self.read('App/AppSession.swift')
        region = self.read('App/RegionalLaunchConfiguration.swift')
        dependency = self.read('App/NativeRuntimeDependencies.swift')
        self.assertIn('OfficialActionProductionFactory(api: regionalConfiguration?.apiConfiguration', app)
        self.assertIn('approval: runtimeDependencies.officialActionApproval, transport: runtimeHTTPTransport', app)
        self.assertIn('current: { [weak self] in self?.currentRuntimeDependencyContext }', app)
        self.assertIn('officialActionApproval: OfficialActionProductionApproval? = nil', dependency)
        self.assertIn('static var dormant: Self { .init() }', dependency)
        self.assertIn('let approved:[RegionalMarket:Set<String>]=[:]', region)
        self.assertIn('session=(composition ?? RegionalLaunchConfiguration.composition).makeSession()', self.read('App/QuestifyApp.swift'))
        self.assertNotIn('write: { _ in throw OfficialActionFailure.disabled }', app)

    def test_scope_is_exact_and_market_stays_off_without_grants(self):
        source = self.read('Core/OfficialActionProduction.swift')
        for value in ['market == .china', 'context.market == market', 'endpoints.baseURL == context.baseURL',
                      'endpoints.namespace == context.session.namespace', 'endpoints.accountID == context.session.accountID',
                      'commands.contains(command)', 'reads.union([command.path]).isSubset(of: endpoints.paths)',
                      'observedContext != context', 'observedIdentity != identity']:
            self.assertIn(value, source)
        self.assertNotIn('URLSession', source)
        self.assertNotIn('UserDefaults', source)

    def test_writes_need_coordinator_authorization_after_durable_lock(self):
        source = self.read('Core/OfficialActionCoordinator.swift')
        self.assertLess(source.index('try locks.insert(lock)'), source.index('OfficialActionDispatchAuthorization(review: review'))
        self.assertIn('fileprivate init(review:', source)
        self.assertIn('return try self.locks.contains(lock)', source)
        self.assertIn('self.generation == revision', source)
        self.assertIn('self.state == .submitting', source)
        self.assertIn('fresh == review.snapshot', source)
        factory = self.read('Core/OfficialActionProduction.swift')
        self.assertIn('public func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt { throw OfficialActionFailure.forbidden }', factory)
        for value in ['!dispatched', 'request.url == expected.url', 'request.httpBody == expected.httpBody',
                      'request.allHTTPHeaderFields == expected.allHTTPHeaderFields', 'request.httpBodyStream == nil',
                      'authorization.review.command == command', 'expected.httpBody == authorization.review.body']:
            self.assertIn(value, factory)
        self.assertGreaterEqual(factory.count('try authorization.validate()'), 4)

    def test_readback_is_separate_and_cannot_release_unknown_outcomes(self):
        factory = self.read('Core/OfficialActionProduction.swift')
        coordinator = self.read('Core/OfficialActionCoordinator.swift')
        self.assertIn('case event(OfficialEvent), published(OfficialPublished), party(OfficialPartyInvite?)', factory)
        self.assertIn('catch { throw OfficialActionFailure.unknown }', factory)
        self.assertIn('published.events.contains(where: { $0.id == id && $0.isCompleteRecord })', factory)
        self.assertIn('published.broadcasts.contains(where: { $0.id == id })', factory)
        self.assertIn('event.id == id, event.signed == true { try locks.remove(lock) }', coordinator)
        self.assertIn('access.identity == readbackIdentity ? verifiedReadback : nil', coordinator)
        self.assertNotIn('event.signed =', factory)
        self.assertNotIn('/receipt', factory)
        self.assertNotIn('/retry', factory)

    def test_missing_source_context_cannot_be_granted(self):
        source = self.read('Core/OfficialActionProduction.swift')
        self.assertIn('case .arrival, .inviteMerchants: return nil', source)
        self.assertIn('case .arrival, .inviteMerchants: throw OfficialActionFailure.disabled', source)
        app = self.read('App/OfficialEventDetailView.swift')
        self.assertIn('OfficialParticipationActions(coordinator: actions, event: event)', app)

    def test_required_runtime_cases_are_authored(self):
        tests = self.read('Tests/CoreTests/OfficialActionProductionTests.swift')
        for case in ['NoApprovalMakesZeroReadsAndWrites', 'NakedPreparedAccessCannotBypassDurableAuthorization',
                     'PublishWritesExactReviewOnceThenReadsOwnedResult', 'UnknownPostSurvivesFactoryAndCoordinatorRecreation',
                     'ReadbackRejectionCannotUnlockSuccessfulPost', 'FilteredPartyDisappearanceIsInconclusiveAndLocked',
                     'RoleAndTokenChangesInvalidateReviewedIdentity', 'SessionChangeDuringPostKeepsUnknownLockAndNoReadback',
                     'CancelDuringPostDoesNotPretendRejection', 'CorruptJournalFailsClosedBeforeReadOrWrite']:
            self.assertIn('func test' + case, tests)
