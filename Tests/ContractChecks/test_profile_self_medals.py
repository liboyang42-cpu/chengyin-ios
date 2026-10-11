"""Own-profile medal source seams only; not Swift runtime execution."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
class ProfileSelfMedalsSourceChecks(unittest.TestCase):
 def setUp(self):
  self.core=read('Core/ProfileSelfMedals.swift');self.view=read('App/ProfileSelfMedalsSection.swift');self.public=read('App/SocialPublicProfileView.swift');self.account=read('App/AccountView.swift')
 def test_self_owner_and_positive_target(self):
  self.assertIn('memberID > 0',self.core);self.assertIn('accountReader.identity.accountID == memberID',self.core);self.assertIn('owner.accountID == memberID',self.core)
 def test_current_and_both_configured(self):
  self.assertIn('guard isCurrent, memberID > 0, accountReader.isConfigured, profileReader.isConfigured',self.core)
 def test_both_reader_instances_and_revisions(self):
  for term in ['ObjectIdentifier(accountReader)','ObjectIdentifier(profileReader)','accountReader.presentationRevision','owner: owner','viewer: accountReader.identity']:self.assertIn(term,self.core)
 def test_existing_reader_only_no_direct_endpoint(self):
  self.assertIn('try await profileReader.profileBadges()',self.core)
  for term in ['URLSession','HTTPTransport','api/','token','UserDefaults','save(']:self.assertNotIn(term,self.core)
 def test_duplicate_load_suppressed(self):
  self.assertIn('guard !isLoading || context != captured else { return }',self.core)
 def test_new_context_clears_old_rows(self):
  self.assertIn('if context != captured { medals = nil; issue = nil; context = captured }',self.core)
 def test_full_post_await_fence(self):
  self.assertIn('generation == run && context == captured && !Task.isCancelled',self.core)
  self.assertIn('profileReader: profileReader, isCurrent: isCurrent()) == captured',self.core)
  self.assertIn('let wall = try await profileReader.profileBadges()\n            guard current() else { return }',self.core)
 def test_nil_medals_is_partial_not_empty(self):
  self.assertIn('guard let rows = wall.medals else { issue = .partial; return }',self.core)
  self.assertNotIn('wall.medals ?? []',self.core)
 def test_successful_empty_replaces_rows(self):
  self.assertIn('medals = rows',self.core);self.assertNotIn('medals +=',self.core)
 def test_unauthorized_clears_old_rows(self):
  self.assertIn('error as? APIError == .unauthorized',self.core);self.assertIn('isUnauthorized == true',self.core);self.assertIn('medals = nil; issue = .signIn',self.core)
 def test_generic_failure_retains_but_labels_rows(self):
  self.assertIn('else { issue = .readFailed }',self.core);self.assertIn('if model.medals != nil { Text("profile.selfMedals.retained")',self.view)
 def test_suspend_keeps_navigation_rows_and_retires_generation(self):
  self.assertIn('public func suspend() { generation &+= 1; isLoading = false }',self.core)
  self.assertIn('.onDisappear { model.suspend() }',self.view)
 def test_retire_clears_every_projection(self):
  self.assertIn('suspend(); context = nil; medals = nil; issue = nil',self.core)
 def test_view_only_renders_matching_owner(self):
  self.assertIn('if let context',self.view);self.assertIn('if model.context != context { ProgressView',self.view)
 def test_count_is_loaded_rows_not_invented_total(self):
  self.assertIn('String(medals.count)',self.view);self.assertIn('profile.selfMedals.loadedCount',self.view)
 def test_failures_have_explicit_read_retry(self):
  self.assertIn('profile.selfMedals.retry',self.view);self.assertIn('Button("action.retry") { Task { await load() } }',self.view)
 def test_refresh_and_empty_available(self):
  self.assertIn('profile.selfMedals.refresh',self.view);self.assertIn('if medals.isEmpty { Text("profile.selfMedals.empty")',self.view)
 def test_normal_account_injection_and_tab(self):
  self.assertIn('selfMedalsReader: session.profileReader',self.account)
  self.assertIn('case .achievements:\n                        if let selfMedalsReader',self.public)
  self.assertIn('profileReader: selfMedalsReader, isCurrent: isCurrent)',self.public)
 def test_other_callers_default_to_no_private_reader(self):
  self.assertIn('var selfMedalsReader: (any ProfileReading)? = nil',self.public)
 def test_wall_reuses_existing_destination_with_exact_context(self):
  self.assertIn('ObjectBadgeWallView(reader: scopedReader)',self.view)
  self.assertIn('scopedReader.identity == context.owner, scopedReader.isConfigured',self.view)
 def test_scoped_wall_fences_queued_and_completed_reads(self):
  body=self.core.split('public final class ProfileSelfMedalsScopedReader')[1]
  self.assertEqual(body.count('guard matches else { throw CancellationError() }'),2)
  self.assertIn('try await reader.profileBadges()',body)
  self.assertIn('@State private var scopedReader: ProfileSelfMedalsScopedReader',self.view)
 def test_no_new_image_reader_or_preview_claim(self):
  for term in ['AsyncImage','RetainedPublicImage','media:','URLSession','previewImage']:self.assertNotIn(term,self.view)
 def test_previous_public_features_preserved(self):
  for term in ['ProfileAuthorPostsSection','ProfileLocalCoverSection','ProfileSelfEditDestination','profile.published','purpose: .toggleFollow']:self.assertIn(term,self.public)
 def test_fragment_has_seven_bilingual_keys(self):
  reg=json.loads(read('docs/profile-self-medals-registration.fragment.json'));loc=json.loads(read(reg['localization_fragment']))['strings']
  self.assertEqual(len(loc),7);self.assertEqual(reg['new_endpoints'],[]);self.assertEqual(reg['new_approvals'],[]);self.assertFalse(reg['media_reader_injection'])
  for value in loc.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
 def test_native_inventory_is_authored_not_executed(self):
  self.assertEqual(read('Tests/CoreTests/ProfileSelfMedalsTests.swift').count('func test'),20)
  self.assertEqual(read('Tests/AppUnitTests/ProfileSelfMedalsAppTests.swift').count('func test'),7)
  self.assertEqual(read('Tests/AppUITests/ProfileSelfMedalsFlowTests.swift').count('func test'),6)
if __name__=='__main__':unittest.main()
