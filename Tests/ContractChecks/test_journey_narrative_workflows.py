import json
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class JourneyNarrativeNativeContracts(unittest.TestCase):
    def test_normal_session_host_and_per_node_entry(self):
        host = (ROOT/'App/SessionPlayRuntimeView.swift').read_text()
        view = (ROOT/'App/PlayExperienceView.swift').read_text()
        session = (ROOT/'App/AppSession.swift').read_text()
        self.assertIn('narrativeModel: { session.journeyNarrative(scope: scope, topicID: model.snapshot?.result.topicID, query: $0) }', host)
        for query in ['narrativeLink(.casebook)', 'narrativeLink(.backpack)', 'narrativeLink(.stage(chapterID: chapter.id)', 'narrativeLink(.ending)', 'narrativeModel?(.questions(nodeID: id))']:
            self.assertIn(query, view)
        self.assertIn('factory.journeyNarrativeService()', session)
        self.assertIn('journal: journeyNarrativeJournal', session)
        self.assertIn('currentPlayRuntimeSession', session)

    def test_defaults_are_configuration_off_and_transport_remains_protected(self):
        config = (ROOT/'Core/RuntimeDependencyConfiguration.swift').read_text()
        service = (ROOT/'Core/JourneyNarrativeService.swift').read_text()
        self.assertIn('journeyAsks: Bool = false', config)
        self.assertIn('asksEnabled: accepted?.journeyAsks == true', config)
        self.assertIn('readsEnabled: Bool = false, asksEnabled: Bool = false', service)
        self.assertNotIn('URLSession', service)
        self.assertIn('current() == captured', config)
        self.assertIn('configuration.endpoints.paths.contains', config)

    def test_source_domains_not_ids_from_ui_or_invented_call_choices(self):
        code = (ROOT/'Core/JourneyNarrativeContracts.swift').read_text()
        self.assertIn('activityID = 0', code)
        self.assertIn('guard id == topicID', code)
        self.assertIn('"activityId": String(activityID)', code)
        self.assertIn('"^[A-Za-z0-9_-]{1,32}$"', code)
        self.assertIn('answer = asked ?', code)
        self.assertNotIn('api/play/journey/call', (ROOT/'Core/JourneyNarrativeService.swift').read_text())

    def test_write_reservation_precedes_dispatch_and_readback_is_not_retry(self):
        code = (ROOT/'Core/JourneyNarrativeCoordinator.swift').read_text()
        self.assertLess(code.index('try journal.save(saved'), code.index('let result = try await service.ask'))
        self.assertIn('fresh == approved.projection', code)
        self.assertIn('currentSession() == captured', code)
        self.assertIn('saved.subtracting(projection.questions.filter(\\.asked).map(\\.id))', code)
        self.assertEqual(code.count('service.ask('), 1)
        self.assertIn('journal?.isDurable == true', code)

    def test_topic_customer_filters_are_normal_ui_and_distinct_from_crm(self):
        code = (ROOT/'App/ClubGovernanceViews.swift').read_text()
        self.assertIn('Picker("club.gov.filter", selection: $topicCustomerFilter)', code)
        self.assertIn('if operation == .topicCustomers { options = topicCustomerFilter.options }', code)
        self.assertIn('fields: ["soldCount", "pendingCount", "verifiedCount"]', code)
        self.assertIn('.onChange(of: filter)', code)
        contracts = (ROOT/'Core/ClubGovernanceContracts.swift').read_text()
        self.assertIn('case all = "", pending, contacted, verified', contracts)

    def test_new_display_keys_are_bilingual(self):
        catalog = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        keys = set()
        for path in [ROOT/'App/JourneyNarrativeView.swift', ROOT/'Core/JourneyNarrativeCoordinator.swift', ROOT/'Core/JourneyNarrativeContracts.swift']:
            keys |= set(re.findall(r'"(journey\.record\.[A-Za-z0-9_]+)"', path.read_text()))
        keys |= {'journey.record.relation.' + s for s in ['ally','neutral','guarded']}
        keys |= {'journey.record.reward.' + s for s in ['claimed','pending','none']}
        keys |= {'club.gov.topicFilter.' + s for s in ['all','pending','contacted','verified']}
        for key in keys:
            # Accessibility-only identifiers are not displayed strings.
            if key in {'journey.record.error','journey.record.pending','journey.record.confirm'}: continue
            for language in ['en','zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][language]['stringUnit']['value'])

@unittest.skipUnless(os.getenv('CHENGYIN_BACKEND_SOURCE_ROOT'), 'Optional current backend source not supplied; native checks still run')
class JourneyNarrativeCurrentBackendContracts(unittest.TestCase):
    def test_routes_and_exact_run_fallback_contract(self):
        root = Path(os.environ['CHENGYIN_BACKEND_SOURCE_ROOT'])
        api = root/'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api'
        for filename, routes in {
            'ApiPlayJourneyReadController.java': ['/casebook','/backpack'],
            'ApiPlayJourneyController.java': ['/stage-end','/ending'],
            'ApiPlayJourneyActionController.java': ['/ask'],
        }.items():
            code=(api/filename).read_text()
            self.assertIn('@RequestMapping("/api/play/journey")', code)
            for route in routes: self.assertIn('Mapping("'+route+'")', code)
            self.assertIn('activityId', code)
        scope=(root/'chengyinhub-system/src/main/java/com/chengyinhub/business/service/support/TopicRouteSessionScope.java').read_text()
        self.assertIn('if (activityId == null)', scope)
        self.assertIn('selectByOwner(activityId, topicId, memberId, "default")', scope)
        runtime=(root/'chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/TopicRouteRuntimeServiceImpl.java').read_text()
        self.assertIn('Pattern.compile("[A-Za-z0-9_-]{1,32}")', runtime)
        self.assertIn('receipt.put("questionId", qid)', runtime)
        encounter=(root/'chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/PlayEncounterServiceImpl.java').read_text()
        for field in ['nodeId','runId','stateVersion','arrived','locked','enter']: self.assertIn('view.put("'+field+'"', encounter)
        self.assertIn('if (asked) item.put("a"', encounter)

if __name__ == '__main__': unittest.main()
