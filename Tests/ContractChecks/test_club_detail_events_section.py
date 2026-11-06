"""Package 10 source-level guard: club detail events tab summary reuses existing reads only."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ClubDetailEventsSectionTests(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_symbols_and_wiring(self):
        section = self.text('App/ClubDetailEventsSection.swift')
        for symbol in ['ClubDetailEventsSection', 'ClubEventCalendarReadModel', 'ClubEventCalendarView',
                       'club.calendar.open', 'task(id: readContext)', 'model.invalidate()']:
            self.assertIn(symbol, section)
        self.assertIn('ClubDetailEventsSummary', self.text('Core/ClubDetailEventsSummary.swift'))
        self.assertIn('ClubDetailEventsSection(', self.text('App/ClubDetailView.swift'))

    def test_no_new_endpoints_or_writes(self):
        for path in ['App/ClubDetailEventsSection.swift', 'Core/ClubDetailEventsSummary.swift']:
            src = self.text(path)
            self.assertIsNone(re.search(r'api/', src), path)
            self.assertNotIn('URLSession', src)
            self.assertNotIn('.write', src)

    def test_untouched_package09_and_no_new_localization_keys(self):
        section = self.text('App/ClubDetailEventsSection.swift')
        keys = set(re.findall(r'(?:Text|Label|LabeledContent)\("(club\.[A-Za-z.]+)"', section))
        catalog = ''.join(p.read_text() for p in (ROOT / 'Resources').glob('*.json'))
        for key in keys:
            self.assertIn('"%s"' % key, catalog, key)

    def test_loaded_empty_and_context_isolation_projection_tests(self):
        summary = self.text('Core/ClubDetailEventsSummary.swift')
        section = self.text('App/ClubDetailEventsSection.swift')
        tests = self.text('Tests/CoreTests/ClubDetailEventsSummaryTests.swift')

        for token in [
            'case loading',
            'case failed(localizationKey: String)',
            'case empty',
            'case loaded(current: Int, ended: Int, upcoming: [ClubActivityRow])',
            'overview.rows.isEmpty ? .empty',
            'Array(overview.current.prefix(Self.upcomingLimit))',
            'acceptedContext: ClubGovernanceReadContext?',
            'expectedContext: ClubGovernanceReadContext',
        ]:
            self.assertIn(token, summary)

        for token in [
            'let accepted = model.accepted(readContext, access: governance.access)',
            'acceptedContext: accepted ? model.context : nil',
            'expectedContext: readContext',
            'club.detail.events.loading',
            'club.detail.events.error',
            'club.detail.events.empty',
            'club.detail.events.currentCount',
            'club.detail.events.endedCount',
        ]:
            self.assertIn(token, section)

        required_test_methods = [
            'testNoOverviewAndNoFailureIsLoading',
            'testFailuresAreIsolatedAndMapToExistingKeys',
            'testUpcomingLimitIsThree',
            'testEmptyAuthorizedOverviewProjectsEmptyState',
            'testLoadedProjectionCountsCurrentAndEndedAndCapsUpcomingAtThreeInSourceOrder',
            'testEndedOnlyOverviewProjectsLoadedWithZeroCurrentAndEmptyUpcomingRatherThanEmpty',
            'testScopeAccessAndStaleContextDiscardProjectLoadingWithoutLeakingRows',
        ]
        for method in required_test_methods:
            self.assertIn(f'func {method}(', tests)

        for assertion_token in [
            '.empty',
            '.loaded(current, ended, upcoming)',
            '.loaded(current: 0, ended: 2, upcoming: [])',
            'XCTAssertEqual(upcoming.map(\\.id), [92, 93, 95])',
            'XCTAssertEqual(upcoming.map(\\.name), ["Morning Run", nil, "City Orienteering"])',
            'XCTAssertEqual(upcoming.map(\\.status), [.live, .recruiting, .recruiting])',
            'context(clubID: 82)',
            'context(authorizationGeneration: UUID())',
            'context(accessIdentity: ObjectIdentifier(otherToken))',
        ]:
            self.assertIn(assertion_token, tests)


if __name__ == '__main__':
    unittest.main()
