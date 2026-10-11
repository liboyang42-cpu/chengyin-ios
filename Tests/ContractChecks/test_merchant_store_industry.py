"""Source-level supplementary checks; not Swift typechecking or simulator acceptance."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantStoreIndustryChecks(unittest.TestCase):
    def core(self): return read('Core/MerchantStoreIndustrySelection.swift')
    def app(self): return read('App/MerchantStoreIndustryPicker.swift')

    def test_industry_catalog_uses_type_one_and_existing_profile_permission(self):
        service = read('Core/MerchantOperationsService.swift').split('public func storeIndustries(')[1].split('public func featuredActivities(')[0]
        self.assertIn('guard access.allows(.decor)', service)
        self.assertIn('read("api/category/list", body: .form(["type": "1", "parentid": "0"]), token: token)', service)
        self.assertNotIn('"type": "4"', service); self.assertNotIn('.templates', service)

    def test_catalog_accepts_only_existing_integer_single_industries(self):
        core = self.core()
        for text in ['id > 0, id <= Int(Int32.max)', 'type == nil || type == 1', '!name.trimmingCharacters',
                     'singleValueContainer().decode([MerchantStoreIndustry].self)', 'Set(rows.map(\\.id)).count == rows.count']:
            self.assertIn(text, core)
        self.assertNotIn('!rows.isEmpty', core)

    def test_session_read_preserves_access_and_account_fences(self):
        reader = read('Core/MerchantOperationsReading.swift')
        method = reader.split('public func storeIndustries()')[1].split('public func featuredActivities(')[0]
        for text in ['let expected = currentSession()', 'try await read', 'service.access(token: token)', 'expected == currentSession()']:
            self.assertIn(text, method)
        self.assertIn('currentSession() == session, captured == scope', reader)

    def test_apply_is_single_use_and_changes_only_existing_category_id(self):
        core = self.core(); apply = core.split('public func apply()')[1].split('public func cancel()')[0]
        self.assertIn('var edited = original; edited.categoryID = selected.id', apply)
        self.assertIn('cancel(); return edited', apply)
        for text in ['save(', 'owner.edit(', 'categoryName', 'activityCategoryids']: self.assertNotIn(text, apply)
        self.assertIn('document.edit(.decor(value))', self.app())

    def test_unavailable_source_is_retained_without_automatic_selection_or_clear(self):
        core = self.core()
        self.assertIn('selectedID = original.categoryID', core)
        self.assertIn('public var previousIsUnavailable:', core)
        self.assertIn('rows.contains(where: { $0.id == id })', core)
        self.assertNotIn('selectedID = nil', core)
        reload = core.split('public func reload()')[1].split('public func apply()')[0]
        self.assertNotIn('selectedID =', reload)
        self.assertIn('merchant.industry.unavailable', self.app()); self.assertIn('merchant.industry.noClear', self.app())

    def test_new_industry_field_can_make_an_otherwise_empty_decor_draft_valid(self):
        core = read('Core/MerchantOperationsContracts.swift')
        self.assertIn('&& tags.isEmpty && (categoryID ?? 0) <= 0 && !(featuredType == 0 && featuredID == nil)', core)
        self.assertIn('"categoryId": categoryID as Any? ?? NSNull()', core)

    def test_cancel_stale_document_account_and_late_response_are_fenced(self):
        core = self.core()
        for text in ['owner.draft == .decor(original)', 'owner.reader.scope == scope', 'owner.draftIdentity == identity',
                     'ticket == generation, isCurrent', 'request?.cancel()', 'consumed = true']:
            self.assertIn(text, core)
        app = self.app()
        for text in ['.onChange(of: document.coordinator.draftIdentity)', '.onChange(of: document.coordinator.draft)',
                     '.onChange(of: document.coordinator.reader.scope)', '.onChange(of: scenePhase)', '.onDisappear { close() }']:
            self.assertIn(text, app)

    def test_frozen_review_and_industry_only_readback_mount_existing_flow(self):
        editor = read('App/MerchantOperationsEditor.swift')
        self.assertIn('MerchantStoreIndustryPicker(document: model)', editor)
        self.assertIn('MerchantStoreIndustryReview(change: change)', editor)
        reader = read('Core/MerchantOperationsReading.swift')
        section = reader.split('} else if MerchantStoreIndustryChange(baseline: value.baseline, draft: value.draft) != nil {')[1].split('} else if case .cooperation')[0]
        for text in ['document = nil; baseline = nil; draft = nil', 'reader.document(.decor)',
                     'baseline = .decor(returned); draft = .decor(returned)', 'merchant.industry.readbackFailed']:
            self.assertIn(text, section)
        for text in ['saveReviewed', 'saveExample', 'isLocked = true']: self.assertNotIn(text, section)

    def test_ui_has_load_empty_retry_buffer_and_clear_boundary(self):
        app = self.app()
        for text in ['merchant.industry.loading', 'merchant.industry.empty', 'merchant.industry.retry', 'merchant.industry.reload',
                     'merchant.industry.cancel', 'merchant.industry.apply', 'merchant.industry.replaceHint', 'merchant.industry.reviewBody']:
            self.assertIn(text, app)
        self.assertNotIn('URLSession', app); self.assertNotIn('publish(', app)

    def test_bilingual_fragment_and_interpolation_are_complete(self):
        fragment = json.loads(read('Resources/MerchantStoreIndustryLocalizations.fragment.json'))
        source = self.app() + read('Core/MerchantOperationsReading.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', source)
        keys = set(re.findall(r'"(merchant\.industry\.[A-Za-z]+)"', source))
        keys.add('merchant.industry.currentID %lld')
        self.assertEqual(set(fragment), keys); self.assertEqual(len(fragment), 22)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])

    def test_authored_core_tests_cover_real_adapter_gate_readback_failure_and_recovery(self):
        tests = read('Tests/CoreTests/MerchantStoreIndustryTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 19)
        for text in ['testIndustryAloneMakesNewDecorChoiceReviewable', 'testSingleSelectionChangesOnlyIndustryAndAppliesOnce',
                     'testMissingSavedIndustryRemainsUntilUserChoosesReplacement', 'testNewerReloadWinsOverOutOfOrderCatalog',
                     'testProjectPermissionAloneCannotReadIndustryPicker', 'testAcknowledgedSaveWithFailedReadbackCannotBeReplayed',
                     'transport.replies += [access, canonical]; await owner.load()', 'testNoApprovalStillPreventsStoreWrite']:
            self.assertIn(text, tests)

    def test_authored_ui_tests_cover_cancel_review_discard_save_reload(self):
        tests = read('Tests/AppUITests/MerchantStoreIndustryFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 3)
        for text in ['merchant.industry.cancel', 'merchant.industry.review.previous', 'merchant.industry.review.new',
                     'app.alerts.buttons["merchant.operations.keepEditing"]', 'app.alerts.buttons["merchant.operations.discardReload"]',
                     'keepEditing.waitForExistence(timeout: 5)', 'discardReload.waitForExistence(timeout: 5)',
                     'merchant.operations.exampleSaved', 'merchant.industry.reload']:
            self.assertIn(text, tests)


if __name__ == '__main__': unittest.main()
