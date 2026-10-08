"""Native source contracts only; these do not execute Swift or Apple UI tests."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SearchMapRefreshContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.state = (ROOT / 'Core/SearchMapRefresh.swift').read_text()
        cls.view = (ROOT / 'App/SearchMapExplorerView.swift').read_text()
        cls.core_tests = (ROOT / 'Tests/CoreTests/SearchMapRefreshTests.swift').read_text()
        cls.app_tests = (ROOT / 'Tests/AppUnitTests/SearchMapRefreshTests.swift').read_text()

    def test_refresh_is_an_explicit_action_not_an_automatic_retry(self):
        start = self.view.split('private func startRefresh()', 1)[1].split('private func acceptsRefresh', 1)[0]
        self.assertIn('refresh.begin(', start)
        self.assertIn('guard refreshOwnerActive,', start)
        self.assertIn('loading = false; refreshOwnerActive = false }', self.view)
        self.assertIn('refreshOwnerActive = true; readOwner.activate()', self.view)
        self.assertIn('readOwner.start { await performRefresh(ticket) }', start)
        for forbidden in ['reader.selectManualArea(', 'invalidate()', 'Task.sleep', 'Timer', 'onReceive']:
            self.assertNotIn(forbidden, start)
        self.assertEqual(self.view.count('await reader.citySearch(ticket.query)'), 1)
        self.assertIn('Button { startRefresh() }', self.view)

    def test_refresh_and_pagination_are_mutually_exclusive(self):
        self.assertIn('guard pending == nil, !pagination.isLoading', self.state)
        self.assertIn('!loading, !refresh.isLoading, visibleCityResults != nil', self.view)
        self.assertIn('.disabled(loading || pagination.isLoading || !reader.isConfigured)', self.view)
        self.assertIn('.disabled(refresh.isLoading)', self.view)
        self.assertIn('.disabled(loading || refresh.isLoading || !reader.isConfigured)', self.view)

    def test_every_refresh_completion_matches_current_query_scope_and_area_revision(self):
        for fragment in ['pending?.ticket == ticket', 'ticket.query == query', 'ticket.scope == scope',
                         'ticket.manualAreaRevision == manualAreaRevision']:
            self.assertIn(fragment, self.state)
        perform = self.view.split('private func performRefresh(', 1)[1].split('private func applyRefresh(', 1)[0]
        self.assertEqual(perform.count('guard acceptsRefresh(ticket) else { return }'), 3)
        self.assertIn('defer { refresh.cancel(ticket) }', perform)
        self.assertIn('!Task.isCancelled && reader.isConfigured && refresh.accepts', self.view)

    def test_fresh_query_and_dismissal_retire_tickets(self):
        self.assertIn('readOwner.cancel(); refresh.invalidate(); gate.invalidate(); pagination.invalidate()', self.view)
        self.assertIn('readOwner.deactivate(); refresh.cancelPending(); pagination.cancelPending()', self.view)
        self.assertIn('public mutating func invalidate() { self = SearchMapRefresh() }', self.state)
        self.assertIn('if pending?.ticket == ticket { pending = nil }', self.state)
        start = self.view.split('private func startLoad()', 1)[1].split('private func startRefresh()', 1)[0]
        self.assertIn('reader.selectManualArea(area)', start)
        self.assertIn('invalidate()', start)

    def test_only_transient_failures_retain_layers(self):
        self.assertIn('result.activityFailure == .unavailable && previous.result.activityFailure == nil', self.state)
        self.assertIn('result.nodeFailure == .unavailable && previous.result.nodeFailure == nil', self.state)
        self.assertIn('result.nodeFailure == nil ? result.nodes : []', self.state)
        self.assertIn('result.activityFailure == nil ? result.activities : []', self.state)
        self.assertIn('case .unauthorized, .notConfigured, .invalidConfiguration, .invalidRequest:', self.view)
        self.assertIn('invalidate(); issue = SearchMapIssue.key(error)', self.view)
        self.assertIn('catch is CancellationError { }', self.view)

    def test_refresh_replaces_successful_layer_and_preserves_failed_page_continuation(self):
        self.assertIn('var pages = previous.pagination', self.state)
        self.assertIn('if !retainedActivities {', self.state)
        self.assertIn('pages.reset(query: ticket.query', self.state)
        self.assertNotIn('pages.begin(', self.state)
        self.assertNotIn('pages.fail(', self.state)
        self.assertIn('cityResults = update.result; pagination = update.pagination', self.view)

    def test_retained_labels_are_visible_before_map_and_selected_card(self):
        self.assertLess(self.view.index('if visibleCityResults != nil { refreshControls }'), self.view.index('SearchMapCanvas('))
        for key in ['retainedActivities', 'retainedNodes', 'previousWhileLoading', 'loading', 'retry', 'refresh']:
            self.assertIn('mapRefresh.' + key, self.view)
        self.assertIn('if let selectedPin, !pins.contains(where: { $0.id == selectedPin }) { self.selectedPin = nil }', self.view)
        self.assertIn('destination(.activity(row.id))', self.view)
        self.assertIn('destination(.topic(topic))', self.view)

    def test_all_new_copy_is_bilingual(self):
        strings = json.loads((ROOT / 'Resources/SearchMapRefreshLocalizations.fragment.json').read_text())
        used = set(re.findall(r'"(mapRefresh\.[A-Za-z]+)"', self.view))
        self.assertEqual(used, set(strings))
        for value in strings.values():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(x['stringUnit']['value'] for x in value['localizations'].values()))

    def test_race_layer_and_interleaving_tests_are_authored(self):
        for name in ['testRepeatRefreshRetiresOldSuccessFailureAndCancellation',
                     'testFailedRefreshAllowsLoadMoreThenRetrySuccessReplacesAccumulatedPages',
                     'testPageFailureSurvivesRefreshFailureAndIsIndependentOfRefreshRetry',
                     'testChangedQueryScopeAndAreaRevisionRejectLateCompletion',
                     'testAuthorizationOrConfigurationFailuresNeverRetainAffectedLayer',
                     'testSuccessfulEmptyRefreshClearsOldRowsPinsAndContinuation',
                     'testFilteredEmptyFullPageStillContinuesAfterSuccessfulRefresh']:
            self.assertIn(name, self.core_tests)
        for name in ['testExplicitRefreshUsesExistingTwoReadsWithoutReselectingManualArea',
                     'testSessionOrAreaChangeDiscardsLateRefreshAndCannotExpireNewAccount',
                     'testDismissalBeforeQueuedRefreshPreventsDispatchAndRetryGetsNewTicket',
                     'testOwnerCancellationSuppressesNoncooperativeLateRefresh']:
            self.assertIn(name, self.app_tests)

    def test_refresh_has_no_new_location_provider_or_write_capability(self):
        for source in [self.state, self.view]:
            for forbidden in ['CLLocationManager', 'requestAlwaysAuthorization', 'startUpdatingLocation',
                              'MKDirections(', '/presence', '/reveal', '/complete', '/favorite', 'URLSession', 'UserDefaults']:
                self.assertNotIn(forbidden, source)

if __name__ == '__main__':
    unittest.main()
