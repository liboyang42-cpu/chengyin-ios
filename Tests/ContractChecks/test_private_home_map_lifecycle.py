"""Independent source guards; authored Apple tests still require an Apple executor."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PrivateHomeMapLifecycleContracts(unittest.TestCase):
    def text(self, name):
        return (ROOT / name).read_text()

    def test_actual_account_destination_keys_all_private_view_state_to_owner(self):
        source = self.text('App/PrivateHomeView.swift')
        self.assertIn('PrivateHomeAccountLink(coordinator: privateHomeCoordinator)', self.text('App/AccountView.swift'))
        wrapper = source.split('@MainActor struct PrivateHomeView: View {', 1)[1].split('@MainActor private struct PrivateHomeOwnerForm:', 1)[0]
        self.assertIn('PrivateHomeOwnerForm(model: model, mapAdapter: mapAdapter)', wrapper)
        self.assertIn('.id(ObjectIdentifier(model))', wrapper)
        self.assertNotIn('@State', wrapper)
        self.assertIn('.id(picker.selection.generation)', source)

    def test_final_confirmation_rechecks_map_source_inside_task_before_owner_dispatch(self):
        source = self.text('App/PrivateHomeView.swift')
        self.assertIn('Task {\n                            guard picker.authorizeOwnerConfirmation() else { return }\n                            await model.confirm()', source)
        picker = self.text('App/PrivateHomeMapPicker.swift')
        self.assertIn('reviewedRequestID = owner.review?.requestId', picker)
        self.assertIn('reviewedSource = sourceAtOpen', picker)
        gate = picker.split('func authorizeOwnerConfirmation() -> Bool {', 1)[1].split('func close()', 1)[0]
        self.assertIn('owner.review?.requestId == reviewedRequestID', gate)
        self.assertIn('adapter.approvedSource == reviewedSource', gate)
        self.assertIn('owner.cancelReview()', gate)
        self.assertNotIn('journal.', gate)
        self.assertNotIn('service.', gate)

    def test_same_route_fixture_has_owner_replacement_late_delivery_and_revocation_probes(self):
        fixture = self.text('App/PrivateHomeFixtureHost.swift')
        self.assertIn('PrivateHomeAccountLink(coordinator: model, mapAdapter: mapAdapter)', fixture)
        ui = self.text('Tests/AppUITests/PrivateHomeMapPickerFlowTests.swift')
        for name in ['testSameAccountRouteReplacementClearsManualFields',
                     'testSameAccountRouteReplacementDiscardsPickerAndLateCallback',
                     'testSourceRevocationAfterReviewBlocksFinalConfirmation']:
            self.assertIn('func ' + name, ui)
        self.assertIn('record("requests", "0", app)', ui)
