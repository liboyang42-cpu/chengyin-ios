"""Bounded native read-only discovery source checks; not runtime evidence."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class CoopRelationDiscoveryChecks(unittest.TestCase):
    def source(self, path): return (ROOT / path).read_text()
    def test_existing_endpoint_limit_and_both_arrays(self):
        service = self.source('Core/CooperationFlowService.swift')
        model = self.source('Core/CoopRelationDiscovery.swift')
        self.assertIn('case .relations: return .object(["limit": .id(10)])', service)
        self.assertIn('case .relations: _ = try CoopRelationDiscovery(value)', service)
        for text in ['value["relations"].rows != nil', 'value["discovery"]["merchants"].rows', 'value["discovery"]["clubs"].rows']:
            self.assertIn(text, model)
        self.assertNotIn('URLRequest', model)
    def test_namespaces_partial_data_and_source_media(self):
        source = self.source('Core/CoopRelationDiscovery.swift')
        for text in ['case merchant(PublicMerchantOwnerID)', 'ownerMemberID.map(CoopRelationProfileRoute.merchant)', 'case .clubs: return .club(rowID)', '"coverImage" : "cover"', 'Self.text(value["logo"])', 'invalidMerchantCount', 'invalidClubCount']:
            self.assertIn(text, source)
        self.assertNotIn('legacyMerchantRowID', source)
        for text in ['canInvite', 'shareRate', 'compensation', 'originApplyId', 'URLSession']:
            self.assertNotIn(text, source)
    def test_exact_reader_session_snapshot_context_and_scopes(self):
        source = self.source('Core/CoopRelationDiscovery.swift')
        for text in ['loadedSession == reader.session', 'loadedReader == ObjectIdentifier(reader)', 'selection.snapshotID == snapshotID', 'selection.destinationScope == scope', 'selection.displayContext == context', 'selection.row.route == selection.route', 'value?.rows(selection.row.kind).contains(selection.row)', 'stamp == generation, reader.session == session']:
            self.assertIn(text, source)
    def test_normal_route_uses_existing_read_only_destinations(self):
        app = self.source('App/CoopRelationDiscoveryView.swift')
        root = self.source('App/QuestifyApp.swift')
        workbench = self.source('App/CooperationFlowWorkbench.swift')
        self.assertIn('if resource == .relations { CoopRelationDiscoveryEntry(reader: reader) }', workbench)
        self.assertIn('.environment(\\.cooperationRelationDiscovery, { AnyView(SessionCoopRelationDiscoveryView(session: session, reader: $0)) })', root)
        for text in ['PublicMerchantHomeView(target: .ownerMemberID(owner)', 'ClubDetailView(id: id, reader: reader)', 'value.memberId == owner.rawValue', 'session.contentDetailRevision == scope.contentRevision', 'value.id == id', 'guard loadedKey == key', 'guard canOpen(choice) else { return }', 'profiles.isCurrent()', '.navigationDestination(item: $selection)']:
            self.assertIn(text, app)
        for text in ['AsyncImage(', 'URLSession', 'CoopFlowMutation', 'CoopFlowInvite', 'actionCoordinator:', 'management:', 'community:', 'ProductionApproval(']:
            self.assertNotIn(text, app)
    def test_scoped_unauthorized_callbacks_are_fenced_before_expiration(self):
        flow = self.source('Core/CooperationFlowService.swift')
        club = self.source('Core/ClubReading.swift')
        app = self.source('App/CoopRelationDiscoveryView.swift')
        model = self.source('Core/CoopRelationDiscovery.swift')
        self.assertIn('guard isCurrent(), current() == session, !Task.isCancelled else', flow)
        self.assertIn('guard isCurrent() else { throw CancellationError() }\n            guard !Task.isCancelled, currentSession() == snapshot else', club)
        self.assertIn('self.requestGeneration == request', app)
        self.assertIn('stamp == self.generation && isCurrent()', model)
        self.assertIn('key == captured && (profiles?.isCurrent() ?? true)', app)
        self.assertIn('selection?.id == choice.id && canOpen(choice)', app)
        self.assertIn('current() && selectionCurrent()', app)
        self.assertIn('clubReader.clubDetail(id: id, isCurrent: isCurrent)', app)
        self.assertIn('clubReader.clubMembers(id: id, isCurrent: isCurrent)', app)

    def test_bilingual_strings_and_fixture_is_synthetic(self):
        keys = ['kind', 'merchants', 'clubs', 'partial', 'emptyMerchants', 'emptyClubs', 'unavailable', 'image', 'topic', 'chapter']
        catalog = json.loads(self.source('Resources/Localizable.xcstrings'))['strings']
        for key in keys:
            self.assertEqual(set(catalog['cooprelation.' + key]['localizations']), {'en', 'zh-Hans'})
        fixture = self.source('App/CoopRelationDiscoveryFixture.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('https://relation-fixture.invalid/', fixture)
        self.assertNotIn('URLSession', fixture)

if __name__ == '__main__': unittest.main()
