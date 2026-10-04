"""Source-level guards only; does not run Swift, Apple UI or a service."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class MerchantBusinessStatusChecks(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_status_domain_and_owner_are_typed_and_separate(self):
        value = self.read('Core/MerchantOperationsContracts.swift')
        status = value.split('public enum MerchantBusinessStatus:',1)[1]
        self.assertIn('case closed = 0, open = 1', status)
        self.assertIn('public let merchantID: Int', status)
        self.assertIn('guard merchantID > 0', status)
        self.assertNotIn('accountStatus', status)
        self.assertIn('case .businessStatus: return profileWrite && identity.allows(.basicRead)', value)
    def test_write_is_one_exact_form_with_no_client_owner(self):
        draft = self.read('Core/MerchantOperationsDraft.swift')
        self.assertIn('path: "api/merchant/business-status/update", form: ["business_status": String(value.status.rawValue)]', draft)
        service = self.read('Core/MerchantOperationsService.swift')
        self.assertIn('application/x-www-form-urlencoded; charset=utf-8', service)
        self.assertIn('components.percentEncodedQuery', service)
        self.assertIn('proposed.merchantID == original.merchantID', service)
        self.assertIn('"api/merchant/business-status", body: .none', service)
    def test_save_reuses_scoped_preflight_and_storefront_unknown_lock(self):
        draft = self.read('Core/MerchantOperationsDraft.swift')
        self.assertIn('case .profile, .decor, .gallery, .story, .businessStatus: return "merchant:storefront"', draft)
        service = self.read('Core/MerchantOperationsService.swift')
        for fence in ['approval.allows','access.allows(draft.destination)','fresh == .draft(baseline)','try checkSession()']:
            self.assertIn(fence, service)
        save = service.split('public func save(',1)[1]
        self.assertLess(save.index('try journal.write(record)'),save.index('transport.send(request)'))
    def test_authoritative_readback_clears_and_does_not_resubmit(self):
        value = self.read('Core/MerchantOperationsReading.swift')
        self.assertIn('if destination == .profile || destination == .businessStatus', value)
        block = value.split('if destination == .profile || destination == .businessStatus',1)[1].split('\n            } else {',1)[0]
        self.assertIn('document = nil; baseline = nil; draft = nil', block)
        self.assertIn('let current = try await reader.document(destination)', block)
        self.assertIn('returnedStatus.merchantID == original.merchantID', block)
        self.assertNotIn('saveReviewed', block)
    def test_ordinary_navigation_and_frozen_localized_review(self):
        self.assertIn('[.profile, .businessStatus, .decor', self.read('App/MerchantOperationsViews.swift'))
        editor = self.read('App/MerchantOperationsEditor.swift')
        self.assertIn('merchant.operations.status.picker',editor)
        self.assertIn('line.key == "merchant.operations.businessStatus"',editor)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key in ['businessStatus','statusOpen','statusClosed','statusHint','statusReadback','statusReadbackFailed']:
            self.assertEqual(set(catalog['merchant.operations.'+key]['localizations']), {'en','zh-Hans'})
    def test_no_production_activation_or_media_rewrite(self):
        cache = self.read('App/RetainedImageContextCache.swift')
        self.assertIn('enabled: false, approvedOrigins: []',cache)
        self.assertIn('nativeSelectionEnabled = false',self.read('App/RetainedImagePresenterHost.swift'))
        session = self.read('App/AppSession.swift')
        self.assertNotIn('business-status/update',session)
    def test_runtime_negative_coverage_is_authored_not_executed(self):
        tests = self.read('Tests/CoreTests/MerchantOperationsTests.swift')
        for name in ['testRoleABAEpochPreventsSecondRead','testLatePriorReadCannotReplaceNewScopeDocument','testReadbackCannotAdoptDifferentMerchantOwner','testDormantServiceExactFormAndUnknownPersistentReplayLock','testCancelAndStaleConfirmationSendNothing']:
            self.assertIn('func '+name,tests)
