"""Source-only approval/flow checks; no real transport or Swift runtime execution."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
class ProfileFavoriteRemovalSourceChecks(unittest.TestCase):
 def setUp(self):
  self.core=read('Core/ProfileFavoriteRemoval.swift');self.view=read('App/ProfileFavoriteRemovalView.swift');self.host=read('App/AccountCollectionFavoritesView.swift')
 def test_exact_source_paths_only(self):
  self.assertIn('["api/creativesquare/info", "api/creativesquare/bookmark"]',self.core)
  for bad in ['api/topic/like','api/v1/','follow/action','startChat','URLSession']:self.assertNotIn(bad,self.core)
 def test_no_implicit_production_grant(self):
  self.assertIn('approvals: [ProfileFavoriteRemovalApproval] = []',self.core)
  self.assertEqual(self.host.count('var favoriteRemoval: ProfileFavoriteRemovalController? = nil'),2)
  self.assertIn('if isCurrent(), controller.isAvailable(post: post, collectionScope: scope)',self.view)
 def test_approval_requires_exact_path_set_target_and_account(self):
  self.assertIn('endpoint.paths == Self.paths, endpoint.accountID == identity.accountID, postID > 0',self.core)
  self.assertIn('expiresAt.timeIntervalSince1970.isFinite',self.core)
 def test_runtime_approval_is_cn_exact_and_unique(self):
  for term in ['session.market == .china','now() < $0.expiresAt','$0.identity == session.identity','$0.postID == postID','.count == 1','namespace: session.namespace']:self.assertIn(term,self.core)
 def test_only_legacy_saved_posts_and_current_scope(self):
  self.assertIn('post.generation == .legacySquare && isAvailable(postID: post.id, collectionScope: collectionScope)',self.core)
  self.assertIn('session.collectionScope == collectionScope, approved(post.id, session: session)',self.core)
 def test_double_taps_consume_review_before_await(self):
  self.assertIn('guard !isBusy, isAvailable',self.core)
  self.assertIn('guard review == proposed, intent == proposed.intent, phase == .reviewed',self.core)
  self.assertIn('phase = .working; review = nil',self.core)
 def test_prepare_is_read_only(self):
  body=self.core.split('public func prepare(')[1].split('public func retryPreparation')[0]
  self.assertNotIn('bookmark", fields:',body);self.assertNotIn('journal.write',body)
  self.assertIn('let marked = try await bookmarked(value)',body)
 def test_cancel_only_retires_matching_presentation(self):
  body=self.core.split('public func retire(')[1].split('private func fence')[0]
  self.assertIn('guard intent?.id == id else { return }',body)
  self.assertNotIn('journal.',body);self.assertNotIn('transport.',body)
 def test_every_read_request_has_session_and_presentation_fence(self):
  self.assertIn('guard intent == value, current() == value.session, approved(value.postID, session: value.session)',self.core)
  self.assertIn('try Task.checkCancellation()',self.core)
  self.assertIn('try fence(value)\n        guard ProfileFavoriteRemovalApproval.paths.contains(path)',self.core)
 def test_readback_requires_exact_id_and_explicit_boolean_state(self):
  self.assertIn('row["id"].integer == value.postID, let marked = row["isBookmarked"].integer, marked == 0 || marked == 1',self.core)
  self.assertIn('return marked == 1',self.core)
  self.assertNotIn('favoritePosts(',self.core)
 def test_fresh_state_and_pending_lock_rechecked_before_write(self):
  body=self.core.split('public func confirm(')[1].split('public func reconcile')[0]
  self.assertEqual(body.count('guard try pending(value) == nil'),2)
  self.assertIn('let marked = try await bookmarked(value); try fence(value)',body)
 def test_request_has_explicit_zero_and_stable_review_key(self):
  self.assertIn('"bookmark": "0", "request_id": proposed.id.uuidString',self.core)
  self.assertNotIn('"member_id"',self.core)
 def test_durable_lock_precedes_dispatch(self):
  self.assertLess(self.core.index('try journal.write(prepared); record = prepared'),self.core.index('dispatched = true'))
  self.assertLess(self.core.index('dispatched = true'),self.core.index('transport.send(write)'))
 def test_durable_owner_excludes_epoch_token(self):
  body=self.core.split('private func owner(')[1].split('private func target')[0]
  self.assertIn('configuration.baseURL.absoluteString, value.session.namespace',body)
  self.assertIn('value.session.identity.accountID',body)
  self.assertNotIn('session.token',body);self.assertNotIn('identity.epoch',body)
 def test_success_requires_ack_readback_and_lock_clear(self):
  body=self.core.split('public func confirm(')[1].split('public func reconcile')[0]
  self.assertIn('_ = try envelope(data, status: status)',body)
  self.assertIn('guard !stillMarked else',body)
  self.assertLess(body.index('try clearResolved(prepared)'),body.rindex('phase = .removed'))
 def test_uncertain_post_stays_locked(self):
  self.assertIn('phase = dispatched ? .unknown : .failed',self.core)
  self.assertIn('if !dispatched, let record',self.core)
  self.assertNotIn('if dispatched, let record { try? journal.write(record) }',self.core)
  self.assertIn('pendingState.hold(record)',self.core)
 def test_reconcile_never_resends(self):
  body=self.core.split('public func reconcile(')[1]
  self.assertIn('phase == .unknown',body);self.assertIn('let stillMarked = try await bookmarked(value)',body)
  for bad in ['transport.send(write)','"bookmark":','confirm(']:self.assertNotIn(bad,body)
 def test_reconcile_clear_verifies_cleanup_or_quarantines(self):
  body=self.core.split('public func reconcile(')[1]
  self.assertIn('try clearResolved(record)',body)
  self.assertNotIn('journal.write',body)
  helper=self.core.split('private func clearResolved(')[1].split('public func prepare(')[0]
  self.assertIn('pendingState.hold(record)',helper)
  self.assertIn('guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil',helper)
 def test_retry_only_restarts_preflight(self):
  body=self.core.split('public func retryPreparation(')[1].split('public func confirm')[0]
  self.assertIn('phase == .failed',body);self.assertIn('await prepare(id)',body)
 def test_optional_injection_threads_through_existing_list(self):
  self.assertIn('onOpenPost: onOpenPost, favoriteRemoval: favoriteRemoval)',self.host)
  self.assertIn('ProfileFavoriteRemovalEntry(post: post, scope: key.scope, controller: favoriteRemoval',self.host)
  self.assertIn('onRemoved: { await refresh() }',self.host)
 def test_existing_detail_and_gallery_preserved(self):
  self.assertIn('onOpenPost?(.init(id: post.id, generation: post.generation))',self.host)
  self.assertIn('NativeMediaGalleryEntry(sources: post.images, scope: reader.scope, titleKey: "media.destination.squareImages")',self.host)
 def test_sheet_cannot_retire_another_presentation(self):
  self.assertIn('.sheet(item: $presentation) { value in',self.view)
  self.assertNotIn('onDismiss: { if let id = controller.presentationID',self.view)
  self.assertIn('.onDisappear { finish() }',self.view)
  self.assertIn('controller.retire(id)',self.view)
 def test_done_consumed_once_only_after_removed_and_current(self):
  self.assertIn('guard !isFinished else { return }',self.view)
  self.assertIn('controller.presentationID == id && controller.phase == .removed',self.view)
  self.assertIn('Task { if isCurrent() { await onRemoved() } }',self.view)
 def test_unknown_ui_has_check_not_submit(self):
  body=self.view.split('case .unknown:')[1].split('case .removed:')[0]
  self.assertIn('controller.reconcile(presentation.id)',body);self.assertNotIn('controller.confirm',body)
 def test_background_scope_and_close_retire(self):
  self.assertIn('.onChange(of: scope) { _, _ in close() }',self.view)
  self.assertIn('if value != .active { close() }',self.view)
  self.assertIn('presentation?.finish(controller: controller, isCurrent: isCurrent, onRemoved: onRemoved)',self.view)
 def test_registration_and_localization_disclose_pending_production(self):
  reg=json.loads(read('docs/profile-favorite-removal-registration.fragment.json'));loc=json.loads(read(reg['localization_fragment']))['strings']
  self.assertFalse(reg['production_enabled']);self.assertEqual(reg['central_files_modified'],[]);self.assertEqual(len(loc),11)
  for v in loc.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
 def test_fixture_uses_real_controller_only_with_synthetic_wire(self):
  f=read('App/ProfileFavoriteRemovalFixture.swift');self.assertTrue(f.startswith('#if DEBUG'));self.assertIn('ProfileFavoriteRemovalController',f);self.assertIn('https://profile.example/native',f);self.assertNotIn('URLSession',f)
 def test_native_inventory_and_core_boundaries(self):
  c=read('Tests/CoreTests/ProfileFavoriteRemovalTests.swift');a=read('Tests/AppUnitTests/ProfileFavoriteRemovalAppTests.swift');u=read('Tests/AppUITests/ProfileFavoriteRemovalFlowTests.swift')
  self.assertEqual(c.count('func test'),31);self.assertEqual(a.count('func test'),11);self.assertEqual(u.count('func test'),8)
  for term in ['UnknownLockSurvives','MissingState','WrongGeneration','RetiredIdentity','JournalFailure','ClosingDuringPreflight','DuplicateConfirm']:self.assertIn(term,c)
 def test_missing_row_recovery_does_not_require_a_saved_post_or_allow_write(self):
  body=self.core.split('public func beginRecovery(')[1].split('public func begin(')[0]
  self.assertIn('guard (try? pending(next)) != nil',body)
  self.assertIn('review = nil; phase = .unknown',body)
  self.assertNotIn('transport.',body)
  self.assertIn('ProfileFavoriteRecoverySection(scope: renderedScope',self.host)
  self.assertIn('if !ids.isEmpty || presentation != nil',self.view)
 def test_unauthorized_is_context_fenced_and_never_clears_pending(self):
  body=self.core.split('private func expireIfCurrent(')[1].split('private func bookmarked(')[0]
  self.assertIn('intent == value, current() == value.session',body)
  self.assertIn('onUnauthorized()',body)
  self.assertNotIn('journal.clear',body)
if __name__=='__main__':unittest.main()
