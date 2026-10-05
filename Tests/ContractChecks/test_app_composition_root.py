"""Supplementary source-only checks; recorder XCTest execution requires Apple CI."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class AppCompositionRootContracts(unittest.TestCase):
    def text(self, path): return (ROOT/path).read_text()
    def test_default_is_explicitly_unconfigured_and_grants_are_not_auth_derived(self):
        root = self.text('App/AppCompositionRoot.swift')
        launch = self.text('App/RegionalLaunchConfiguration.swift')
        self.assertIn('.init(deployment: .unconfigured,', launch)
        self.assertIn('DeploymentState = .unconfigured', root)
        self.assertIn('self.sessionDependencies = sessionDependencies ?? { _ in .dormant }', root)
        self.assertNotIn('OperationEndpointApproval(', root)
        self.assertIn('approvedBaseURLs: approvedBaseURLs', root)
        self.assertIn('verifiedCapabilities: verifiedCapabilities', root)
        self.assertIn('reads: Set<ReadGrant> = []', root)
    def test_normal_services_cannot_construct_live_transport_or_bypass_route_gate(self):
        session = self.text('App/AppSession.swift')
        root = self.text('App/AppCompositionRoot.swift')
        self.assertNotIn('URLSessionTransport()', session)
        self.assertNotIn('ResponseLimitedHTTPTransport(', session)
        self.assertIn('let transport=compositionTransport', session)
        self.assertIn('transportOverride: runtimeHTTPTransport', session)
        self.assertEqual(session.count('let transport = scopedTransport(transport)'), 4)
        self.assertIn('transport: scopedTransport(transport)', session)
        for marker in ['request.httpMethod == "POST"', 'url.query == nil', 'url.fragment == nil',
                       'deployment.reads.contains(.homeAndSearch)', 'current() == captured',
                       'request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) != captured.token.map({ Data($0.utf8) })']:
            self.assertIn(marker, root)
    def test_storage_preserves_existing_unknown_journal_format(self):
        root = self.text('App/AppCompositionRoot.swift')
        session = self.text('App/AppSession.swift')
        self.assertIn('OperationDefaultsJournal(defaults: defaults)', root)
        self.assertNotIn('ScopedCompositionJournal', root)
        self.assertIn('vault=composition.storage.tokenStore(scope)', session)
        self.assertNotIn('UserDefaults.standard.', session)
        logout = session.split('func logout() async {',1)[1].split('func activities(',1)[0]
        self.assertNotIn('journal.clear', logout)
    def test_atomic_authenticated_builder_and_context_invalidation(self):
        session = self.text('App/AppSession.swift')
        self.assertIn('guard !committingAuthenticatedSession, let context = currentRuntimeDependencyContext', session)
        self.assertIn('retainedDependencyContext != context', session)
        self.assertIn('retainedDependencyContext = nil; retainedDependencies = .dormant', session)
        commit = session.split('private func commitAuthenticatedSession(',1)[1].split('func bootstrap()',1)[0]
        self.assertLess(commit.index('committingAuthenticatedSession = true'), commit.index('self.token = token'))
        self.assertLess(commit.index('self.account = account'), commit.index('committingAuthenticatedSession = false'))
