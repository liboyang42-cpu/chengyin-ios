"""Static role-view privacy and integration contracts; not Apple/runtime proof."""
import json,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class JourneyRoleViewChecks(unittest.TestCase):
    @classmethod
    def setUpClass(c):
        c.domain=(ROOT/'Core/JourneyRoleView.swift').read_text()
        c.coordinator=(ROOT/'Core/JourneyRoleViewCoordinator.swift').read_text()
        c.service=(ROOT/'Core/JourneyContentService.swift').read_text()
        c.view=(ROOT/'App/JourneyRoleViewSection.swift').read_text()
    def test_only_singular_server_projection(self):
        self.assertIn('encounter["roleView"]',self.domain)
        self.assertNotIn('encounter["roleViews"]',self.domain)
        for token in ['TemplateAdvancedDraft','advancedConfigJson','memberIndex','teamOrder']:self.assertNotIn(token,self.domain+self.coordinator+self.view)
    def test_exact_server_role_values(self):
        self.assertIn('case a = "A", b = "B", solo = "SOLO", missing',self.domain)
        self.assertIn('assignment != .missing',self.domain)
    def test_assignment_privacy_cardinality(self):
        self.assertIn('parsed.count == 1, ids == [role]',self.domain)
        self.assertIn('parsed.count == 2, ids == ["A", "B"]',self.domain)
        self.assertIn('guard rows.isEmpty',self.domain)
        self.assertIn('ids.insert(id).inserted',self.domain)
    def test_node_run_version_binding(self):
        for token in ['node == expectedNodeID','run > 0','version >= 0']:self.assertIn(token,self.domain)
    def test_activity_scope_is_explicit_read_only(self):
        method=self.service.split('public func roleView(')[1].split('public func act(')[0]
        self.assertIn('query["activityId"] = String(id)',method)
        self.assertIn('guard id == topicID',method)
        self.assertIn('capability: .reads',method)
        self.assertIn('"api/play/encounter"',method)
        self.assertNotIn('form:',method);self.assertNotIn('json:',method)
    def test_session_and_generation_fences(self):
        self.assertIn('generation == stamp, currentSession() == session',self.coordinator)
        self.assertIn('projection = nil; status = .idle; loaded = false',self.coordinator)
        self.assertIn('service.readsEnabled',self.coordinator)
        self.assertNotIn('UserDefaults',self.coordinator)
    def test_player_ui_has_no_role_picker(self):
        self.assertNotIn('Picker(',self.view)
        self.assertNotIn('setRole',self.view)
        self.assertIn('ForEach(projection.views)',self.view)
        self.assertIn('.privacySensitive()',self.view)
    def test_plain_text_and_no_markup(self):
        for token in ['Text(verbatim: view.title)','Text(verbatim: view.body)','Text(verbatim: item.text)']:self.assertIn(token,self.view)
    def test_stable_host_load_and_close(self):
        host=(ROOT/'App/PlayExperienceView.swift').read_text()
        self.assertIn('await journey?.roleContent.load(expectedRunID:',host)
        self.assertIn('journey?.roleContent.close()',host)
        self.assertIn('JourneyRoleViewSection(model: model.roleContent)',(ROOT/'App/PlayJourneyContentViews.swift').read_text())
    def test_existing_check_reviews_remain_independent(self):
        check=(ROOT/'Core/JourneyCheckCoordinator.swift').read_text()
        self.assertIn('public let roleContent: JourneyRoleViewCoordinator',check)
        self.assertIn('guard available, review == approved',check)
        self.assertIn('roleContent.synchronize()',check)
        self.assertNotIn('service.act',self.coordinator)
    def test_bilingual_catalog(self):
        fragment=json.loads((ROOT/'Resources/RoleViewLocalizations.fragment.json').read_text())
        self.assertEqual(len(fragment),13)
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for key in fragment:
            for lang in ['en','zh-Hans']:self.assertTrue(catalog[key]['localizations'][lang]['stringUnit']['value'])
    def test_synthetic_scenarios_and_ui_acceptance_authored(self):
        fixture=(ROOT/'App/JourneyContentFixtureSupport.swift').read_text();ui=(ROOT/'Tests/AppUITests/JourneyRoleViewFlowTests.swift').read_text()
        for scenario in ['roleA','roleB','roleSolo','roleMissing']:self.assertIn('"'+scenario+'"',fixture)
        self.assertIn('roleMismatch',ui);self.assertIn('Must not render A',ui);self.assertIn('Must not render B',ui)
