"""Supplementary source assertions only; native typechecking and UI require Apple tools."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateBrowserChecks(unittest.TestCase):
    def core(self): return read('Core/MerchantTemplateBrowser.swift')
    def app(self): return read('App/MerchantTemplateBrowserView.swift')

    def test_exact_my_list_contract_keeps_ten_row_paging_and_existing_grant(self):
        service = read('Core/MerchantOperationsService.swift').split('public func templatePage(')[1].split('public func templateCategories(')[0]
        for text in ['guard access.allows(.templates)', 'guard page > 0', 'read("api/template/my-list"',
                     '"is_quote": "", "keyword": "", "category_id": ""', '"pageNum": String(page)', '"pageSize": String(MerchantTemplatePage.pageSize)']:
            self.assertIn(text, service)
        self.assertIn('public static let pageSize = 10', self.core())
        self.assertNotIn('draft_status', service); self.assertNotIn('scope', service); self.assertNotIn('publish_status', service)

    def test_page_decode_requires_rows_and_preserves_unknown_total(self):
        core = self.core()
        for text in ['c.decode([MerchantTemplateRecord].self, forKey: .rows)', 'if !c.contains(.total) { total = nil }',
                     'else if try c.decodeNil(forKey: .total) { total = nil }', 'total.map({ $0 >= rows.count }) ?? true',
                     'rows.allSatisfy({ $0.id > 0 })', 'Set(rows.map(\\.id)).count == rows.count']:
            self.assertIn(text, core)
        self.assertNotIn('total ?? 0', core)

    def test_session_adapter_reuses_access_cancellation_and_unauthorized_fences(self):
        reader = read('Core/MerchantOperationsReading.swift')
        section = reader.split('public func templatePage(page: Int)')[1].split('public func templateCategories()')[0]
        for text in ['try await read', 'service.access(token: token)', 'expected == currentSession()',
                     'service.templatePage(page: page, access: access, token: token)', 'return .init(page: result, access: access)']:
            self.assertIn(text, section)
        self.assertIn('currentSession() == session, captured == scope', reader)
        self.assertIn('if error as? APIError == .unauthorized { onUnauthorized(session) }', reader)

    def test_append_advances_only_after_success_and_keeps_retry_page(self):
        core = self.core()
        for text in ['await fetch(page: page + 1, appending: true', 'page = requestedPage; loaded = true',
                     'else if appending { loadMoreIssue = .init(error) }', 'public var canLoadMore:', 'issue == nil && page < Int.max']:
            self.assertIn(text, core)
        catch = core.split('        } catch {')[1]
        self.assertNotIn('page = requestedPage', catch); self.assertNotIn('sourceRows = combined', catch)

    def test_no_false_completion_duplicate_drop_or_oversized_page_acceptance(self):
        core = self.core()
        for text in ['incoming.rows.count <= MerchantTemplatePage.pageSize', 'Set(combined.map(\\.id)).count == combined.count',
                     'total >= combined.count, !incoming.rows.isEmpty || combined.count >= total',
                     'incoming.total.map { combined.count < $0 } ?? (incoming.rows.count == MerchantTemplatePage.pageSize)']:
            self.assertIn(text, core)
        self.assertNotIn('unique', core); self.assertNotIn('Set(combined)', core)

    def test_stale_cancel_and_changed_access_cannot_restore_or_mix_rows(self):
        core = self.core()
        for text in ['scope == reader.scope, reader.isAuthenticated', 'ticket == generation', 'request?.cancel()',
                     'active = false; generation += 1', 'appending && access != result.access',
                     'clearRows(); loadedScope = scope; issue = .key("merchant.templateBrowser.accessChanged")',
                     'public var rows: [MerchantTemplateRecord] { isCurrent ? sourceRows : [] }',
                     'error as? MerchantOperationsFailure == .accessDenied || error as? APIError == .unauthorized']:
            self.assertIn(text, core)

    def test_active_list_route_bypasses_legacy_first100_document_loader(self):
        app = read('App/MerchantOperationsViews.swift').split('struct MerchantOperationsDocumentView:')[1]
        entry = app.split('private var documentBody:')[0]
        self.assertIn('if destination == .templates', entry); self.assertIn('MerchantTemplateBrowserView(reader: reader', entry)
        self.assertNotIn('model.load()', entry)
        self.assertNotIn('MerchantOperationsTemplatesView', app); self.assertNotIn('merchant.operations.templatePageLimit', app)

    def test_full_ui_recovery_return_refresh_and_existing_exact_id_editor(self):
        app = self.app()
        for text in ['merchant.templateBrowser.retryRefresh', 'merchant.templateBrowser.retained', 'merchant.templateBrowser.retryMore',
                     'merchant.templateBrowser.emptyHint', 'merchant.templateBrowser.end', '.refreshable { await model.refresh() }',
                     '.task(id: reader.scope) { await model.refresh() }', '.onDisappear { model.deactivate() }',
                     'destination: .template(row.id)', 'destination: .template(nil)', '!reader.isAuthenticated']:
            self.assertIn(text, app)
        self.assertNotIn('.searchable', app); self.assertNotIn('Picker(', app)
        for text in ['.save(', 'deleteTemplate', 'market-submit', 'updateLibraryStatus']: self.assertNotIn(text, app + self.core())

    def test_bilingual_fragment_matches_new_strings(self):
        fragment = json.loads(read('Resources/MerchantTemplateBrowserLocalizations.fragment.json'))
        source = self.core() + self.app()
        source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', source)
        keys = set(re.findall(r'"(merchant\.templateBrowser\.[A-Za-z]+)"', source))
        keys.update(['merchant.templateBrowser.count %lld %lld', 'merchant.templateBrowser.loadedCount %lld'])
        self.assertEqual(set(fragment), keys); self.assertEqual(len(fragment), 12)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])

    def test_synthetic_fixture_can_page_beyond100_and_fail_once_without_network(self):
        fixture = read('Core/MerchantOperationsSyntheticFixtures.swift')
        for text in ['configureTemplateBrowserFixture(count: Int = 105)', 'templatePageFailures.remove(page)',
                     'templatePageRequests.append(page)', 'fields["title"] = current.title']:
            self.assertIn(text, fixture)
        host = read('App/MerchantOperationsFixtureSupport.swift')
        self.assertTrue(host.startswith('#if DEBUG'))
        for text in ['--merchant-template-browser-pages', '--merchant-template-browser-first-failure', '--merchant-template-browser-more-failure', '--merchant-template-browser-empty']:
            self.assertIn(text, host)

    def test_authored_core_matrix_covers_pages_recovery_access_and_transport(self):
        tests = read('Tests/CoreTests/MerchantTemplateBrowserTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 23)
        for text in ['testAll105TemplatesAreReachableAndEndStopsRequests', 'testAppendFailureRetainsRowsAndRetriesSamePage',
                     'testRefreshSupersedesLateAppendWithoutMixingSnapshots', 'testChangedMerchantAccessClearsEarlierMerchantRows',
                     'testAccountSwitchCannotReceivePriorAccountLatePage', 'testCancelledCallerCannotCommitItsResponse',
                     'testExactReadFormPreservesMiniPagingAndExistingGrant', 'testUnauthorizedListUsesExistingSessionCallback']:
            self.assertIn(text, tests)

    def test_authored_ui_matrix_covers_first_append_save_return_and_empty(self):
        tests = read('Tests/AppUITests/MerchantTemplateBrowserFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 4)
        for text in ['merchant.templateBrowser.retryRefresh', 'merchant.templateBrowser.retryMore', 'merchant.operations.template.81',
                     'Synthetic template 11', 'Synthetic template 1 refreshed', 'Loaded 0 of 0 templates', 'merchant.operations.newTemplate']:
            self.assertIn(text, tests)


if __name__ == '__main__': unittest.main()
