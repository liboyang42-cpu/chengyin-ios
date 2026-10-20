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

    def test_shelf_delete_queries_reveal_without_relaxing_business_assertions(self):
        text=read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift')
        self.assertIn('maximumSwipes: 12, requiresHittable: requiresHittable',text)
        self.assertIn('attachFixtureScreenshot(self, app: app, name: "Owned shelf reveal failure")',text)
        self.assertIn('OWNED_SHELF_FIXTURE_REVEAL',text)
        self.assertEqual(text.count('reveal(button, in: app); XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertTrue(button.isEnabled); button.tap()'),2)
        self.assertIn('XCTAssertEqual(status.label, "Simulation completed. No template was saved to a server or published.")',text)
        self.assertIn('XCTAssertEqual(status.label, "This change is unresolved. Further shelf changes are locked; refreshing alone cannot confirm an unknown request.")',text)
        self.assertIn('reveal(button, in: app, requiresHittable: false); XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertFalse(button.isEnabled)',text)
        self.assertIn('XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].isEnabled)',text)

    def test_keyboard_empty_keyword_rereads_once_without_trim_or_second_clear(self):
        view=read('App/TemplateAuthoringMineView.swift')
        button=view.split('if !keyword.isEmpty {',1)[1].split('accessibilityIdentifier("templateAuthor.shelf.clearSearch")',1)[0]
        self.assertIn('let stamp = viewRequest', button)
        self.assertIn('keyword = ""', button)
        self.assertEqual(button.count('refreshClearedKeyword(stamp: stamp, refreshUnfiltered: true)'), 1)
        self.assertNotIn('await refresh()', button)
        change=view.split('.onChange(of: keyword)',1)[1].split('.onChange(of: sessionRevision)',1)[0]
        self.assertIn('coordinator.cancelShelfReview()', change)
        self.assertIn('newValue.isEmpty, appliedKeyword?.isEmpty == false', change)
        self.assertEqual(change.count('refreshClearedKeyword'), 1)
        self.assertNotIn('trimmingCharacters', change)
        cleared=view.split('private func refreshClearedKeyword(stamp: UUID, refreshUnfiltered: Bool = false) async {',1)[1].split('private func refresh() async {',1)[0]
        self.assertIn('guard stamp == viewRequest, keyword.isEmpty, !Task.isCancelled else { return }', cleared)
        self.assertIn('guard refreshUnfiltered || appliedKeyword?.isEmpty == false else { return }', cleared)
        self.assertEqual(cleared.count('await refresh()'), 1)
        refresh=view.split('private func refresh() async {',1)[1]
        self.assertLess(refresh.index('let stamp = UUID(); viewRequest = stamp'), refresh.index('await coordinator.shelfReader.refresh(keyword: keyword)'))
        self.assertLess(refresh.index('rows = coordinator.shelfReader.refreshSnapshot(keyword: keyword)'), refresh.index('await coordinator.shelfReader.refresh(keyword: keyword)'))
        self.assertLess(refresh.index('await coordinator.shelfReader.refresh(keyword: keyword)'), refresh.index('if coordinator.canSubmit { await coordinator.loadMine() }'))
        self.assertNotIn('trimmingCharacters', view)
        self.assertIn('ForEach(appliedKeyword == keyword ? rows : [])', view)
        self.assertIn('if hasMore, appliedKeyword == keyword', view)
        self.assertIn('guard !busy, appliedKeyword == keyword else { return }', view)
        ui=read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift')
        name='func testKeyboardClearingUnsubmittedQueryRestoresShelfWithoutClearButton('
        self.assertIn(name, ui)
        body=ui.split(name,1)[1].split('\n    func ',1)[0]
        self.assertIn('XCUIKeyboardKey.delete', body)
        self.assertIn('XCTAssertFalse(detail.exists)', body)
        self.assertNotIn('templateAuthor.shelf.clearSearch"].tap()', body)
        self.assertIn('XCTAssertFalse(clear.exists)', body)

    def test_explicit_clear_retains_unfiltered_refresh_and_stale_work_fences(self):
        view=read('App/TemplateAuthoringMineView.swift')
        button=view.split('if !keyword.isEmpty {',1)[1].split('accessibilityIdentifier("templateAuthor.shelf.clearSearch")',1)[0]
        self.assertLess(button.index('let stamp = viewRequest'), button.index('keyword = ""'))
        self.assertIn('refreshUnfiltered: true', button)
        self.assertNotIn('appliedKeyword', button)
        self.assertIn('.task(id: sessionRevision) { viewRequest = UUID(); busy = false;', view)
        self.assertIn('.onDisappear { viewRequest = UUID(); coordinator.shelfReader.leave();', view)
        ui=read('Tests/AppUITests/TemplateOwnShelfFlowTests.swift')
        body=ui.split('func testExplicitClearOfUnsubmittedDraftRefreshesUnfilteredShelf()',1)[1].split('\n    func ',1)[0]
        self.assertIn('field.typeText("draft")', body)
        self.assertIn('clear.tap()', body)
        self.assertIn('XCTAssertFalse(status.exists)', body)
