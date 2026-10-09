"""Bounded source contracts. They do not execute Swift or prove navigation runtime."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class TicketWalletReadLifetimeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TicketWalletReading.swift').read_text()
        cls.adapter = (ROOT / 'App/TicketWalletModel.swift').read_text()
        cls.screens = [(ROOT / path).read_text() for path in ['App/TicketWalletView.swift', 'App/TicketWalletDetailView.swift']]
        cls.tests = (ROOT / 'Tests/CoreTests/TicketWalletTests.swift').read_text()
    def test_owner_includes_exact_reader_scope_auth_configuration_and_registration(self):
        for token in ['public let readerID: ObjectIdentifier', 'readerID = ObjectIdentifier(reader); scope = reader.scope',
                      'configured = reader.isConfigured; authenticated = reader.isAuthenticated; self.id = id',
                      'loadedOwner == owner ? value : nil', 'loadedOwner == owner ? issue : nil']:
            self.assertIn(token, self.core)
    def test_presentation_nonce_is_new_and_retired_before_any_queued_load(self):
        self.assertIn('fileprivate let nonce = UUID()', self.core)
        self.assertIn('presentation = owner.canRead ? TicketWalletReadPresentation(owner: owner) : nil', self.core)
        self.assertIn('presentation = nil', self.core)
        load = self.core.split('public func load(presentation permit:', 1)[1]
        self.assertLess(load.index('accepts(permit, currentOwner: currentOwner())'), load.index('invalidate()'))
        self.assertLess(load.index('accepts(permit, currentOwner: currentOwner())'), load.index('try await operation()'))
        self.assertEqual(load.count('accepts(permit, currentOwner: currentOwner())'), 3)
    def test_cancellation_and_stale_failure_never_publish(self):
        self.assertIn('guard !Task.isCancelled, accepts(permit, currentOwner: currentOwner())', self.core)
        self.assertIn('!(error is CancellationError)', self.core)
        self.assertIn('generation == captured', self.core)
        self.assertIn('issue = TicketWalletIssue(error); loadedOwner = permit.owner', self.core)
    def test_end_can_preserve_rows_for_existing_pushed_navigation_without_retaining_permit(self):
        self.assertIn('if preservingValues { cancelPending() } else { invalidate() }', self.core)
        self.assertIn('if loadedOwner != owner { invalidate() } else { cancelPending() }', self.core)
        for view in self.screens:
            self.assertIn('model.endPresentation()', view)
            self.assertIn('model.value(owner: key)', view)
            self.assertIn('model.loadedOwner != key', view)
    def test_adapter_owns_tasks_and_refresh_cancellation_propagates_to_reader(self):
        for token in ['private var task: Task<Void, Never>?', 'task?.cancel(); task = nil',
                      'guard let presentation, accepts(presentation, currentOwner: currentOwner)',
                      'guard !Task.isCancelled, let self, self.accepts(presentation, currentOwner: currentOwner)',
                      'await withTaskCancellationHandler { await pending.value } onCancel: { pending.cancel() }']:
            self.assertIn(token, self.adapter)
    def test_every_retry_refresh_and_foreground_entry_captures_owned_presentation(self):
        for view in self.screens:
            for token in ['let offeredPresentation = model.presentation', 'schedule(offeredPresentation)',
                          'model.refresh(presentation: offeredPresentation, currentOwner: key)',
                          'model.schedule(presentation: permit, currentOwner: key)', 'schedule(model.beginPresentation(owner: key))',
                          'guard isVisible, scenePhase == .active, !Task.isCancelled,',
                          'model.accepts(presentation, currentOwner: key)']:
                self.assertIn(token, view)
            self.assertNotIn('Task {', view)
            self.assertNotIn('.task(id:', view)
    def test_background_departure_and_key_replacement_retire_old_permits(self):
        for view in self.screens:
            self.assertIn('if phase == .background { refreshOnActive = true; model.endPresentation() }', view)
            self.assertIn('isVisible && (refreshOnActive || model.presentation == nil)', view)
            self.assertIn('model.endPresentation(preservingValues: false)', view)
        self.assertIn('.onChange(of: key) { _, _ in replacePresentation() }', self.screens[0])
        self.assertIn('.onChange(of: TicketWalletPlayLoadKey(readerID: ObjectIdentifier(reader), key: key, providerOwner: playProvider?.owner))', self.screens[1])
    def test_play_receipt_requires_active_read_presentation_and_existing_provider(self):
        detail = self.screens[1]
        load = detail.split('private func load(presentation:', 1)[1].split('private struct TicketWalletPlayLoadKey', 1)[0]
        self.assertLess(load.index('model.accepts(presentation, currentOwner: key)'), load.index('playEntry.retire()'))
        self.assertIn('if !Task.isCancelled, model.accepts(presentation, currentOwner: key),', load)
        self.assertIn('provider.owner == playProvider?.owner, provider.matches(reader: reader)', load)
        self.assertIn('model.value(owner: captured)?.id == id, captured == key', load)
    def test_regressions_use_actual_model_and_http_transport_boundary(self):
        for name in ['testQueuedListAndDetailRetriesAfterDepartureMakeZeroHttpRequests',
                     'testOldPermitAfterBackAndReopenCannotDispatchOrClearFreshRows',
                     'testReaderReplacementAndRequestedIdChangeHideFactsEvenWhenScopeIsEqual',
                     'testAuthConfigurationAndInvalidIdCannotAcquireOrReusePermit',
                     'testDepartureBeforeSuccessOrAuthFailureReceiptDoesNotPublish',
                     'testCancelledQueuedTaskDoesNotDispatchAndCurrentAuthFailureKeepsLoginOutcome']:
            self.assertIn('func ' + name, self.tests)
        self.assertIn('let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)', self.tests)
    def test_no_added_grant_endpoint_location_payment_or_persistence(self):
        delta = self.core.split('/// A local read owner', 1)[1] + self.adapter + ''.join(self.screens)
        for forbidden in ['URLSession', 'api/', 'ReadApproval(', 'requestWhenInUseAuthorization', 'UserDefaults', 'Keychain', 'FileManager']:
            self.assertNotIn(forbidden, delta)
if __name__ == '__main__': unittest.main()
