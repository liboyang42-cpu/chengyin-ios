"""Source-backed offline checks. These do not compile or run Swift/iOS."""
import json
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = os.environ.get("CHENGYIN_FLUTTER_SOURCE_ROOT")

class MerchantDiscoveryRedemptionContracts(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()
    def test_discovery_backend_tags_are_exact_and_all_uses_empty_name(self):
        text = self.read("Core/MerchantDiscovery.swift")
        for tag in ["夜间友好", "可拍照", "适合组队", "宠物友好", "安静", "适合亲子"]:
            self.assertIn('"' + tag + '"', text)
        self.assertIn('["name": ""] : ["tags": rawValue]', text)
        service = self.read("Core/SearchMapService.swift").split('public func merchantDiscovery')[1].split('public func categories')[0]
        self.assertIn('json("api/merchant/list", fields: tag.fields', service)
        self.assertIn('SearchMapValue<[MerchantDiscoveryRow]>', service)
    def test_discovery_owner_identity_chips_and_media_boundary(self):
        text = self.read("Core/MerchantDiscovery.swift")
        self.assertIn('memberId.flatMap(PublicMerchantOwnerID.init)', text)
        self.assertIn('map(PublicMerchantHomeTarget.ownerMemberID)', text)
        self.assertNotIn('legacyMerchantRowID', text)
        self.assertIn('\\u{FF0C}\\u{FF1B}\\u{3001}', text)
        self.assertIn('(role + values).prefix(3)', text)
        view = self.read('App/MerchantDiscoverView.swift')
        self.assertIn('publicMerchant.image', view)
        self.assertNotIn('AsyncImage', view)
        self.assertIn('key == captured, gate.accepts', view)
        self.assertIn('.onDisappear { gate.invalidate()', view)
    def test_normal_search_and_permission_checked_workbench_entries(self):
        self.assertIn('MerchantDiscoverView(reader: reader, publicMerchant: publicMerchant)', self.read('App/GlobalSearchView.swift'))
        self.assertIn('publicMerchant: session.publicMerchantHomeContext', self.read('App/SessionGlobalSearchView.swift'))
        home = self.read('App/MerchantBusinessViews.swift')
        verify = home.split('if access.allows("merchant:verify")')[1].split('} else if loading')[0]
        self.assertIn('CityNodeRedeemView(reader: reader, journal: journal)', verify)
    def test_redemption_request_exactness_and_message_preservation(self):
        text = self.read('Core/CityNodeRedemption.swift')
        self.assertIn('.form("api/verify/citynode/redeem", ["code": value])', text)
        result = text.split('public struct CityNodeRedemptionResult')[1].split('public struct CityNodeRedemptionReview')[0]
        self.assertIn('redeemed = code == 200', result)
        self.assertIn('message = text', result)
        self.assertNotIn('trimmingCharacters', result)
        self.assertNotIn('mbText', result)
        self.assertIn('Text(verbatim: result.message)', self.read('App/CityNodeRedeemView.swift'))
    def test_dormant_default_and_before_dispatch_access_locks(self):
        service = self.read('Core/MerchantBusinessService.swift')
        self.assertIn('testingMutationTransport: (any MerchantBusinessTestTransport)? = nil', service)
        text = self.read('Core/CityNodeRedemption.swift')
        prepare = text.split('public func prepare')[1].split('public func cancelReview')[0]
        self.assertLess(prepare.index('service.canExecuteSyntheticMutation'), prepare.index('currentSession()'))
        confirm = text.split('public func confirm')[1].split('private func intent')[0]
        self.assertLess(confirm.index('service.access'), confirm.index('journal.reserve'))
        self.assertLess(confirm.index('access.merchantID == frozen.merchantID'), confirm.index('journal.reserve'))
        self.assertLess(confirm.index('journal.reserve'), confirm.index('service.syntheticEnvelope'))
        self.assertIn('target: "redemption"', text)
        self.assertIn('reserved == nil ? errorKey(error) : "merchant.cityRedeem.unknown"', confirm)
        self.assertNotIn('journal.complete', text.split('public func invalidate')[1].split('public func confirm')[0])
        self.assertNotIn('URLSession', text)
    def test_native_presentation_avoids_scanner_dialog_stacking(self):
        text = self.read('App/CityNodeRedeemView.swift')
        self.assertIn('.confirmationDialog(', text)
        self.assertIn('onDismiss:', text)
        self.assertIn('scannedCode = payload', text)
        self.assertIn('lifetime == captured', text)
        self.assertIn('phase != .active { clear() }', text)
        self.assertIn('codeFocused = false', text)
        self.assertIn('.onDisappear { visible = false; clear() }', text)
        self.assertIn('.disabled(!model.coordinator.isAvailable', text)
    def test_bilingual_catalog_additions(self):
        entries = json.loads(self.read('docs/merchant-discovery-redemption-localizations.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(entries), 34)
        for row in entries:
            for locale in ['en', 'zh-Hans']:
                self.assertEqual(row[locale], catalog[row['key']]['localizations'][locale]['stringUnit']['value'])
    def test_authored_runtime_tests_cover_lifecycle_and_unknown_outcomes(self):
        text = self.read('Tests/CoreTests/CityNodeRedemptionTests.swift')
        for test in ['testDefaultDisabledStopsBeforeSessionPermissionOrTransport', 'testReviewCancellationHasNoMutationAndConfirmationRechecksAccess',
                     'testPermissionRevocationOrMerchantChangeBeforeConfirmationNeverDispatches', 'testTimeoutLeavesDurableCoarseLockAcrossNextAndNewEpoch',
                     'testDismissedInFlightResponseCannotShowResultOrClearJournal', 'testLogoutBeforeConfirmInvalidatesConsentWithoutMutation']:
            self.assertIn(test, text)
    @unittest.skipUnless(SOURCE, 'NOT_RUN: supply CHENGYIN_FLUTTER_SOURCE_ROOT for external source evidence')
    def test_external_flutter_source_contracts(self):
        source = Path(SOURCE)
        api = (source/'lib/data/api/merchant_api.dart').read_text()
        page = (source/'lib/feature/merchant/merchant_discover_page.dart').read_text()
        roam = (source/'lib/data/api/roam_api.dart').read_text()
        redeem = (source/'lib/feature/merchant/city_node_redeem_page.dart').read_text()
        self.assertIn("data: <String, dynamic>{'tags': tag}", api)
        self.assertIn("searchByName('')", page)
        self.assertIn("/merchant/public-home/member/$memberId", page)
        self.assertIn("'/api/verify/citynode/redeem'", roam)
        self.assertIn("FormData.fromMap(<String, dynamic>{'code': code})", roam)
        self.assertIn('redeemCityNodeCode(code)', redeem)
        self.assertIn('_controller.stop()', redeem)
        for tag in ['夜间友好', '可拍照', '适合组队', '宠物友好', '安静', '适合亲子']:
            self.assertIn("'" + tag + "'", page)

if __name__ == '__main__': unittest.main()
