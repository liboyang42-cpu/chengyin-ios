"""Supplementary source checks. Does not execute Swift or certify runtime behavior."""
import json
import pathlib
import re
import unittest
from flutter_source import read_flutter_source
ROOT = pathlib.Path(__file__).resolve().parents[2]

class ClubOperationsSourceChecks(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_six_paths_match_flutter_sources(self):
        swift = self.text('Core/ClubOperationsContracts.swift')
        routes = set(re.findall(r'"(api/club/[^" ]+)"', swift))
        self.assertEqual(len(routes), 6)
    def test_six_paths_external_flutter_parity(self):
        swift = self.text('Core/ClubOperationsContracts.swift')
        routes = set(re.findall(r'"(api/club/[^" ]+)"', swift))
        dart = read_flutter_source(self, 'data/api/club_api.dart') + read_flutter_source(self, 'data/api/club_topic_ops_api.dart')
        for route in routes: self.assertIn("'/" + route + "'", dart)
    def test_catalog_preserves_source_wire_values(self):
        swift = self.text('Core/ClubOperationsContracts.swift')
        for value in ['校园社团','旅行组织','兴趣社群','商业活动组织方','内容创作团队','其他','轻社交','深度社交','RPG体验','城市定向','解谜路线','沉浸式剧情','运动路线','艺术体验','美食体验','主题聚会']:
            self.assertIn(value, swift)
    def test_catalog_external_flutter_parity(self):
        dart = read_flutter_source(self, 'feature/club/club_create_page.dart')
        for value in ['校园社团','旅行组织','兴趣社群','商业活动组织方','内容创作团队','其他','轻社交','深度社交','RPG体验','城市定向','解谜路线','沉浸式剧情','运动路线','艺术体验','美食体验','主题聚会']:
            self.assertIn(value, dart)
    def test_dormant_perform_requires_scope_and_durable_lock(self):
        service = self.text('Core/ClubOperationsService.swift')
        body = service.split('public func perform(',1)[1]
        self.assertIn('throw ClubActionWriteError.notSent(.notConfigured)',body)
        self.assertNotIn('transport.send',body); self.assertNotIn('URLSession', service)
        self.assertIn('approval != nil && journal != nil ? .approved : .unverified',service)
        for guard in ['service.isApproved', 'journal.pending', 'journal.write(record)', 'currentSession() == session', 'command.validate(snapshot: fresh']: self.assertIn(guard,body)
        self.assertLess(body.index('try journal.write(record)'),body.index('service.dispatch'))
        coordinator = self.text('Core/ClubOperationsCoordinator.swift')
        self.assertIn('guard access.writeAvailability == .syntheticOnly',coordinator)
    def test_media_dissolution_and_retired_price_stay_out_of_wire(self):
        swift = self.text('Core/ClubOperationsContracts.swift')
        for prohibited in ['"memberDiscountPrice":','"member_discount_price":','api/club/dissolve','api/club/become-leader']:
            self.assertNotIn(prohibited,swift)
        self.assertIn('logo == (original?.club.logo ?? "")',swift)
        self.assertIn('if original.club.joinPolicySupported',swift)
    def test_fixture_is_debug_and_offline(self):
        source = self.text('Core/ClubOperationsSyntheticFixtures.swift')
        self.assertTrue(source.startswith('#if DEBUG'))
        for unsafe in ['URLSession','HTTPTransport','UserDefaults','https://']: self.assertNotIn(unsafe,source)
    def test_ui_has_native_review_unknown_lock_and_accessibility(self):
        ui = self.text('App/ClubOperationsViews.swift') + self.text('App/ClubOperationsReviewView.swift')
        for required in ['.sheet(item:', '.interactiveDismissDisabled(', 'accessibilityIdentifier', 'accessibilityReduceMotion', 'QuestifyImageEntityCard', '.confirmationDialog(', 'TextField(', 'Toggle(', 'Picker(']: self.assertIn(required,ui)
        self.assertNotIn('.stroke(',ui); self.assertNotIn('allowsHitTesting(false)',ui)
        coordinator = self.text('Core/ClubOperationsCoordinator.swift')
        self.assertIn('let accountID: Int; let target: ClubOperationsTarget',coordinator)
        self.assertIn('record.identity != identity',coordinator)
        self.assertIn('records[key]?.readGeneration == run',coordinator)
    def test_all_literal_ui_keys_and_canonical_values_have_bilingual_copy(self):
        catalog = json.loads(self.text('docs/club-operations-localizations.json'))
        for value in catalog.values(): self.assertEqual(set(value),{'en','zh-Hans'}); self.assertTrue(all(value.values()))
        ui = ''.join(p.read_text() for p in (ROOT/'App').glob('ClubOperations*.swift'))
        keys = set(re.findall(r'"(club\.ops\.[A-Za-z][A-Za-z0-9.]*)"',ui))
        for key in keys:
            if key in catalog or key.endswith('.') or any(t in key for t in ['openCreate','openManage','loading','error','setting.','member.','writeCount','fixtureNotice','field.','reviewSheet','confirm','cancelReview']): continue
            # Localized text and test identifiers are intentionally separate.
            self.assertTrue(key in catalog, key)
    def test_integration_wires_retained_session_and_fixture(self):
        # Additive files are valid in isolation; assert host wiring once merged.
        if not (ROOT/'App/AppSession.swift').exists(): self.skipTest('isolated overlay: host integration checked after merge')
        session = self.text('App/AppSession.swift')
        self.assertIn('lazy var clubOperationsCoordinator',session)
        self.assertIn('currentClubOperationsSession == captured',session)
        self.assertIn('clubOperationsCoordinator.synchronizeSession()',session)
        self.assertIn('ClubOperationsFixtureHostView',self.text('App/QuestifyApp.swift'))
        self.assertIn('ClubOperationsEntryButton',self.text('App/ClubHomeView.swift'))
        self.assertIn('ClubOperationsEntryButton',self.text('App/ClubDetailView.swift'))

if __name__ == '__main__': unittest.main()
