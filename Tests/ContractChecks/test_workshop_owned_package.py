"""Immutable package metadata/frozen terms source checks; not Swift execution."""
from pathlib import Path
import json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class WorkshopOwnedPackageContracts(unittest.TestCase):
 def source(self,path):return (ROOT/path).read_text()
 def test_closed_metadata_never_becomes_content_or_paid_access(self):
  s=self.source('Core/WorkshopOwnedPackage.swift')
  for value in ['workshop-package-v1','FREE_INDIVIDUAL_ONLY','PACKAGE_METADATA_ONLY','NOT_AVAILABLE','POST_INSTALL_POLICY_UNAVAILABLE','exactKeys','packageInfo != nil']:
   self.assertIn(value,s)
  for value in ['public let content:', 'public let terms:', 'public let owner', 'public let seller', 'Codable', 'PERPETUAL_PURCHASED_VERSION']:self.assertNotIn(value,s)
 def test_explicit_frozen_rights_and_limits(self):
  s=self.source('Core/WorkshopOwnedPackage.swift')
  for value in ['maximum >= 0','!unlimited || maximum == 0','EXACT_PURCHASED_VERSION','PROHIBITED','regions.count < 64','seen.insert(region).inserted','requiredBindingCount','schemaVersion == 1']:
   self.assertIn(value,s)
 def test_separate_approval_is_off_and_context_bound(self):
  s=self.source('Core/WorkshopOwnedPackageService.swift')
  for value in ['approval: WorkshopOwnedPackageReadApproval? = nil','currentApproval: @escaping () -> WorkshopOwnedPackageReadApproval? = { nil }','latest.revision == approval.revision','now < expiresAt']:
   self.assertIn(value,s)
  c=self.source('App/WorkshopOwnedComposition.swift')
  self.assertIn('packageApproval: WorkshopOwnedPackageReadApproval? = nil',c)
  self.assertIn('if let packageApproval, packageApproval.matches(context)',c)
  self.assertNotIn('WorkshopOwnedPackageReadApproval(',c)
 def test_exact_bounded_request_and_post_transport_lifetime(self):
  s=self.source('Core/WorkshopOwnedPackageService.swift')
  for value in ['api/workshop/owned/package','claim_id=','Content-Length','Cache-Control','data.count <= 65_536','ContentDraftJSON.parse(text)','try check(lifetime); onUnauthorized(lease.context)','try check(lifetime); result = try await transport.send(request); try check(lifetime)','value.claimId == claimId']:
   self.assertIn(value,s)
  for value in ['owner=', 'buyer=', 'purchase(', 'install(', 'refund(', 'URLSession', 'UserDefaults']:self.assertNotIn(value,s)
 def test_replacement_and_parent_exit_retire_package_lifetime(self):
  s=self.source('Core/WorkshopOwnedPackageBrowser.swift')
  self.assertIn('close()\n        guard WorkshopOwnedWire.identifier',s)
  for value in ['generation == ticket','reader.read(claimId: claimId, lifetime: readLifetime)','lease.revoke()','public func close()']:self.assertIn(value,s)
  parent=self.source('Core/WorkshopOwnedBrowser.swift')
  self.assertIn('packageBrowser?.invalidate()',parent);self.assertIn('packageBrowser?.close()',parent)
 def test_vertical_detail_navigation_and_long_accessible_metadata(self):
  s=self.source('App/WorkshopOwnedPackageView.swift');parent=self.source('App/WorkshopOwnedLibraryView.swift')
  self.assertIn('.navigationDestination(isPresented: $navigation.showsPackage)',parent)
  self.assertIn('.onDisappear { navigation.detailDisappeared() }',parent)
  for value in ['.onAppear {', '.onDisappear { navigation.packageDisappeared() }', 'frozenRights','limitNotice','manifestUnavailable','editorUnavailable','Text(verbatim:']:
   self.assertIn(value,s)
  for value in ['TextEditor','WebView','URLSession','AsyncImage','Link(','.lineLimit(1)','height:']:self.assertNotIn(value,s)
 def test_copy_is_bilingual_and_explicitly_not_runtime_capability(self):
  catalog=json.loads(self.source('Resources/WorkshopOwned.xcstrings'))['strings'];s=self.source('App/WorkshopOwnedPackageView.swift')
  self.assertIn('tableName: "WorkshopOwned"',s)
  keys=set(re.findall(r'packageText\("([A-Za-z.]+)"\)',s))|set(re.findall(r'key: "([A-Za-z.]+)"',s))
  for key in keys:
   if key.endswith('.'):continue
   entry=catalog['workshopOwned.package.'+key];self.assertEqual(set(entry['localizations']),{'en','zh-Hans'})
  notice=catalog['workshopOwned.package.limitNotice']['localizations']['en']['stringUnit']['value']
  self.assertIn('frozen',notice.lower())
 def test_suspended_transport_regressions_authored(self):
  s=self.source('Tests/CoreTests/WorkshopOwnedPackageTests.swift')
  for value in ['WorkshopOwnedPackageService(', 'withCheckedThrowingContinuation','testNewSelectionRetiresOld401','testInvalidSelectionRetiresOldRead','testCloseAndCancelledReadSuppressLate401','testCurrent401StillNotifies','testSeparateApprovalDefaultsOff','testMissingOrPrivateFieldsFailClosed']:
   self.assertIn(value,s)
if __name__=='__main__':unittest.main()
