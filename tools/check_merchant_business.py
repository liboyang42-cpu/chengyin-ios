#!/usr/bin/env python3
"""Offline advisory source/fixture checks only. Not Swift compiler or runtime evidence."""
import json,pathlib,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'app-audit'
CORE='\n'.join(p.read_text() for p in (ROOT/'Core').glob('Merchant*.swift') if p.name.startswith(('MerchantBusiness','MerchantRedemptionContext','MerchantAftercareEvidenceAdapter')))
APP='\n'.join(p.read_text() for p in (ROOT/'App').glob('*.swift'))
CAT=json.loads((ROOT/'Resources/MerchantBusinessLocalizations.fragment.json').read_text())
class MerchantBusinessSourceChecks(unittest.TestCase):
    def test_swift_files_exist(self):
        self.assertGreaterEqual(len(list((ROOT/'Core').glob('Merchant*.swift'))),10)
    def test_exact_api_paths_have_source_evidence(self):
        sources='\n'.join(p.read_text() for p in (SOURCE/'lib/data/api').glob('*.dart'))
        paths=set(re.findall(r'"(api/[a-z0-9_/-]+)"',CORE))
        exceptions={'api/merchant/crm/customers','api/merchant/reviews'}
        for path in paths-exceptions:
            self.assertIn('/'+path,sources,path)
    def test_no_invented_settlement_or_receipt_mutations(self):
        mutation=(ROOT/'Core/MerchantBusinessMutation.swift').read_text()
        self.assertNotIn('finance/',mutation)
        self.assertNotRegex(CORE,r'api/merchant/(?:operation/receipt|settlement/(?:create|execute|transfer))')
    def test_production_dormant_gate_has_no_urlsession(self):
        service=(ROOT/'Core/MerchantBusinessService.swift').read_text()
        self.assertIn('testingMutationTransport: (any MerchantBusinessTestTransport)? = nil',service)
        self.assertIn('guard let mutationTransport else',service)
        self.assertNotIn('URLSessionTransport()',CORE)
    def test_source_money_is_not_summed_or_double(self):
        self.assertNotRegex(CORE,r'\bDouble\(')
        self.assertNotRegex(CORE,r'\.reduce\(')
        self.assertIn('strictString: true',CORE)
    def test_all_static_localization_references_present(self):
        keys=set(re.findall(r'"(merchant\.business\.[A-Za-z0-9_.]+)"',APP+CORE))
        # Accessibility identifiers are not user-visible strings.
        keys={k for k in keys if any('"'+k+'"' in line and '.accessibilityIdentifier(' not in line for line in (APP+CORE).splitlines())}
        excluded={'merchant.business.confirm','merchant.business.dispatchDisabled','merchant.business.cancelReview','merchant.business.routePreview'}
        for key in keys-excluded:
            if key.endswith("."):
                self.assertTrue(any(existing.startswith(key) for existing in CAT), key)
                continue
            self.assertIn(key,CAT,key)
    def test_catalog_bilingual_and_nonempty(self):
        for key,row in CAT.items():
            for locale in ['en','zh-Hans']:
                self.assertTrue(row['localizations'][locale]['stringUnit']['value'],(key,locale))
    def test_fixture_json_literals_valid(self):
        source=(ROOT/'Core/MerchantBusinessSyntheticFixtures.swift').read_text()
        fixtures=re.findall(r'public static let (\w+) = ##"(.*?)"##',source)
        self.assertEqual(len(fixtures),11)
        for name,raw in fixtures: self.assertIsInstance(json.loads(raw),(dict,list),name)
    def test_fixture_no_real_contact_or_account_data(self):
        source=(ROOT/'Core/MerchantBusinessSyntheticFixtures.swift').read_text()
        self.assertIn('138****0000',source)
        self.assertNotRegex(source,r'(?<!\d)1\d{10}(?!\d)')
    def test_station_identifier_is_separate(self):
        source=(ROOT/'Core/MerchantRedemptionContext.swift').read_text()
        self.assertIn('stationRegistration(MerchantStationRegistrationID)',source)
        self.assertIn('"registrationMerchantId": String(id.rawValue)',source)
        self.assertNotIn('?? object.mbInt("id"',source)
    def test_unknown_journal_has_no_expiry_or_payload(self):
        source=(ROOT/'Core/MerchantBusinessCoordinator.swift').read_text()
        intent=source.split('@MainActor public protocol')[0]
        self.assertNotRegex(intent,r'let (token|code|content|phone|expiresAt):')
        self.assertNotIn('timeInterval',source)
        self.assertIn('options: .atomic',source)
    def test_authorization_refresh_before_journal_reserve(self):
        source=(ROOT/'Core/MerchantBusinessCoordinator.swift').read_text().split('public func confirm')[1]
        self.assertLess(source.index('reader.snapshot'),source.index('journal.reserve'))
        self.assertLess(source.index('latest == review.baseline'),source.index('journal.reserve'))
        self.assertLess(source.index('journal.reserve'),source.index('reader.execute'))
    def test_utf16_source_limits(self):
        self.assertIn('value.utf16.count',(ROOT/'Core/MerchantBusinessMutation.swift').read_text())
    def test_host_fixture_optin(self):
        source=(ROOT/'App/MerchantBusinessFixtureSupport.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('--uitesting-merchant-business-scenario',source)
if __name__=='__main__': unittest.main(verbosity=2)
