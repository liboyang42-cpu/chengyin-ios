"""Source and build-structure checks only; Swift/Apple execution is a separate gate."""
from pathlib import Path
import json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class WorkshopOwnedLibraryContracts(unittest.TestCase):
    def source(self,path):return (ROOT/path).read_text()
    def test_closed_free_scope_never_becomes_paid_or_refunded(self):
        s=self.source('Core/WorkshopOwnedContracts.swift')
        for marker in ['workshop-owned-v1','FREE_INDIVIDUAL_ONLY','NOT_AVAILABLE','UNAVAILABLE','"FREE"','"INDIVIDUAL"','exactKeys']:
            self.assertIn(marker,s)
        for marker in ['Codable','REFUNDED','public let content:','public let terms:','public let owner','public let license','PERPETUAL_PURCHASED_VERSION']:
            self.assertNotIn(marker,s)
    def test_bounded_list_metadata_and_unknown_states(self):
        s=self.source('Core/WorkshopOwnedContracts.swift')
        for marker in ['rows.count < 50','seen.insert(item.id).inserted','!hasMore || rows.count == 50','rows.isEmpty && !hasMore','decode(String.self, forKey: .validUntil)','guard status == .unavailable']:
            self.assertIn(marker,s)
        self.assertNotIn('Date(timeIntervalSince1970:',s)
    def test_new_reads_are_exact_and_default_off(self):
        s=self.source('Core/WorkshopOwnedService.swift')
        for marker in ['approval: WorkshopOwnedReadApproval? = nil','currentApproval: @escaping () -> WorkshopOwnedReadApproval? = { nil }','latest.revision == approval.revision','now < expiresAt','api/workshop/owned/','body: Data()','Content-Length','Cache-Control']:
            self.assertIn(marker,s)
        for marker in ['owner=', 'buyer=', 'merchant=', 'purchase(', 'install(', 'refund(', 'URLSession', 'UserDefaults']:
            self.assertNotIn(marker,s)
    def test_caller_lifetime_is_checked_before_session_side_effect(self):
        s=self.source('Core/WorkshopOwnedService.swift')
        self.assertIn('guard !revoked else { throw WorkshopOwnedIssue.staleRead }',s)
        self.assertIn('try check(lifetime); onUnauthorized(lease.context)',s)
        self.assertIn('try check(lifetime); result = try await transport.send(request); try check(lifetime)',s)
        self.assertIn('try check(lifetime); return value',s)
        b=self.source('Core/WorkshopOwnedBrowser.swift')
        for marker in ['listLifetime?.revoke()','detailLifetime?.revoke()','reader.list(lifetime: lifetime)','reader.detail(claimId: claimId, lifetime: lifetime)','listGeneration == ticket','detailGeneration == ticket','lease.revoke()']:
            self.assertIn(marker,b)
    def test_response_and_owner_detail_identity_are_bounded(self):
        s=self.source('Core/WorkshopOwnedService.swift')
        self.assertIn('data.count <= 65_536',s);self.assertIn('ContentDraftJSON.parse(text)',s)
        self.assertIn('value.item?.claimId == claimId',s)
        self.assertIn('rows.contains(where:',self.source('Core/WorkshopOwnedBrowser.swift'))
    def test_factory_does_not_create_authority_or_fetch(self):
        s=self.source('App/WorkshopOwnedComposition.swift')
        for marker in ['guard let approval','currentApproval()?.revision == approval.revision','ContentDraftContextFence.matches(current(), context)','approval: WorkshopOwnedReadApproval? = nil']:
            self.assertIn(marker,s)
        self.assertNotIn('await ',s)
    def test_vertical_navigation_and_read_only_states_exist(self):
        s=self.source('App/WorkshopOwnedLibraryView.swift')
        for marker in ['WorkshopOwnedAccountLink','WorkshopOwnedDestination','ForEach(browser.rows)', '.navigationDestination(item: $navigation.selection)', '.onDisappear { navigation.detailDisappeared() }', '.onDisappear { navigation.listDisappeared() }','case .notEnabled','case .empty']:
            self.assertIn(marker,s)
        for marker in ['TextEditor','WebView','URLSession','AsyncImage','Link(','.lineLimit(1)','height:']:
            self.assertNotIn(marker,s)
    def test_all_feature_copy_is_bilingual_and_uses_its_table(self):
        s=self.source('App/WorkshopOwnedLibraryView.swift');catalog=json.loads(self.source('Resources/WorkshopOwned.xcstrings'))
        self.assertIn('tableName: "WorkshopOwned"',s);self.assertIn('table: "WorkshopOwned", locale: locale',s)
        for key,entry in catalog['strings'].items():
            self.assertTrue(key.startswith('workshopOwned.'));self.assertEqual(set(entry['localizations']),{'en','zh-Hans'})
            for item in entry['localizations'].values():self.assertEqual(item['stringUnit']['state'],'translated');self.assertTrue(item['stringUnit']['value'])
        keys=set(re.findall(r'workshopText\("([A-Za-z.]+)"\)',s))|set(re.findall(r'key: "([A-Za-z.]+)"',s))
        self.assertLessEqual({'workshopOwned.'+k for k in keys if not k.endswith('.')},set(catalog['strings']))
        self.assertIn('without subscription renewal',catalog['strings']['workshopOwned.purchasesUnavailable']['localizations']['en']['stringUnit']['value'])
    def test_real_service_browser_regressions_are_authored(self):
        s=self.source('Tests/CoreTests/WorkshopOwnedFlowTests.swift')
        self.assertIn('let service = WorkshopOwnedService(',s);self.assertIn('let browser = WorkshopOwnedBrowser(reader: service, lease: lease)',s)
        for marker in ['CloseListSuppressesDelayed401','CloseReopenKeepsNewRead','CloseDetailSuppressesDelayed401','NewDetailRetiresOld401','CancelledListAndDetail','Current401StillNotifies','HostInvalidatesBeforeRoleTokenEpochAndRealm','InvalidationFencesIntermediateAccountABA']:
            self.assertIn(marker,s)
        self.assertGreaterEqual(len(re.findall(r'func test',s)),15)
    def test_synthetic_helpers_do_not_depend_on_inherited_default_self(self):
        s=self.source('Tests/CoreTests/WorkshopOwnedTestSupport.swift')
        self.assertIn('[WorkshopOwnedTestData.item()]',s);self.assertIn('= WorkshopOwnedTestData.item()',s)
if __name__=='__main__':unittest.main()
