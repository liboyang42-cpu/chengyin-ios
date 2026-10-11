"""Source assertions, not Swift execution or Apple navigation evidence."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
def read(p):return (ROOT/p).read_text()
class ProfileSelfGrowthSourceChecks(unittest.TestCase):
 def setUp(self):
  self.core=read('Core/ProfileSelfGrowth.swift');self.view=read('App/ProfileSelfGrowthSection.swift');self.account=read('App/AccountView.swift');self.public=read('App/SocialPublicProfileView.swift')
 def test_owner_exactly_matches_current_viewer_and_member(self):
  self.assertIn('owner.accountID == memberID, accountReader.identity == owner',self.core)
 def test_configured_current_authenticated_only(self):
  for term in ['guard isCurrent, memberID > 0','accountReader.isConfigured, growthReader.isAuthenticated, growthReader.isConfigured']:self.assertIn(term,self.core)
 def test_growth_scope_captured_by_host(self):
  self.assertIn('growthReader.scope == ownerScope',self.core);self.assertIn('scope = reader.scope',self.view)
 def test_reader_instances_and_public_revision_captured(self):
  for term in ['ObjectIdentifier(accountReader)','ObjectIdentifier(growthReader)','accountReader.presentationRevision']:self.assertIn(term,self.core)
 def test_scoped_wrapper_fences_before_after_and_error(self):
  self.assertEqual(self.core.count('guard matches else { throw CancellationError() }'),2)
  self.assertIn('guard !Task.isCancelled, matches else { throw CancellationError() }',self.core)
 def test_overview_and_leaderboard_share_same_guard(self):
  self.assertIn('try await read { try await reader.overview() }',self.core)
  self.assertIn('try await read { try await reader.leaderboard(query: query) }',self.core)
 def test_scope_is_wrapper_local_and_immutable(self):
  self.assertIn('public let scope = UUID()',self.core)
 def test_no_direct_endpoint_write_or_storage(self):
  for term in ['api/','URLSession','HTTPTransport','AuthRequestBuilder','UserDefaults','save(','token']:self.assertNotIn(term,self.core)
 def test_six_exact_metric_sources(self):
  for term in ['progress?.level ?? center?.level','center?.experience','center?.points','progress?.totalCheckins','progress?.totalMileage','progress?.streakDays']:self.assertIn(term,self.core)
 def test_unknown_not_zero_and_no_rank_substitution(self):
  summary=self.core.split('public struct ProfileSelfGrowthSummary')[1]
  self.assertNotIn('?? 0',summary);self.assertNotIn('overview.rank',summary);self.assertNotIn('board.me.score',summary)
 def test_mileage_retains_existing_unit(self):
  self.assertIn('GrowthCenterFormatting.mileage(progress?.totalMileage)',self.core)
  self.assertNotIn('/ 1000',self.core)
 def test_independent_section_errors_are_preserved(self):
  self.assertIn('centerIssue = overview.center.issue; progressIssue = overview.progress.issue',self.core)
  self.assertIn('if let issue = summary.centerIssue',self.view);self.assertIn('if let issue = summary.progressIssue',self.view)
 def test_uses_existing_screen_model_and_lifecycle(self):
  self.assertIn('GrowthCenterScreenModel<GrowthCenterOverview>()',self.view)
  self.assertIn('GrowthCenterReadLifecycle(key: key, refresh: load, cancel: model.cancelPending)',self.view)
 def test_refresh_does_not_duplicate_active_read(self):
  self.assertIn('guard !model.isLoading, scopedReader.isAuthenticated, scopedReader.isConfigured else { return }',self.view)
 def test_wrapper_retained_across_body_recomputations(self):
  self.assertIn('@State private var scopedReader: ProfileSelfGrowthScopedReader',self.view)
  self.assertIn('.id(context)',self.view)
 def test_destination_uses_same_scoped_reader(self):
  self.assertIn('ProfileSelfGrowthDestination(reader: scopedReader)',self.view)
  self.assertIn('if reader.isAuthenticated && reader.isConfigured { GrowthCenterView(reader: reader) }',self.view)
 def test_normal_account_injects_existing_reader_and_owner(self):
  self.assertIn('selfGrowthAccess: .init(reader: session.growthCenterReader, owner: session.socialAccountReader.identity)',self.account)
 def test_others_receive_no_access_by_default(self):
  self.assertIn('var selfGrowthAccess: ProfileSelfGrowthAccess? = nil',self.public)
 def test_own_entry_is_in_achievements_tab(self):
  body=self.public.split('case .achievements:')[1].split('case .about:')[0]
  self.assertIn('ProfileSelfGrowthEntry(memberID: memberID, accountReader: reader',body)
 def test_prior_features_stay_present(self):
  for term in ['ProfileSelfMedalsSection','ProfileSelfEditDestination','ProfileLocalCoverSection','ProfileAuthorPostsSection']:self.assertIn(term,self.public)
 def test_no_new_media_capability(self):
  for term in ['AsyncImage','RetainedPublicImage','media:','PhotosPicker']:self.assertNotIn(term,self.view)
 def test_five_bilingual_keys_and_no_new_grants(self):
  reg=json.loads(read('docs/profile-self-growth-registration.fragment.json'));loc=json.loads(read(reg['localization_fragment']))['strings']
  self.assertEqual(len(loc),5);self.assertEqual(reg['new_endpoints'],[]);self.assertEqual(reg['new_approvals'],[])
  for value in loc.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
 def test_fixture_is_synthetic_existing_reader(self):
  fixture=read('App/ProfileSelfGrowthFixture.swift');self.assertTrue(fixture.startswith('#if DEBUG'));self.assertIn('GrowthCenterFixtureReader',fixture);self.assertNotIn('URLSession',fixture)
 def test_native_test_inventory(self):
  for path,count in [('Tests/CoreTests/ProfileSelfGrowthTests.swift',18),('Tests/AppUnitTests/ProfileSelfGrowthAppTests.swift',7),('Tests/AppUITests/ProfileSelfGrowthFlowTests.swift',6)]:self.assertEqual(read(path).count('func test'),count)
if __name__=='__main__':unittest.main()
