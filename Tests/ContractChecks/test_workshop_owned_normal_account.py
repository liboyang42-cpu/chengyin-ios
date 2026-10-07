from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class WorkshopOwnedNormalAccountContractTests(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_ordinary_account_entry_uses_session_browser(self):
        self.assertIn('WorkshopOwnedAccountLink(browser: session.workshopOwnedBrowser)', self.read('App/AccountView.swift'))
        self.assertIn('WorkshopOwnedUnavailableView()', self.read('App/WorkshopOwnedLibraryView.swift'))
    def test_typed_approval_is_default_nil_in_both_composition_layers(self):
        text = self.read('App/AppCompositionRoot.swift')
        self.assertEqual(text.count('workshopOwnedReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopOwnedReadApproval? = { _ in nil }'), 2)
        self.assertEqual(text.count('workshopOwnedReadApproval: workshopOwnedReadApproval'), 2)
        self.assertIn('fresh.revision == approval.revision && fresh.matches(context)', text)
    def test_session_retains_binding_and_configuration_invalidates_before_mutation(self):
        text = self.read('App/AppSession.swift')
        self.assertIn('private let workshopOwnedBinding = WorkshopOwnedSessionBinding()', text)
        self.assertIn('workshopOwnedBinding.reconcile(context: context, configurationRevision: approval?.revision)', text)
        self.assertIn('invalidateWorkshopReadBindings()\n        workshopReadConfigurationChanging = true\n        change()\n        workshopReadConfigurationChanging = false\n        workshopReadConfigurationRevision &+= 1', text)
        self.assertIn('private func invalidateWorkshopReadBindings() { workshopCreatorPendingBinding.invalidate(); workshopCreatorConsentBinding.invalidate(); workshopPaidProfessionalBinding.invalidate(); workshopOwnedBinding.invalidate(); workshopPurchasedBinding.invalidate(); workshopPaidInstallBinding.invalidate(); workshopPaidInstalledTextBinding.invalidate() }', text)
        self.assertIn('transport: compositionTransport', text)
        self.assertIn('self.workshopReadConfigurationRevision == configurationRevision', text)
    def test_every_gate_mutation_invalidates_before_it_changes(self):
        lines = self.read('App/AppSession.swift').splitlines()
        for i, line in enumerate(lines):
            if 'gate.invalidate()' in line or 'let operation=gate.begin(' in line:
                self.assertIn('invalidateWorkshopReadBindings()', lines[i-1])
            if 'if gate.cancelLogin()' in line:
                self.assertIn('gate.activeKind == .login { invalidateWorkshopReadBindings() }', lines[i-1])
        self.assertIn('willSet { if account?.id != newValue?.id', '\n'.join(lines))
        self.assertIn('willSet { if token.map', '\n'.join(lines))
    def test_root_lifetime_is_separate_from_list_close(self):
        text = self.read('App/QuestifyApp.swift')
        self.assertIn('.onAppear { session.setWorkshopOwnedPresentationActive(true) }', text)
        self.assertIn('.onDisappear { session.setWorkshopOwnedPresentationActive(false) }', text)
        self.assertIn('navigation.listViewDisappeared(displayed)', self.read('App/WorkshopOwnedLibraryView.swift'))
        self.assertIn('browser.leaveList(presentation, closing: selection == nil)', self.read('App/WorkshopOwnedNavigationState.swift'))
    def test_route_is_exact_and_cannot_expand_into_package_or_mutation(self):
        text = self.read('App/WorkshopOwnedReadRoute.swift')
        for required in ['url.query == nil', 'url.fragment == nil', 'request.httpMethod == "POST"', 'request.httpBodyStream == nil', 'String(body.count)', 'guard body.isEmpty', 'WorkshopOwnedWire.identifier', 'default: return nil']:
            self.assertIn(required, text)
        for forbidden in ['api/workshop/owned/package', 'api/workshop/owned/purchase', 'URLSessionTransport']:
            self.assertNotIn(forbidden, text)
    def test_normal_session_runtime_cases_are_authored(self):
        text = self.read('Tests/AppUnitTests/WorkshopOwnedNormalAccountTests.swift')
        for name in ['testNormalRootGuestAndSignedIn', 'testApprovedNormalAccountListDetailAndReopen', 'testRoleABA', 'testOwnerTokenEpochReplacement', 'testConfigurationABA', 'testRootRemoval', 'testCurrent401', 'testSameOwnerReauthentication', 'testMismatchedOrExpiredApproval']:
            self.assertIn('func '+name, text)
        self.assertNotIn('URLSession', text)

    def test_queued_reads_use_synchronously_offered_navigation_permits(self):
        text = self.read('Tests/AppUnitTests/WorkshopOwnedNormalAccountTests.swift')
        for name in ['testQueuedListAfterBackAndReopen', 'testQueuedDetailAfterBack', 'testQueuedReadAcrossRoleOrApprovalABA', 'testNewVisibleOfferRetiresOld401']:
            self.assertIn('func '+name, text)
        self.assertIn('let action = try listAction(old); let task = Task { await old.load(action: action) }', text)
        self.assertIn('navigation.listDisappeared(navigation.listPermit)', text)
        self.assertIn('XCTAssertNil(previous.offer())', text)
        self.assertIn('XCTAssertNil(browser.packageBrowser', text)
        self.assertNotIn('Task { await old.load()', text)
        self.assertNotIn('Task { await browser.load()', text)
