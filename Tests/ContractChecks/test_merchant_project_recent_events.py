import pathlib,unittest
R=pathlib.Path(__file__).resolve().parents[2]
CORE=(R/'Core/MerchantProjectRecentEvents.swift').read_text();MODEL=(R/'App/MerchantProjectRecentEventsView.swift').read_text();HOST=(R/'App/MerchantProjectsView.swift').read_text();EVENT=(R/'Core/MerchantContracts.swift').read_text()
class Contract(unittest.TestCase):
 def test_01_exact_pair(self):self.assertIn('event.projectOwnerType == ownerType && event.projectOwnerID == ownerID',CORE)
 def test_02_unknown_no_fallback(self):self.assertIn('default: return nil',CORE)
 def test_03_order_no_badge(self):self.assertIn('events.filter(matches)',CORE);self.assertNotIn('.sorted',CORE)
 def test_04_existing_reads_only(self):self.assertIn('reader.merchantEvents(access: access)',MODEL);self.assertNotIn('URLRequest',MODEL)
 def test_05_fresh_order(self):self.assertLess(MODEL.index('await reader.merchantAccess()'),MODEL.index('await reader.merchantProjects'));self.assertLess(MODEL.index('await reader.merchantProjects'),MODEL.index('await reader.merchantEvents'))
 def test_06_existing_permission(self):self.assertIn('access.isOwner, access.merchantID == merchantID, access.allows(.projects)',MODEL)
 def test_07_project_recheck(self):self.assertIn('guard page.rows.contains(project)',MODEL)
 def test_08_context_checks(self):self.assertIn('reader.sessionRevision == revision',MODEL);self.assertIn('sourceIsCurrent()',MODEL);self.assertIn('!Task.isCancelled',MODEL)
 def test_09_epoch(self):self.assertIn('generation == request',MODEL);self.assertIn('generation = UUID(); rows = nil',MODEL)
 def test_10_refresh_clears(self):self.assertIn('generation = request; rows = nil; errorKey = nil; loading = true',MODEL)
 def test_11_background(self):self.assertIn('if phase != .active { model.retire() }',MODEL);self.assertIn('.onDisappear { model.retire() }',MODEL)
 def test_12_normal_host(self):self.assertIn('MerchantProjectRecentEventsView(reader: reader',HOST);self.assertIn('snapshot.access.isOwner',HOST);self.assertIn('current.id == snapshot.id',HOST)
 def test_13_metadata_only(self):self.assertIn('content = try c.decode(String.self, forKey: .content)',EVENT);self.assertIn('time = try c.decode(String.self, forKey: .time)',EVENT);self.assertIn('projectOwnerType: String? = nil',EVENT)
 def test_14_retry_empty_results(self):
  for key in ['retry','empty','row.','refresh']:self.assertIn('merchant.projectEvents.'+key,MODEL)
 def test_15_no_mutations(self):
  for text in ['confirmUpload','createTemplate','requestPermission','merchant:finance:read','markAsRead','unreadCount']:self.assertNotIn(text,MODEL)
 def test_16_existing_fields_not_repurposed(self):self.assertIn('project.bizType',CORE);self.assertNotIn('project.ownerType',CORE)
 def test_17_fake_negative_coverage(self):
  tests=(R/'Tests/AppUnitTests/MerchantProjectRecentEventsTests.swift').read_text()
  for name in ['testRetireSuppressesLateResult','testOverlappingReadLatestResultWins','testOwnerDeniedNoDataReads','testSourceRevokedAfterProjectStopsEvents']:self.assertIn(name,tests)
if __name__=='__main__':unittest.main()
