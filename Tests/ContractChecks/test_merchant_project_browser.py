"""Focused source/fixture checks only; not Swift compilation or XCTest execution."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()

class MerchantProjectBrowserSourceTests(unittest.TestCase):
    def setUp(self):
        self.core = read('Core/MerchantProjectBrowser.swift')
        self.contract = read('Core/MerchantContracts.swift')
        self.app = read('App/MerchantProjectsView.swift')
        self.controls = read('App/MerchantProjectBrowserControls.swift')
        self.fixtures = read('App/MerchantFixtureSupport.swift')
        self.tests = read('Tests/CoreTests/MerchantProjectBrowserTests.swift')
        self.ui = read('Tests/AppUITests/MerchantProjectBrowserFlowTests.swift')
    def test_exact_two_source_kinds_and_unknown_fallback(self):
        self.assertIn('case topic, activity, other', self.core)
        self.assertIn('project.bizType == "topic"', self.core)
        self.assertIn('project.bizType == "activity"', self.core)
        self.assertIn('page.rows.contains(where: MerchantProjectBrowserTab.other.contains) ? [.other] : []', self.core)
        self.assertNotIn('case template', self.core)
    def test_priority_is_raw_state_and_stable_server_order(self):
        self.assertIn('switch project.state { case "rejected": return 0; case "draft": return 1; case "pending": return 2; default: return 9 }', self.core)
        self.assertIn('first == second ? lhs.offset < rhs.offset : first < second', self.core)
        self.assertIn('page.rows.enumerated().filter', self.core)
        for fabricated in ['stateText', 'Date(', 'startTime', 'acceptStatus']: self.assertNotIn(fabricated, self.core)
    def test_loaded_counts_do_not_claim_global_totals(self):
        self.assertIn('page.rows.filter(tab.contains).count', self.core)
        self.assertIn('String(browser.count(browser.tab))', self.controls)
        self.assertIn('page.hasUnloadedRows', self.app)
        self.assertIn('merchant.projects.partial', self.app)
        self.assertNotIn('page.total', self.controls)
    def test_empty_type_has_explicit_local_recovery(self):
        self.assertIn('if page.rows.isEmpty', self.app)
        self.assertIn('else if browser.rows.isEmpty', self.app)
        self.assertIn('ForEach(browser.alternatives', self.app)
        self.assertIn('tabs.filter { $0 != tab && count($0) > 0 }', self.core)
        self.assertIn('presentation.invalidate(); tab = alternative', self.app)
    def test_tab_callbacks_bind_snapshot_and_rendered_tab(self):
        self.assertIn('guard model.value?.id == snapshot.id, !model.isLoading, tab == shownTab, browser.tabs.contains(selected)', self.app)
        self.assertIn('browser.alternatives.contains(alternative)', self.app)
        self.assertIn('presentation.invalidate(); tab = selected', self.app)
        self.assertIn('guard tab == shownTab, browser.rows.contains(project)', self.app)
    def test_context_and_replaced_source_retire_presentations(self):
        self.assertIn('.onChange(of: context) { _, _ in presentation.invalidate(); tab = .topic }', self.app)
        self.assertIn('.onChange(of: model.value?.id)', self.app)
        self.assertIn('if tab == .other', self.app)
        self.assertIn('let captured = context, revision = reader.sessionRevision', self.app)
        self.assertIn('guard context == captured, reader.isSignedIn', self.app)
    def test_existing_read_path_and_authorization_remain_byte_exact(self):
        self.assertEqual(hashlib.sha256((ROOT / 'Core/MerchantService.swift').read_bytes()).hexdigest(),
                         '3d2f2b5636417c8e95f278020cc96fe0fba1f44791d905030465603c8772d00f')
        service = read('Core/MerchantService.swift')
        self.assertIn('guard access.allows(.projects)', service)
        self.assertIn('"scope": "MERCHANT", "pageNum": "1", "pageSize": "200"', service)
    def test_new_presentation_never_requests_or_mutates_remote_state(self):
        for text in ['URLSession', 'HTTPTransport', 'api/', '.perform(', '.prepare(', '.confirm(', 'UserDefaults', 'openURL']:
            self.assertNotIn(text, self.core + self.controls)
        self.assertEqual(self.app.count('reader.merchantProjects(access: access)'), 1)
        self.assertNotIn('.perform(', self.app)
    def test_new_optional_fields_are_strictly_decoded(self):
        for field in ['state', 'ownerType', 'addressName']:
            self.assertIn(f'public let {field}: String?', self.contract)
            self.assertIn(f'{field} = try c.decodeIfPresent(String.self, forKey: .{field})', self.contract)
        self.assertIn('pendingVerifyCount = try c.decodeIfPresent(Int.self, forKey: .pendingVerifyCount)', self.contract)
        self.assertIn('if let pendingVerifyCount, pendingVerifyCount < 0', self.contract)
    def test_pending_count_only_for_exact_merchant_activity_role(self):
        self.assertIn('project.bizType == "activity", project.ownerType == "merchant" { role = .fulfiller }', self.core)
        self.assertIn('pendingVerifications = role == .fulfiller ? project.pendingVerifyCount : nil', self.core)
        self.assertIn('if let pending = facts.pendingVerifications', self.controls)
        self.assertNotIn('signupCount', self.core)
    def test_unknown_role_and_blank_address_are_not_invented(self):
        self.assertIn('["member", "club"].contains(project.ownerType ?? "")', self.core)
        self.assertIn('else { role = nil }', self.core)
        self.assertIn('address.flatMap { $0.isEmpty ? nil : $0 }', self.core)
        self.assertIn('if let role = facts.role', self.controls)
        self.assertIn('if let address = facts.address', self.controls)
    def test_context_is_in_list_and_existing_summary(self):
        self.assertEqual(self.app.count('MerchantProjectCardContext(project: project)'), 2)
        self.assertIn('MerchantProjectSummary(project: selected.project', self.app)
        self.assertIn('Text("merchant.summarySnapshot")', self.app)
    def test_topic_only_workspace_gate_is_unchanged(self):
        self.assertIn('selected.project.bizType == "topic"', self.app)
        self.assertIn('sourceFresh && selectionIsCurrent', self.app)
        self.assertIn('snapshot.page.rows.filter({ $0.id == project.id }).count == 1', self.app)
        self.assertIn('snapshot.access.merchantID == value.merchantID', self.app)
    def test_localization_has_complete_bilingual_fragment(self):
        f = json.loads(read('Resources/MerchantProjectBrowserLocalizations.fragment.json'))
        prefix = 'merchant.projectBrowser.'
        suffixes = {'title','kind','topic','activity','other','loadedCount','loadedOnly','orderHint','emptyTab','role.host','role.fulfiller','pendingCount %lld','attention'}
        self.assertEqual(set(f), {prefix + suffix for suffix in suffixes})
        for item in f.values():
            self.assertEqual(set(item['localizations']), {'en', 'zh-Hans'})
            for locale in item['localizations'].values(): self.assertTrue(locale['stringUnit']['value'])
        for lang in ['en', 'zh-Hans']:
            self.assertIn('%1$lld', f[prefix + 'pendingCount %lld']['localizations'][lang]['stringUnit']['value'])
        self.assertIn('loaded page only', f[prefix + 'loadedOnly']['localizations']['en']['stringUnit']['value'])
    def test_new_synthetic_fixture_exercises_real_loaded_count_and_shapes(self):
        raw = re.search(r'if scenario == \.projectBrowser \{\s*return try decode\(#"(.*?)"#\)', self.fixtures, re.S).group(1)
        page = json.loads(raw)
        self.assertEqual(page['total'], 205); self.assertEqual(len(page['rows']), 9)
        self.assertEqual({r['bizType'] for r in page['rows']}, {'topic','activity','future-kind'})
        self.assertEqual([r['pendingVerifyCount'] for r in page['rows'] if r.get('ownerType') == 'merchant'], [2, 0])
        self.assertIn('projectsReadCount += 1', self.fixtures)
        self.assertIn('var projectBrowserDiagnostics: Bool { scenario == .projectBrowser }', self.fixtures)
    def test_existing_fixture_payloads_are_not_replaced(self):
        self.assertIn('case owner, finance, inactive, retry, empty, projectBrowser', self.fixtures)
        self.assertIn('"title":"Fixture hosted activity"', self.fixtures)
        self.assertIn('if scenario == .empty', self.fixtures)
        self.assertNotIn('URLSession', self.fixtures)
    def test_swift_cases_cover_order_unknowns_nullable_facts_and_strict_errors(self):
        for name in ['testPendingPriorityKeepsSourceOrderWithinEveryRank','testMissingAndUnknownStateDoNotGetInventedAttention',
                     'testEmptyTypeRecoveryIsDistinctFromEmptyPage','testActivityAndThemeWithSameNumericIDStaySeparate',
                     'testMissingCountIsUnknownWhileZeroIsARealValue','testOptionalCardFieldsAcceptMissingNullButRejectWrongTypes',
                     'testHostDoesNotExposeMisplacedPendingCountOrInferRoleFromAcceptance']:
            self.assertIn('func ' + name, self.tests)
        self.assertEqual(len(re.findall(r'func test', self.tests)), 17)
    def test_authored_transport_tests_are_offline_and_check_no_new_tab_reads(self):
        self.assertIn('private final class BrowserTransport: HTTPTransport', self.tests)
        self.assertIn('https://example.test', self.tests)
        self.assertIn('XCTAssertEqual(transport.requests.count, 1)', self.tests)
        self.assertIn('testMissingProjectGrantStopsBeforeRead', self.tests)
        self.assertNotIn('URLSession', self.tests)
    def test_authored_ui_covers_local_tabs_summary_and_empty_recovery(self):
        self.assertEqual(len(re.findall(r'func test', self.ui)), 3)
        for text in ['--uitesting-merchant-fixture', 'projectBrowser', 'tab("Activities", app)', 'tab("Other", app)',
                     'tab("Themes", app)', 'merchant.projectBrowser.fixture.readCount', 'merchant.projectBrowser.switch.activity',
                     'Pending verification: 2', 'XCTAssertFalse(app.buttons["merchant.projectWorkspace.open"].exists)']:
            self.assertIn(text, self.ui)
    def test_documentation_does_not_claim_native_execution(self):
        docs = read('docs/merchant-project-browser.md')
        for text in ['49c68c6420270b0a0cc7ec8d18bc8561f329d796', 'f1fe895f34c3664783aafd6145cf93e0de15878d',
                     'NOT_RUN', 'scope=MERCHANT', 'No unsubmitted batch dependency', 'tree-sitter']:
            self.assertIn(text, docs)

if __name__ == '__main__': unittest.main(verbosity=2)
