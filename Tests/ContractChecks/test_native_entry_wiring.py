"""Offline routing/privacy assertions. These do not execute Swift or certify UI visuals."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class NativeEntryWiringChecks(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_reply_entry_comes_only_from_loaded_received_application(self):
        source = self.read('App/CooperationFlowWorkbench.swift')
        begin = source.index('case .receivedApplications:', source.index('private func sourceActions'))
        reply = source[begin:source.index('case .registrations:', begin)]
        self.assertIn('loadedSession == reader.session', reply)
        self.assertIn('CoopFlowInvitationContext(receivedApplication: row, session: loadedSession)', reply)
        self.assertIn('inviteContext = context', reply)
        self.assertIn('CoopFlowInviteEditor(reader: reader, context: context)', source)
        self.assertIn('.onChange(of: reader.session) { _, _ in inviteContext = nil; refresh = UUID() }', source)
    def test_editor_is_single_sheet_with_push_review_and_explicit_draft_discard(self):
        source = self.read('App/CooperationFlowEditors.swift')
        source = source[source.index('@MainActor struct CoopFlowInviteEditor'):source.index('struct CoopFlowReviewEditor:')]
        self.assertIn('context.invitation(', source)
        self.assertIn('currentSession: reader.session', source)
        self.assertIn('NavigationLink("coopflow.reviewAction")', source)
        self.assertIn('.interactiveDismissDisabled(hasDraft)', source)
        self.assertIn('.confirmationDialog(', source)
        self.assertIn('role: .cancel', source)
        self.assertIn('.scrollDismissesKeyboard(.interactively)', source)
        self.assertNotIn('.sheet(', source)
        self.assertNotIn('execute(', source)
    def test_nearby_is_reachable_without_location_or_network_side_effect(self):
        source = self.read('App/CooperationFlowWorkbench.swift')
        self.assertIn('NavigationLink { CoopFlowNearbyGate(reader: reader) }', source)
        self.assertNotIn('authorizedCoordinates', source)
        gate = source[source.index('@MainActor struct CoopFlowNearbyGate'):source.index('struct CoopFlowSafetyNotice')]
        for banned in ['CLLocationManager', 'requestWhenInUseAuthorization', 'reader.read(', 'URLSession', '.task(']:
            self.assertNotIn(banned, gate)
        for key in ['coopflow.nearby.purpose', 'coopflow.nearby.unavailable', 'coopflow.nearby.privacy']:
            self.assertIn(key, gate)
    def test_marketing_visibility_is_not_a_service_grant(self):
        self.assertIn('isSourceVisible: true', self.read('App/MerchantHomeView.swift'))
        self.assertIn('gates: .init(reads: false, insight: false, settlement: false), locks: nil', self.read('App/AppSession.swift'))
        self.assertIn('iOSCheckoutAvailable: Bool { false }', self.read('Core/MerchantMarketingModels.swift'))
        self.assertIn('case dashboard, insight, subscriptions, predictions', self.read('Core/MerchantMarketingCoordinator.swift'))
    def test_all_added_copy_is_bilingual_and_catalog_matches(self):
        fragment = json.loads(self.read('Resources/NativeEntryWiringLocalizations.fragment.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, value in fragment.items():
            self.assertEqual(catalog[key], value, key)
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'}, key)
            for entry in value['localizations'].values(): self.assertTrue(entry['stringUnit']['value'].strip(), key)
