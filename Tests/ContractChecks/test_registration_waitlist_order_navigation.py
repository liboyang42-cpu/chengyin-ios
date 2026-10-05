"""Offline structural contracts only; behavioral/Apple tests remain separate."""
import pathlib
import json
import re
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

    def test_flow_activity_fixture_satisfies_required_ticket_wire_fields(self):
        # Structural preflight, not a substitute for executing Swift Decodable/XCTest.
        source = (ROOT / 'Tests/CoreTests/RegistrationWaitlistOrderDestinationTests.swift').read_text()
        fixtures = [json.loads(raw) for raw in re.findall(r'Data\(#"(.*?)"#\.utf8\)', source)
                    if 'omsTicketList' in raw]
        self.assertEqual(len(fixtures), 1, 'Keep the flow activity fixture explicitly inspected')
        decoder = (ROOT / 'Core/ActivityDetail.swift').read_text()
        self.assertIn('id=try c.decode(Int.self,forKey:.id)', decoder)
        self.assertIn('name=try c.decode(String.self,forKey:.name)', decoder)
        fixture = fixtures[0]
        self.assertEqual(fixture['id'], 7)
        self.assertIsInstance(fixture['name'], str)
        self.assertEqual([ticket['id'] for ticket in fixture['omsTicketList']], [11, 12])
        for ticket in fixture['omsTicketList']:
            self.assertIs(type(ticket['id']), int)
            self.assertGreater(ticket['id'], 0)
            self.assertIsInstance(ticket['name'], str)
            self.assertTrue(ticket['name'])
            self.assertEqual(ticket['remainingInventory'], 5)
