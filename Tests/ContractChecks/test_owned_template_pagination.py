"""Native source assertions, supplementary to authored Swift tests; no runtime proof."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class OwnedTemplatePagination(unittest.TestCase):
    def test_read_descriptor_bounded_member_only(self):
        text=read('Core/TemplateAuthoringShelf.swift')
        for value in ['pageSize = 10','maximumPages = 100','"category_id": ""','"is_quote": ""','mutates: false','MemberPlayTemplateID(rawValue: $0.id)','Set(rows.map(\\.id)).count == rows.count']:
            self.assertIn(value,text)
        self.assertNotIn('/api/template/info',text)
    def test_reader_cannot_reconcile_or_write(self):
        text=read('Core/TemplateAuthoringShelf.swift').split('public final class TemplateOwnShelfReader')[1]
        for forbidden in ['submit(', 'clearShelfPending', 'TemplateOwnShelfReview', 'libraryStatus(']: self.assertNotIn(forbidden,text)
        for value in ['generation == stamp','currentSession() == owner','!Task.isCancelled','requested == 1','page: page + 1','!result.rows.isEmpty','!existing.contains($0.id)']:
            self.assertIn(value,text)
    def test_owner_write_authority_is_unchanged(self):
        text=read('Core/TemplateAuthoringCoordinator.swift')
        self.assertIn('fresh.first(where: { $0.id == value.templateID.rawValue }) == value.baseline',text)
        self.assertIn('try validateShelfRows(readback); rows = readback',text)
        self.assertIn('rows.count < 100 && matches.isEmpty',read('Core/TemplateAuthoringShelf.swift'))
        self.assertIn('"pageSize": "100"',read('Core/TemplateAuthoringContract.swift'))
        view=read('App/TemplateAuthoringMineView.swift')
        self.assertEqual(view.count('!coordinator.rows.contains(row)'),2)
        self.assertIn('coordinator.shelfReader.synchronizeSession()',view)
        self.assertIn('stamp == viewRequest, !Task.isCancelled',view)
    def test_factory_stays_dormant_and_wire_whitelist_exact(self):
        factory=read('App/AppSession.swift').split('func templateAuthoringEditor')[1].split('\n    }')[0]
        self.assertIn('TemplateAuthoringAdapter()',factory)
        self.assertNotIn('TemplateAuthoringHTTPTransport',factory)
        self.assertIn('descriptor == (try TemplateOwnShelfPage.request(page: page, keyword: keyword))',read('Core/TemplateAuthoringWireRequestBuilder.swift'))
    def test_authored_runtime_cases_present_not_executed_here(self):
        text=read('Tests/CoreTests/TemplateAuthoringHTTPTests.swift')
        for name in ['testNewKeywordRejectsOldSuccessAndError','testSameAccountEpochAndRoleRevisionClearContinuation','testLimitCannotIssuePage101','testContinuationRetryPreservesRowsAndPageThenStopsAtTotal','testMalformedEnvelopeAndServerRefusalDoNotFallBack']:
            self.assertIn(name,text)

    def test_detail_destination_survives_source_row_invalidation(self):
        view=read('App/TemplateAuthoringMineView.swift')
        self.assertIn('.navigationDestination(item: $selectedMember)',view)
        self.assertIn('Button { selectedMember = id }',view)
        self.assertNotIn('NavigationLink { memberDetail(id) }',view)
        self.assertIn('.onChange(of: sessionRevision) { _, _ in selectedMember = nil }',view)
        self.assertIn('testOwnedDetailBackAndReopenKeepsStableDestination',read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift'))
