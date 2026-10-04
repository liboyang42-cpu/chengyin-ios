"""Offline structural contracts only; behavioral/Apple tests remain separate."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class WaitlistOrderNavigationContracts(unittest.TestCase):
    def test_owned_reader_authority_is_explicit_and_not_participant_authority(self):
        host = (ROOT / 'App/SessionRegistrationSheet.swift').read_text()
        self.assertIn('orderReader:session.ownedOrderReader', host)
        view = (ROOT / 'App/RegistrationSheetView.swift').read_text()
        self.assertIn('orderReader: (any ProfileReading)? = nil', view)
        self.assertIn('.sheet(item: $orderDestination)', view)
        self.assertIn('flow.waitlistOrderDestination == destination', view)
        self.assertIn('.onChange(of: flow.waitlistReadKey)', view)
        self.assertIn('registration.waitlist.openOrder', view)
    def test_detail_has_no_lifecycle_or_creation_dispatch(self):
        view = (ROOT / 'App/RegistrationWaitlistOrderSheet.swift').read_text()
        self.assertIn('ProfileOrderDetailView(id: reader.destination.registrationID, reader: reader)', view)
        self.assertNotIn('lifecycleCoordinator:', view)
        adapter = (ROOT / 'Core/RegistrationWaitlistOrderDestination.swift').read_text()
        for field in ['order.id == destination.registrationID', 'order.memberID == destination.identity.accountID', 'order.ownerType == 2', 'order.ownerID == destination.scope.activityID', 'order.ticketID == destination.scope.ticketID', 'base.identity == readIdentity']:
            self.assertIn(field, adapter)
        for forbidden in ['URLSession', 'transport.send', 'create(', 'join(', 'cancel(', 'paymentSDK']:
            self.assertNotIn(forbidden, adapter)
    def test_claimed_states_do_not_recreate_when_inventory_reappears(self):
        flow = (ROOT / 'Core/RegistrationUIFlow.swift').read_text()
        self.assertIn('if let state = waitlistStatus?.state, [.claimed, .converted].contains(state) { return .intentAlreadySubmitted }', flow)
