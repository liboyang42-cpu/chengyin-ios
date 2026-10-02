import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def source(path): return (ROOT / path).read_text()

class LiveRoamContracts(unittest.TestCase):
    def test_production_injection_is_default_off_not_a_nil_only_factory(self):
        deps = source('App/NativeRoamLiveDependencies.swift')
        self.assertIn('static var dormant: Self { .init() }', deps)
        self.assertIn('static func approved', deps)
        self.assertIn('RuntimeNativeLocationProvider(enabled: approval.foregroundLocation)', deps)
        app = source('App/AppSession.swift')
        self.assertIn('self.roamLiveDependencies = roamLiveDependencies ?? .dormant', app)
        self.assertIn('approval.allows(snapshot.identity, api: api)', app)
        self.assertIn('RoamLiveService(api: api, approval: approval', app)
        self.assertIn('retainedRoamLiveSession?.invalidate()', app)
    def test_write_ahead_and_keyed_bootstrap_are_present(self):
        service = source('Core/RoamLiveService.swift')
        self.assertIn('fields["clientSessionKey"] = clientSessionKey', service)
        self.assertIn('currentSession() == captured', service)
        self.assertIn('result.sessionId == sessionID', service)
        controller = source('Core/RoamLiveSessionController.swift')
        self.assertLess(controller.index('draft.pendingWrite = .reveal; try persist(draft)'), controller.index('service!.reveal('))
        self.assertLess(controller.index('draft.pendingWrite = .finish; try persist(draft)'), controller.index('service!.finish('))
        self.assertIn('fact.hasCompleteSettlement, record.pendingTiles.isEmpty', controller)
        self.assertIn('try history.prependSettled(archived, fact: fact)', controller)
    def test_precise_tracking_is_ephemeral_and_presence_ttl_is_honest(self):
        data = source('Core/RoamLiveContracts.swift').split('public struct RoamLiveRecord:')[1].split('@MainActor public final class RoamLiveJournal')[0]
        for value in ['var track:', 'var fix:', 'var token:', 'var latitude:', 'var longitude:']:
            self.assertNotIn(value, data)
        view = source('App/RoamLiveSessionView.swift')
        self.assertIn('owner.setForeground(value == .active)', view)
        self.assertIn('.onDisappear { owner.pause() }', view)
        catalog = json.loads(source('Resources/Localizable.xcstrings'))['strings']
        self.assertIn('five minutes', catalog['roam.live.presencePrivacy']['localizations']['en']['stringUnit']['value'])
    def test_registration_shop_domain_is_not_node_id(self):
        service = source('Core/RoamLiveService.swift')
        self.assertIn('post("api/map/nearby"', service)
        self.assertIn('"radius": "800", "limit": "20"', service)
        controller = source('Core/RoamLiveSessionController.swift')
        self.assertIn('sourceType: 2, sourceID: shop.id', controller)
        self.assertNotIn('sourceID: shop.nodeId', controller)
    def test_roam_nearby_reads_owned_teams_before_success(self):
        host = source('App/RoamNearbyTeamsView.swift')
        self.assertIn('await reader.loadTeams()', host)
        self.assertIn('if let message = reader.messageKey { failureKey = message }', host)
        self.assertIn('joinedTeams: rows', host)
        self.assertIn('SessionRoamNearbyTeamsView()', source('App/QuestifyApp.swift'))
    def test_share_is_local_preview_then_explicit_system_gesture(self):
        view = source('App/RoamHistoryShareView.swift')
        self.assertIn('ImageRenderer(content:', view)
        self.assertIn('ShareLink(item:', view)
        self.assertIn('private var includeRoute = false', view)
        for forbidden in ['URLSession', 'PHPhotoLibrary', 'requestAuthorization', 'api/', 'http://', 'https://']:
            self.assertNotIn(forbidden, view)
    def test_bilingual_copy_for_all_rendered_live_and_share_keys(self):
        catalog = json.loads(source('Resources/Localizable.xcstrings'))['strings']
        for path in ['App/RoamLiveSessionView.swift','App/RoamHistoryShareView.swift']:
            text = re.sub(r'\.accessibilityIdentifier\("[^"]+"\)', '', source(path))
            for key in re.findall(r'"(roam\.(?:live|share)\.[A-Za-z]+)"', text):
                self.assertIn(key, catalog)
                self.assertEqual(set(catalog[key]['localizations']), {'en','zh-Hans'})

if __name__ == '__main__': unittest.main()
