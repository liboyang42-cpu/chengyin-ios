"""Focused source contracts only. This does not compile or execute Swift or iOS UI."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SearchMapPaginationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.state = (ROOT/'Core/SearchMapPagination.swift').read_text()
        cls.service = (ROOT/'Core/SearchMapService.swift').read_text()
        cls.reader = (ROOT/'Core/SearchMapReading.swift').read_text()
        cls.view = (ROOT/'App/SearchMapExplorerView.swift').read_text()
        cls.fixture = (ROOT/'App/SearchMapFixtureSupport.swift').read_text()
        cls.core_tests = (ROOT/'Tests/CoreTests/SearchMapPaginationTests.swift').read_text()
        cls.app_tests = (ROOT/'Tests/AppUnitTests/SearchMapPaginationTests.swift').read_text()

    def test_existing_activity_route_and_first_page_size_are_preserved(self):
        page = self.service.split('public func cityActivityPage(', 1)[1].split('public func nearby(', 1)[0]
        self.assertIn('pageSize: 50', page)
        self.assertIn('fields["pageNum"] = String(page)', page)
        self.assertIn('form("api/activity/list", fields: fields, token: token)', page)
        self.assertNotIn('api/city/nodes', page)
        for key in ['"longitude"', '"latitude"', '"sort_type"']:
            self.assertIn(key, page)
        for key in ['"minPrice"', '"maxPrice"', '"startDate"', '"endDate"', '"cityRole"', '"tag"']:
            self.assertNotIn(key, page)
        self.assertIn('self.cityActivityPage(query, page: 1, token: token)', self.service)

    def test_optional_total_and_raw_count_are_separate_from_filtering(self):
        self.assertIn('ActivityListResponse(from: decoder).rows', self.state)
        self.assertIn('decodeIfPresent(Int.self, forKey: .total)', self.state)
        self.assertIn('rawCount: response.rows.count, serverTotal: response.total', self.service)
        continuation = self.state.split('public var hasMore:', 1)[1].split('public static func validPageNumber', 1)[0]
        self.assertNotIn('rows.count', continuation)
        for fragment in ['guard rawCount > 0', 'if let serverTotal', '(pageNumber - 1) * Self.pageSize', 'rawCount >= Self.pageSize']:
            self.assertIn(fragment, continuation)

    def test_ticket_scope_single_flight_and_same_page_retry(self):
        self.assertIn('inFlight == nil, let page = nextPage', self.state)
        self.assertIn('guard inFlight == ticket else { return false }', self.state)
        self.assertIn('guard page.pageNumber == ticket.page', self.state)
        failure = self.state.split('public mutating func fail(', 1)[1]
        self.assertNotIn('rows =', failure)
        self.assertNotIn('nextPage =', failure)
        self.assertIn('if inFlight == ticket { inFlight = nil }', self.state)
        for field in ['self.query == query', 'self.scope == scope', 'self.manualAreaRevision == manualAreaRevision']:
            self.assertIn(field, self.state)

    def test_duplicates_append_without_replacing_previously_displayed_rows(self):
        self.assertIn('var seen = Set(rows.map(\\.id))', self.state)
        self.assertIn('rows.append(contentsOf: page.rows.filter { seen.insert($0.id).inserted })', self.state)
        self.assertNotIn('Dictionary(uniqueKeysWithValues:', self.state)

    def test_ui_keeps_same_activity_rows_for_map_list_and_detail(self):
        self.assertIn('ForEach(pagination.rows)', self.view)
        self.assertIn('for activity in visibleCityResults == nil ? [] : pagination.rows', self.view)
        self.assertIn('(visibleCityResults == nil ? [] : pagination.rows).first', self.view)
        self.assertIn('pagination.rows.filter { !$0.hasValidCoordinates }.count', self.view)
        load_more = self.view.split('private func performLoadMore(', 1)[1].split('private func acceptsPage(', 1)[0]
        for forbidden in ['cityResults = nil', 'selectedPin = nil', 'pagination.invalidate()', 'mapEnabled = true']:
            self.assertNotIn(forbidden, load_more)
        self.assertIn('mapPagination.filteredPage', self.view)
        self.assertIn('mapPagination.retry', self.view)

    def test_ui_and_reader_both_fence_identity_and_cancel_old_work(self):
        for fragment in ['reader.scope == ticket.scope', 'reader.manualAreaRevision == ticket.manualAreaRevision', 'cityQuery == ticket.query', '!Task.isCancelled', 'defer { pagination.cancel(ticket) }', 'guard acceptsPage(ticket) else { return }', 'pagination.cancelPending()']:
            self.assertIn(fragment, self.view)
        self.assertIn('return try await read { try await $0.cityActivityPage(query, page: page, token: $1) }', self.reader)
        self.assertIn('currentContext() == context, scope == capturedScope, manualAreaRevision == areaRevision', self.reader)
        self.assertIn('if error as? APIError == .unauthorized, context.accountID != nil { onUnauthorized(context) }', self.reader)

    def test_localization_fragment_covers_new_ui_copy_without_shared_catalog_edit(self):
        fragment = json.loads((ROOT/'Resources/SearchMapPaginationLocalizations.fragment.json').read_text())
        ui = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', self.view)
        used = set(re.findall(r'"(mapPagination\.[A-Za-z]+)"', ui))
        self.assertEqual(used, set(fragment))
        for item in fragment.values():
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})
            for localized in item['localizations'].values():
                self.assertTrue(localized['stringUnit']['value'])

    def test_explicit_fixture_flows_and_swift_assertions_are_authored(self):
        for scenario in ['pagination', 'pageFailure', 'pageDelayed', 'filteredPage']:
            self.assertIn(scenario, self.fixture)
        self.assertIn('activityPageRequests.append(page)', self.fixture)
        self.assertIn('APIConfiguration(baseURL: URL(string: "https://example.test/")!)', self.core_tests)
        self.assertNotIn('https://example.invalid/', self.core_tests)
        self.assertIn('cancelActivityPage(id)', self.fixture)
        self.assertEqual(len(re.findall(r'func test\w+', self.core_tests)), 16)
        self.assertEqual(len(re.findall(r'func test\w+', self.app_tests)), 4)
        for name in ['testServiceKeepsRawCountWhenEveryActivityIsFilteredOut',
                     'testSessionReaderRejectsLateSuccessAnd401AfterAccountOrAreaChange',
                     'testCurrentAuthenticatedPage401ExpiresCapturedAccount',
                     'testResetInvalidationAndDismissalRetireLateSuccessAndFailure']:
            self.assertIn(name, self.core_tests)

    def test_slice_has_no_location_mutation_or_live_provider(self):
        for source in [self.state, self.service, self.reader, self.view]:
            for forbidden in ['CLLocationManager', 'requestAlwaysAuthorization', 'startUpdatingLocation',
                              'MKDirections(', '/presence', '/reveal', '/complete', '/favorite']:
                self.assertNotIn(forbidden, source)

if __name__ == '__main__':
    unittest.main()
