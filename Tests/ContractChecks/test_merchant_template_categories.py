"""Supplementary source checks; these do not compile Swift or run native UI."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateCategoryChecks(unittest.TestCase):
    def group(self): return read('Core/MerchantTemplateCategorySelection.swift')

    def test_existing_catalog_contract_and_native_grant(self):
        service = read('Core/MerchantOperationsService.swift').split('public func templateCategories(')[1].split('public func featuredActivities(')[0]
        self.assertIn('guard access.allows(.templates)', service)
        self.assertIn('read("api/category/list", body: .form(["type": "4", "parentid": "0"]), token: token)', service)
        self.assertNotIn('page', service); self.assertNotIn('save', service)

    def test_catalog_reads_retain_existing_session_and_unauthorized_fences(self):
        reader = read('Core/MerchantOperationsReading.swift')
        method = reader.split('public func templateCategories()')[1].split('public func featuredActivities')[0]
        for text in ['let expected = currentSession()', 'try await read', 'service.access(token: token)', '!Task.isCancelled, expected == currentSession()']:
            self.assertIn(text, method)
        self.assertIn('currentSession() == session, captured == scope', reader)
        self.assertIn('if error as? APIError == .unauthorized { onUnauthorized(session) }', reader)

    def test_catalog_is_strict_but_empty_is_valid(self):
        group = self.group()
        for text in ['singleValueContainer().decode([MerchantTemplateCategory].self)', 'Set(rows.map(\\.id)).count == rows.count',
                     '9_007_199_254_740_991', '$0.type == nil || $0.type == 4', '!$0.name.trimmingCharacters']:
            self.assertIn(text, group)
        catalog = group.split('public struct MerchantTemplateCategoryCatalog:')[1].split('/// Exact existing')[0]
        self.assertNotIn('!rows.isEmpty', catalog)

    def test_wire_payload_uses_only_existing_two_fields_and_keeps_raw_noop(self):
        group = self.group()
        for text in ['fields["activityCategoryids"] = rawIDs', 'fields["categoryId"] = primaryID',
                     'if isSupported && selectedIDs == ids { return }', 'primaryID = ids[0]', 'String(id) == token']:
            self.assertIn(text, group)
        self.assertNotIn('fields["categoryIds"]', group); self.assertNotIn('fields["sysCategoryList"]', group)
        model = read('Core/MerchantOperationsContracts.swift')
        self.assertIn('for (key, value) in categories.fields { fields[key] = value }', model)
        self.assertIn('try c.decodeIfPresent(String.self, forKey: .activityCategoryids)', model)
        self.assertIn('try c.decodeIfPresent([MerchantTemplateCategory].self, forKey: .sysCategoryList)', model)

    def test_invalid_and_missing_source_categories_require_explicit_handling(self):
        group = self.group()
        for text in ['public var needsReplacement:', 'public func beginReplacement()', 'public var unavailableIDs:',
                     'public func removeUnavailable(_ id: Int)', '!selectedIDs.isEmpty && unavailableIDs.isEmpty',
                     'replacedUnsupportedSource = !isSupported || replacedUnsupportedSource']:
            self.assertIn(text, group)
        reload = group.split('public func reload() async')[1].split('public func apply()')[0]
        self.assertNotIn('selectedIDs =', reload)

    def test_buffer_never_edits_document_and_stale_async_results_are_discarded(self):
        group = self.group()
        for text in ['owner.draft == .template(original)', 'owner.reader.scope == scope', 'owner.draftIdentity == identity',
                     'ticket == generation, isCurrent', 'request?.cancel()', 'consumed = true', 'cancel(); return edited']:
            self.assertIn(text, group)
        self.assertNotIn('owner.edit(', group); self.assertNotIn('save(', group)
        app = read('App/MerchantTemplateCategoryPicker.swift')
        self.assertIn('document.edit(.template(value))', app)
        for text in ['.onChange(of: document.coordinator.draftIdentity)', '.onChange(of: document.coordinator.draft)',
                     '.onChange(of: document.coordinator.reader.scope)', '.onChange(of: scenePhase)', '.onDisappear { close() }']:
            self.assertIn(text, app)

    def test_ui_includes_catalog_error_empty_search_retry_and_frozen_review(self):
        app = read('App/MerchantTemplateCategoryPicker.swift')
        for text in ['MerchantOperationsIssueView(issue: issue)', 'merchant.categories.retry', 'merchant.categories.empty',
                     'merchant.categories.noMatches', '.searchable(text: $search', 'merchant.categories.cancel',
                     'merchant.categories.apply', 'merchant.categories.replacementReview', 'Text(verbatim: raw)']:
            self.assertIn(text, app)
        editor = read('App/MerchantOperationsEditor.swift')
        self.assertIn('MerchantTemplateCategoryPicker(document: model)', editor)
        self.assertIn('MerchantTemplateCategoryReview(categories: template.categories)', editor)

    def test_save_authority_and_ai_boundary_remain_existing(self):
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', read('Core/MerchantOperationsDraft.swift'))
        reader = read('Core/MerchantOperationsReading.swift')
        self.assertIn('baseline = .template(returned); draft = .template(returned)', reader)
        assist = read('Core/MerchantTemplateAssistContracts.swift').split('public enum MerchantTemplateAssistField:')[1].split('public struct MerchantTemplateAssistEdits:')[0]
        self.assertNotIn('categories', assist); self.assertNotIn('categoryId', assist)
        fixture = read('Core/MerchantOperationsSyntheticFixtures.swift')
        self.assertIn('returned.categories = .init(rawIDs:', fixture); self.assertIn('Synthetic observation', fixture)

    def test_bilingual_fragment_covers_new_keys(self):
        fragment = json.loads(read('Resources/MerchantTemplateCategoryLocalizations.fragment.json'))
        app = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', read('App/MerchantTemplateCategoryPicker.swift'))
        keys = set(re.findall(r'"(merchant\.categories\.[A-Za-z]+)"', app))
        keys.update('merchant.categories.' + key + ' %lld' for key in ['removeID', 'selectionCount', 'id', 'primary'])
        self.assertEqual(set(fragment), keys); self.assertEqual(len(fragment), 24)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])

    def test_authored_core_tests_cover_full_read_buffer_write_readback_and_gates(self):
        tests = read('Tests/CoreTests/MerchantTemplateCategoryTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 20)
        for text in ['testNoOpSelectionKeepsExactRawCSVAndExistingPrimary', 'testUnavailableSavedIDsAreNeverSilentlyDropped',
                     'testNewerReloadWinsOverOutOfOrderResponse', 'testLateResponseAfterCancelCannotRestoreCatalog',
                     'testCatalogReadUsesExactTypeParentFormAfterMerchantGrant', 'testDeniedMerchantGrantNeverCallsCatalog',
                     'testApprovedSaveSendsOrderedIDsAndReadsCanonicalLabelsAndPrimary', 'testNoApprovalStillPreventsCategorySave',
                     'Server canonical puzzle', '"/prod-api/api/template/myinfo"']:
            self.assertIn(text, tests)

    def test_authored_ui_tests_cover_cancel_review_save_reload_discard(self):
        tests = read('Tests/AppUITests/MerchantTemplateCategoryFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 3)
        for text in ['merchant.categories.cancel', 'merchant.categories.apply', 'merchant.categories.reload',
                     'merchant.operations.confirm.cancel', 'merchant.operations.exampleSaved', 'app.alerts.buttons["merchant.operations.keepEditing"].tap()', 'app.alerts.buttons["merchant.operations.discardReload"].tap()']:
            self.assertIn(text, tests)
        self.assertIn('app.alerts.buttons["merchant.operations.keepEditing"].waitForExistence(timeout: 5)', tests)
        self.assertIn('app.alerts.buttons["merchant.operations.discardReload"].waitForExistence(timeout: 5)', tests)


if __name__ == '__main__': unittest.main()
