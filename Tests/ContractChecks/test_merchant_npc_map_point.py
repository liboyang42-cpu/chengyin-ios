"""Static source contracts only; does not compile Swift, exercise iOS, or call a service."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT/path).read_text()
CORE = read('Core/MerchantNPCMapPoint.swift')
APP = read('App/MerchantNPCMapPointView.swift')
DRAFT = read('Core/MerchantOperationsDraft.swift')
SERVICE = read('Core/MerchantOperationsService.swift')
READING = read('Core/MerchantOperationsReading.swift')

class MerchantNPCMapPointContracts(unittest.TestCase):
    def test_point_contract_requires_valid_pair_and_reuses_range_validator(self):
        for value in ['RoamCoordinate(latitude: lat, longitude: lng)', 'Double(latitude.trimmingCharacters', 'Double(longitude.trimmingCharacters', 'coordinate == nil', 'id > 0']:
            self.assertIn(value, CORE)
        for value in ['latitude > 0', 'longitude > 0', 'latitude != 0', 'longitude != 0']:
            self.assertNotIn(value, CORE)
    def test_manual_datum_is_explicit_with_no_conversion_or_native_map(self):
        self.assertIn('guard confirmedDatum == .gcj02', CORE)
        self.assertIn('confirmedDatum = nil', APP)
        for forbidden in ['import MapKit', 'CLLocationManager', 'requestLocation', 'requestWhenInUseAuthorization', 'MKLocalSearch', 'CLGeocoder', 'RuntimeLocationProjection', 'UserAnnotation', 'URLSession']:
            self.assertNotIn(forbidden, APP+CORE)
    def test_only_three_source_patch_fields_and_no_client_verification(self):
        fields=CORE.split('public var fields:')[1]
        self.assertEqual(set(re.findall(r'"([A-Za-z]+)":', fields)), {'locationLat','locationLng','address'})
        self.assertNotIn('locationVerified', APP+CORE)
        self.assertIn('case .npcMapPoint(let value): return [try .init(path: "api/merchant/decor/save", fields: value.fields)]', DRAFT)
    def test_read_requires_owner_and_coop_while_writer_still_requires_both(self):
        self.assertIn('case .npcMapPoint: return profileWrite && cooperationManage', read('Core/MerchantOperationsContracts.swift'))
        self.assertIn('destination == .npcMapPoint ? access.cooperationManage : access.allows(destination)', SERVICE)
        branch=SERVICE.split('case .npcMapPoint:')[1].split('case .businessStatus:')[0]
        self.assertIn('"api/merchant/coop-profile", body: .json',branch)
        self.assertIn('value.merchantID == access.identity.merchantID',branch)
    def test_save_uses_existing_preflight_and_shared_unknown_lock(self):
        self.assertIn('case .npcMapPoint: return "merchant:storefront"',DRAFT)
        for token in ['fresh == .draft(baseline)','access.allows(draft.destination)','approval.allows','try journal.write(record)','checkSession()','proposed.merchantID == original.merchantID']:
            self.assertIn(token,SERVICE)
        self.assertLess(SERVICE.index('try journal.write(record)'),SERVICE.index('transport.send(request)',SERVICE.index('public func save(')))
    def test_acknowledgment_cannot_replace_server_readback(self):
        self.assertIn('|| destination == .npcMapPoint',READING)
        start=READING.index('if destination == .profile || destination == .businessStatus')
        block=READING[start:].split('\n            } else {')[0]
        for token in ['document = nil; baseline = nil; draft = nil','let current = try await reader.document(destination)','returnedPoint.merchantID == original.merchantID','merchantMapPoint.readbackFailed']:
            self.assertIn(token,block)
        self.assertNotIn('saveReviewed(',block)
    def test_exact_scoped_sheet_fences_and_one_local_apply(self):
        for token in ['!consumed','owner.isCurrent','!owner.isBusy','!owner.isLocked','owner.confirmation == nil','owner.reader.scope == scope','owner.draftIdentity == draftIdentity','owner.draft == .npcMapPoint(original)']:
            self.assertIn(token,APP)
        self.assertEqual(APP.count('document.edit('),1)
        apply=APP.split('@discardableResult func apply() -> Bool')[1].split('func cancel()')[0]
        self.assertIn('consumed = true',apply);self.assertIn('document.edit(.npcMapPoint(candidate))',apply)
        self.assertNotIn('saveReviewed(',APP)
    def test_cancel_background_reload_and_account_change_close_sheet(self):
        for token in ['phase != .active','cancelManual(); document.cancel()','document.coordinator.draftIdentity','document.coordinator.reader.scope','.onDisappear { model.cancel() }']:
            self.assertIn(token,APP)
    def test_character_hosts_entry_and_only_map_case_hosts_new_fields(self):
        editor=read('App/MerchantOperationsEditor.swift')
        character=editor.split('case .character(let value):')[1].split('case .template(let value):')[0]
        self.assertIn('MerchantNPCMapPointEntry(document: model)',character)
        self.assertIn('case .npcMapPoint:\n            MerchantNPCMapPointFields(document: model)',editor)
        self.assertIn('destination: .npcMapPoint',APP)
    def test_review_uses_only_frozen_point_fields(self):
        review=DRAFT.split('public var reviewLines:')[1].split('case .businessStatus')[0]
        for token in ['v.latitude','v.longitude','v.address','"GCJ-02"']:
            self.assertIn(token,review)
    def test_all_new_visible_text_is_bilingual_and_discloses_limits(self):
        catalog=json.loads(read('Resources/MerchantNPCMapPointLocalizations.fragment.json'))['strings']
        visible=re.sub(r'\.accessibilityIdentifier\([^\n]*\)','',APP+CORE+READING)
        keys=set(re.findall(r'"(merchantMapPoint\.[a-zA-Z]+)"',visible))
        self.assertFalse(keys-set(catalog))
        for key in catalog:
            for lang in ['en','zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][lang]['stringUnit']['value'])
        self.assertIn('not available',catalog['merchantMapPoint.mapUnavailable']['localizations']['en']['stringUnit']['value'])
        self.assertIn('does not certify',catalog['merchantMapPoint.displayOnly']['localizations']['en']['stringUnit']['value'])
    def test_access_fixtures_supply_real_required_identity_fields(self):
        core=read('Tests/CoreTests/MerchantNPCMapPointTests.swift')
        roles=set(re.findall(r'= "(MERCHANT_[A-Z]+)"',read('Core/MerchantAccess.swift')))
        fixtures=[json.loads(value) for value in re.findall(r'#"(\{.*?\})"#',core) if '"active":true' in value]
        self.assertEqual(len(fixtures),2)
        for value in fixtures:
            self.assertGreater(value['merchant']['id'],0)
            self.assertIn(value.get('roleCode'),roles)
            self.assertIsInstance(value['permissions'],list)
        matrix=core.split('func testReadAndWritePermissionMustBothBePresent()')[1].split('func testPointShares')[0]
        self.assertIn('"roleCode": "MERCHANT_OWNER"',matrix)
        self.assertIn('"merchant": ["id": 31]',matrix)
        app=read('Tests/AppUnitTests/MerchantNPCMapPointTests.swift')
        self.assertIn('let reader = MerchantOperationsFixtureReader()',app)
        shared=read('Core/MerchantOperationsSyntheticFixtures.swift')
        self.assertIn('"roleCode": "MERCHANT_OWNER"',shared)
        self.assertIn('"merchant": ["id": 31',shared)
    def test_focused_runtime_cases_exist_without_claiming_execution(self):
        tests=read('Tests/CoreTests/MerchantNPCMapPointTests.swift')
        app=read('Tests/AppUnitTests/MerchantNPCMapPointTests.swift')
        for name in ['testUnknownWriteStaysLockedAfterRefreshAndReentry','testAcknowledgedSaveWithFailedReadbackDoesNotReplayOrInventSuccess','testAccountChangeBeforeConfirmAndDuringReadBlocksWrite','testForeignReadbackIsDiscarded','testRoleRevocationBeforeWriteNeverSendsPatch']:
            self.assertIn('func '+name,tests)
        for name in ['testConcurrentEditRejectsOldSheet','testUnknownAndWGS84AreRejectedWithoutConversion','testReloadSamePointInvalidatesOldSheet','testCancellationClearsInputAndDisallowsLateApply']:
            self.assertIn('func '+name,app)

if __name__ == '__main__': unittest.main()
