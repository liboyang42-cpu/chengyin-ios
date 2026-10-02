#!/usr/bin/env python3
"""Advisory offline contract, privacy, localization and fixture checks; never Swift/Xcode evidence."""
import base64,io,json,pathlib,re,unittest,zipfile,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[1]
CORE='\n'.join(p.read_text() for pattern in ['MerchantEngagement*.swift','MerchantEvidenceSelection.swift','MerchantMutationFailureDisposition.swift','MerchantOperatorInviteRoute.swift'] for p in (ROOT/'Core').glob(pattern))
APP='\n'.join(p.read_text() for pattern in ['MerchantEngagement*.swift','MerchantEvidenceSelectionView.swift','MerchantOperatorInvitationLandingView.swift'] for p in (ROOT/'App').glob(pattern))
CAT=json.loads((ROOT/'Resources/MerchantEngagementLocalizations.fragment.json').read_text())
SOURCE='\n'.join(p.read_text() for p in (ROOT.parent/'app-audit/lib/data/api').glob('*.dart'))
class Checks(unittest.TestCase):
 def test_static_paths_exist_in_source(self):
  for path in set(re.findall(r'"(api/[a-z0-9_/-]+)"',CORE)):
   self.assertIn('/'+path,SOURCE,path)
 def test_no_invented_receipt_permission_or_invite_preview_endpoint(self):
  for forbidden in ['terminal-receipt','invite/preview','export-token/refresh','permissions/update']:
   self.assertNotIn(forbidden,CORE)
 def test_default_action_transport_is_nil(self):
  self.assertIn('testingActionTransport: (any MerchantBusinessTestTransport)? = nil',CORE)
  self.assertNotIn('URLSessionTransport()',CORE+APP)
 def test_campaign_creation_does_not_chain_dispatch(self):
  service=(ROOT/'Core/MerchantEngagementService.swift').read_text()
  self.assertNotIn('dispatchCampaign(',service)
 def test_export_token_uses_header_only(self):
  self.assertIn('forHTTPHeaderField: "X-CRM-Export-Token"',CORE)
  self.assertNotRegex(CORE,r'queryItems.*downloadToken')
  self.assertNotRegex(CORE,r'appendingPathComponent\(.*downloadToken')
 def test_recovery_records_exclude_credentials(self):
  code=(ROOT/'Core/MerchantEngagementCoordinator.swift').read_text().split('@MainActor public protocol')[0]
  for key in ['token','content','phone','bytes','filter']:
   self.assertNotRegex(code,rf'let {key}\b')
 def test_contact_once_only_and_bound_scope(self):
  code=(ROOT/'Core/MerchantEngagementCoordinator.swift').read_text().split('public func consumeContact')[1]
  self.assertIn('reader.scope == captured',code)
  self.assertLess(code.index('clearSensitiveReceipt()\n        try await delivery'),code.index('deliverSynthetic(phone:'))
 def test_preflight_before_reserve_then_send(self):
  code=(ROOT/'Core/MerchantEngagementCoordinator.swift').read_text().split('public func confirm')[1]
  self.assertLess(code.index('reader.proof'),code.index('journal.reserve'))
  self.assertLess(code.index('fresh == frozen.proof'),code.index('journal.reserve'))
  self.assertLess(code.index('journal.reserve'),code.index('reader.execute'))
 def test_server_errors_remain_unknown(self):
  self.assertIn('MerchantMutationFailureDisposition.provesNoDispatch(error)',CORE)
  self.assertIn('error as? MerchantBusinessFailure == .disabled',CORE)
 def test_photo_selection_binds_account_and_store(self):
  self.assertIn('scope == selectedScope, grant.merchantID == merchantID',CORE)
  self.assertIn('currentScope() == selectedScope',APP)
 def test_native_device_grants_default_off(self):
  self.assertIn('deviceEffectsAllowed: Bool = false',APP)
  self.assertIn('var deviceExportAllowed = false',APP)
  self.assertIn('nativeSelectionEnabled: false',APP)
  self.assertIn('var cameraSelectionEnabled = false',APP)
 def test_invite_route_exact_and_token_hidden(self):
  self.assertIn('path == "/merchant/team"',CORE)
  self.assertIn('tokens.count == 1',CORE)
  self.assertNotIn('Text(invitation.token)',APP)
 def test_all_static_localization_keys(self):
  count_fields={"filterTotalCount"}
  for array in re.findall(r"public static let (?:campaignKeys|broadcastKeys|countKeys) = \[([^\]]+)\]",CORE):
   count_fields.update(re.findall(r'"([^"\n]+)"',array))
  self.assertGreater(len(count_fields),10)
  def enum_values(name):
   body=re.search(r"public enum "+name+r"[^\{]*\{([^}]+)\}",CORE).group(1)
   raw=re.findall(r'= "([^"]+)"',body)
   return raw or re.findall(r"\b(?:case\s+)?(call|copy)\b",body)
  command_body=CORE.split('public var key: String {',1)[1].split('public var lockTarget',1)[0]
  status_body=re.search(r'private let known = \[([^\]]+)\]',APP).group(1)
  families={"count":count_fields,"channel":enum_values("MerchantCampaignChannel"),
   "scope":enum_values("MerchantBroadcastScope"),"contact":enum_values("MerchantContactPurpose"),
   "command":re.findall(r'return "([^"]+)"',command_body),"status":re.findall(r'"([^"]+)"',status_body)}
  prefixes={"merchant.engagement."+family+"." for family in families}
  for family, values in families.items():
   self.assertTrue(values,family)
   for value in values: self.assertIn("merchant.engagement."+family+"."+value,CAT,(family,value))
  for key in set(re.findall(r'"(merchant\.engagement\.[A-Za-z0-9_.]+)"',CORE+APP)):
   usages=[line for line in (CORE+APP).splitlines() if '"'+key+'"' in line]
   visible=any('.accessibilityIdentifier(' not in line for line in usages)
   if visible and key not in prefixes: self.assertIn(key,CAT,key)
 def test_bilingual_keys_are_nonempty(self):
  for key,row in CAT.items():
   for lang in ['en','zh-Hans']: self.assertTrue(row['localizations'][lang]['stringUnit']['value'],(key,lang))
 def test_json_fixtures_parse(self):
  code=(ROOT/'Core/MerchantEngagementSyntheticFixtures.swift').read_text()
  literals=re.findall(r'public static let (\w+) = ##"(.*?)"##',code)
  self.assertEqual(len(literals),7)
  for key,value in literals: self.assertIsInstance(json.loads(value),(list,dict),key)
 def test_workbook_fixture_is_structured_masked_and_synthetic(self):
  code=(ROOT/'Core/MerchantEngagementSyntheticFixtures.swift').read_text()
  encoded=re.search(r'workbookBytes = Data\(base64Encoded: "([^"]+)"',code).group(1)
  with zipfile.ZipFile(io.BytesIO(base64.b64decode(encoded))) as archive:
   for name in archive.namelist(): ET.fromstring(archive.read(name))
   sheet=archive.read('xl/worksheets/sheet1.xml').decode()
   self.assertEqual(sheet.count('<row '),8)
   self.assertIn('Example customer 1',sheet);self.assertIn('202***0101',sheet)
   self.assertNotRegex(sheet,r'(?<!\d)1\d{10}(?!\d)')
 def test_integrated_host_actions_stay_default_off(self):
  host=(ROOT/'App/AppSession.swift').read_text()
  self.assertIn('MerchantEngagementService(configuration:configuration,readTransport:transport)',host)
  self.assertNotIn('testingActionTransport:',host)
  self.assertEqual((ROOT/'App/QuestifyApp.swift').read_text().count('--uitesting-merchant-engagement-fixture'),2)
 def test_source_count_fields_are_not_client_sum(self):
  self.assertNotIn('.reduce(',CORE)
  self.assertIn('Missing counts are unknown, not zero',CORE)
if __name__=='__main__':unittest.main(verbosity=2)
