"""P108 source-seam checks; not a replacement for the authored Swift/UIKit tests."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path): return (ROOT / path).read_text()

class ProfileAuthorPostsRefreshSourceChecks(unittest.TestCase):
    def setUp(self):
        self.core = read('Core/ProfileAuthorPostsRefresh.swift')
        self.view = read('App/ProfileAuthorPostsSection.swift')
        self.host = read('App/SocialPublicProfileView.swift')
    def test_live_posts_tab_uses_new_section_and_parent_lifetime(self):
        self.assertIn('ProfileAuthorPostsSection(memberID: memberID, accountReader: reader, squareReader: squareReader, actions: actions, isCurrent: isCurrent)', self.host)
        self.assertNotIn('private struct SocialAuthorPostsSection', self.host)
    def test_only_existing_author_read_is_used(self):
        self.assertEqual(self.core.count('try await squareReader.squareFeed('), 1)
        self.assertIn('squareFeed(query: .init(authorID: memberID), cursor: cursor)', self.core)
        for forbidden in ['URLSession', 'HTTPTransport', 'Authorization', '/api/', 'currentSession', 'perform(', 'write(', 'token:']:
            self.assertNotIn(forbidden, self.core)
    def test_refresh_builds_replacement_before_commit(self):
        self.assertIn('var replacement = operation == .refresh ? SquareFeedPagination() : pagination', self.core)
        self.assertLess(self.core.index('try replacement.accept(page, requestedCursor: cursor)'), self.core.index('pagination = replacement'))
    def test_refresh_and_more_have_distinct_cursor_and_retry_intents(self):
        self.assertIn('let cursor = operation == .refresh ? nil : pagination.nextCursor', self.core)
        self.assertIn('failedOperation = operation', self.core)
        self.assertIn('guard expected == context, let operation = failedOperation else { return }', self.core)
        self.assertIn('await load(operation, memberID:', self.core)
    def test_more_cannot_skip_failed_refresh(self):
        self.assertIn('error == nil || failedOperation == .more else { return }', self.core)
        self.assertIn('pagination.hasLoadedPage, pagination.hasMore, pagination.nextCursor != nil', self.core)
    def test_same_context_double_taps_are_blocked(self):
        self.assertIn('guard !isBusy else { return }', self.core)
        self.assertLess(self.core.index('guard !isBusy else { return }'), self.core.index('try await squareReader.squareFeed'))
    def test_complete_context_key(self):
        for required in ['memberID: Int', 'SocialAccountIdentity', 'revision: UInt64', 'squareScope: UUID', 'ObjectIdentifier(accountReader)', 'ObjectIdentifier(squareReader)', 'accountReader.presentationRevision', 'accountReader.isConfigured && squareReader.isConfigured', 'viewer.accountID != nil && squareReader.isSignedIn']:
            self.assertIn(required, self.core)
    def test_context_changed_before_callback_drops_rows(self):
        self.assertEqual(self.core.count('guard isCurrent(), captured == ProfileAuthorPostsContext'), 2)
        self.assertIn('guard run == generation else { return }', self.core)
        self.assertIn('guard !Task.isCancelled, run == generation else { return }', self.core)
    def test_unavailable_context_never_reads(self):
        self.assertIn('guard memberID > 0, captured.isConfigured, captured.isSignedIn else {', self.core)
        self.assertLess(self.core.index('guard memberID > 0'), self.core.index('try await squareReader.squareFeed'))
    def test_denials_clear_rows(self):
        self.assertIn('if Self.isAccessDenial(error) {\n                pagination = .init(); failedOperation = nil', self.core)
        self.assertIn('case .httpStatus(let code)', self.core)
        self.assertIn('case .businessCode(let code)', self.core)
        self.assertIn('case .server(let code, _)', self.core)
        self.assertIn('code == 2 || code == 401 || code == 403', self.core)
    def test_initial_cancel_cannot_retire_new_request(self):
        self.assertIn('guard !Task.isCancelled else { return }', self.core)
        self.assertIn('guard isCurrent() else { if context == captured { retire() }; return }', self.core)
    def test_suspension_preserves_detail_source_but_retires_pending_callback(self):
        self.assertIn('public func suspend() { generation &+= 1; activeOperation = nil }', self.core)
        self.assertIn('.onDisappear { model.suspend() }', self.view)
    def test_retire_clears_cached_context(self):
        self.assertIn('generation &+= 1; context = nil; pagination = .init()', self.core)
    def test_rows_and_detail_open_use_current_context(self):
        self.assertIn('guard isCurrent, expected == context, expected.isConfigured, expected.isSignedIn else { return [] }', self.core)
        self.assertIn('model.visibleRows(for: context, isCurrent: isCurrent())', self.view)
        self.assertIn('model.canOpen(post, context: context, isCurrent: isCurrent())', self.view)
        self.assertIn('contentGeneration: post.generation', self.view)
    def test_task_tracks_full_context_not_just_account_id(self):
        self.assertIn('.task(id: context) { await refresh() }', self.view)
    def test_refresh_busy_retained_and_retry_ui(self):
        for key in ['refresh', 'refreshing', 'retained', 'retry', 'more', 'empty', 'invalidCursor']:
            self.assertIn('"profile.postsRefresh.' + key + '"', self.view)
        self.assertIn('.disabled(model.isBusy)', self.view)
        self.assertIn('if model.failedOperation != nil', self.view)
    def test_empty_requires_successfully_loaded_page(self):
        self.assertIn('if model.pagination.hasLoadedPage && model.pagination.items.isEmpty', self.view)
    def test_gallery_contract_not_replaced(self):
        self.assertIn('NativeMediaGalleryEntry(sources: post.images, scope: squareReader.scope, titleKey: "media.destination.squareImages")', self.view)
        self.assertNotIn('imageReader:', self.view)
    def test_fixture_is_debug_only_and_synthetic(self):
        f=read('App/ProfileAuthorPostsRefreshFixture.swift')
        self.assertTrue(f.startswith('#if DEBUG'))
        self.assertIn('let isOfflineExample = true', f)
        self.assertNotIn('URLSession', f); self.assertNotIn('AppSession', f)
    def test_registration_and_localization_complete(self):
        reg=json.loads(read('docs/profile-author-posts-refresh-registration.fragment.json'))
        self.assertEqual(reg['new_localization_keys'], 3)
        self.assertEqual(reg['central_files_modified'], [])
        loc=json.loads(read(reg['localization_fragment']))['strings']
        self.assertEqual(len(loc), 3)
        for item in loc.values(): self.assertEqual(set(item['localizations']), {'en','zh-Hans'})
    def test_native_test_inventory_and_interruption_coverage(self):
        core=read('Tests/CoreTests/ProfileAuthorPostsRefreshTests.swift')
        app=read('Tests/AppUnitTests/ProfileAuthorPostsRefreshAppTests.swift')
        ui=read('Tests/AppUITests/ProfileAuthorPostsRefreshFlowTests.swift')
        self.assertEqual(core.count('func test'), 18); self.assertEqual(app.count('func test'), 8); self.assertEqual(ui.count('func test'), 5)
        for term in ['NewScopeCanStart', 'ViewerRevisionABA', 'CancelledCompletion', 'ParentRetirement', 'DuplicateRefresh', 'MalformedContinuation']:
            self.assertIn(term, core)
    def test_no_editor_or_session_coupling(self):
        for term in ['ProfileEdit', 'AppSession', 'ProfileAvatar', 'ProfilePreference']:
            self.assertNotIn(term, self.core + self.view)

if __name__ == '__main__': unittest.main()
