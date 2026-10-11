"""Focused source contracts; not a Swift compiler or runtime test."""
import json,re,unittest
from pathlib import Path
W=Path(__file__).resolve().parents[2]
C=(W/'Core/ProfileSelfProjects.swift').read_text();A=(W/'App/ProfileSelfProjectsSection.swift').read_text();S=(W/'App/SocialPublicProfileView.swift').read_text();H=(W/'App/AccountView.swift').read_text()
class ProfileSelfProjectsSourceTests(unittest.TestCase):
 def test_01_owner(self):self.assertIn('owner.accountID == memberID, accountReader.identity == owner',C)
 def test_02_scope(self):self.assertIn('projectsReader.scope == ownerScope',C)
 def test_03_identity(self):self.assertIn('ObjectIdentifier(projectsReader)',C);self.assertIn('accountReader.presentationRevision',C)
 def test_04_config_auth(self):self.assertIn('projectsReader.isAuthenticated, projectsReader.isConfigured',C)
 def test_05_before_after(self):self.assertEqual(C.count('guard isCurrentContext else { throw CancellationError() }'),2)
 def test_06_late_failure(self):self.assertIn('guard !Task.isCancelled, isCurrentContext else { throw CancellationError() }',C)
 def test_07_no_financial_read(self):self.assertIn('func center() async throws -> CreatorContentCenter { throw APIError.invalidRequest }',C)
 def test_08_all_query(self):self.assertIn('reader.projects(query: .init())',C);self.assertNotIn('type: "topic"',C)
 def test_09_topics_before_eight(self):self.assertLess(C.index('row.bizType == "topic"'),C.index('}.prefix(8)'))
 def test_10_typed_dedup(self):self.assertIn('seen.insert(row.id).inserted',C)
 def test_11_ended_filter(self):self.assertIn('today: today) != .ended',C)
 def test_12_shanghai(self):self.assertIn('TimeZone(identifier: "Asia/Shanghai")',C)
 def test_13_day_end(self):self.assertIn('if today > end { return .ended }',C)
 def test_14_unknown_start(self):self.assertIn('guard let start = day(start) else { return nil }',C)
 def test_15_reversed_end(self):self.assertIn('let end = max(day(end) ?? start, start)',C)
 def test_16_source_truncated(self):self.assertIn('sourceTruncated = page.isTruncated',C);self.assertIn('if preview.sourceTruncated',A)
 def test_17_retained_retry(self):self.assertIn('page = next // Authoritative empty',C);self.assertIn('if issue == .login { page = nil }',C);self.assertIn('model.page != nil',A)
 def test_18_duplicate_load(self):self.assertIn('guard !isLoading else { return }',C)
 def test_19_generation(self):self.assertIn('generation == run && !Task.isCancelled && reader.isCurrentContext',C)
 def test_20_exact_selection(self):self.assertIn('rows.contains(row)',C);self.assertIn('model.canOpen(project, reader: reader',A)
 def test_21_stale_rows_disabled(self):self.assertIn('.disabled(model.isLoading || model.issue != nil)',A)
 def test_22_normal_injection(self):self.assertIn('selfProjectsAccess: .init(session: session)',H);self.assertIn('reader: session.creatorContentReader, owner: session.socialAccountReader.identity',A)
 def test_23_self_tab_only(self):self.assertIn('selfProjectsAccess.context(memberID: memberID, accountReader: reader, isCurrent: isCurrent()) != nil',S)
 def test_24_default_nil(self):self.assertIn('var selfProjectsAccess: ProfileSelfProjectsAccess? = nil',S)
 def test_25_full_browser_scope(self):self.assertIn('CreatorContentProjectsView(reader: reader',A);self.assertIn('reader.isCurrentContext, reader.scope == scope',A)
 def test_26_detail_guard(self):self.assertIn('if reader.isCurrentContext, let destination = selection.project.destination',A)
 def test_27_lifecycle(self):self.assertIn('.task { await load() }',A);self.assertIn('.onDisappear { model.suspend() }',A);self.assertIn('.refreshable { await load() }',A)
 def test_28_no_new_io(self):
  for value in ['URLSession','http://','https://','UserDefaults','token:','GrowthCenterReading','ProfileEditCoordinator']:self.assertNotIn(value,C+A)
 def test_29_localizations(self):
  f=json.loads((W/'Resources/ProfileSelfProjectsLocalizations.fragment.json').read_text())['strings'];self.assertEqual(len(f),10)
  for v in f.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
 def test_30_native_inventory(self):
  for path,count in [('CoreTests/ProfileSelfProjectsTests.swift',20),('AppUnitTests/ProfileSelfProjectsAppTests.swift',7),('AppUITests/ProfileSelfProjectsFlowTests.swift',7)]:self.assertEqual(len(re.findall(r'func test\w+\(', (W/'Tests'/path).read_text())),count)
if __name__=='__main__':unittest.main()
