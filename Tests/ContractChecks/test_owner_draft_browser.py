"""Offline source assertions only; Swift and Apple UI execution are separate gates."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
class OwnerDraftBrowserContracts(unittest.TestCase):
    def source(self, path): return (ROOT / path).read_text()
    def test_synthetic_phone_exchange_retains_identity_before_authoritative_readback(self):
        fixture = self.source('App/OwnerDraftFixtureHost.swift')
        phone = fixture.split('if path == "phone" {', 1)[1].split('if path == "userInfo" {', 1)[0]
        literal = re.search(r'Data\(("(?:\\.|[^"\\])*")\.utf8\)', phone).group(1)
        # Decode only the synthetic, non-secret Swift string after replacing its sole interpolation.
        envelope = json.loads(json.loads(literal.replace(r'\(accountID)', '7')))
        self.assertEqual(envelope, {'code': 200, 'token': 'synthetic-7', 'data': {'id': 7}})
        service = self.source('Core/AuthChannelService.swift')
        self.assertIn('let account = body.data, account.id > 0', service)
        self.assertIn('try await service.currentAccount(token: result.token)', self.source('Core/AuthChannelCoordinator.swift'))
    def test_migrated_feature_helpers_require_success_and_exact_auth_requests(self):
        for name in ['AppCompositionRootTests', 'PrivateHomeCompositionTests', 'PublicTemplateCompositionTests',
                     'PublicTemplateDetailAppTests', 'SocialMemberActionAppTests', 'OwnerDraftCompositionTests']:
            source = self.source('Tests/AppUnitTests/' + name + '.swift')
            helper = source.split('private func signIn(', 1)[1].split('\n    }', 1)[0]
            for marker in ['let before = recorder.requests.count', 'XCTAssertNotNil(session.account',
                           'XCTAssertTrue(session.authChannels.state.signedIn', 'recorder.requests.dropFirst(before)',
                           '/api/login/phone', '/api/userInfo']:
                self.assertIn(marker, helper, name)
        ui = self.source('Tests/AppUITests/OwnerDraftBrowserFlowTests.swift')
        self.assertIn('record("session", mode == "guest" ? "guest" : "signed-in", app)', ui)
        self.assertIn('record("authPaths", "phone,userInfo", app)', ui)
    def test_actual_account_and_guest_entry(self):
        self.assertIn('OwnerDraftAccountLink(browser: session.ownerDraftBrowser)', self.source('App/AccountView.swift'))
        self.assertIn('NavigationLink { OwnerDraftGuestView() }', self.source('App/WelcomeView.swift'))
        self.assertIn('LoginView(intent: .player)', self.source('App/OwnerDraftBrowserView.swift'))
    def test_read_only_projection_without_editor_schema(self):
        s = self.source('Core/OwnerDraftBrowser.swift')
        view = self.source('App/OwnerDraftBrowserView.swift')
        self.assertIn('private let reader: any ContentDraftReading', s)
        for term in ['.mutate(', '.prepareSave(', 'TextEditor(', 'ProjectEdit', 'payloadJson', 'installedModules']:
            self.assertNotIn(term, view)
        self.assertIn('ownerDraft.unsupported.detail', view)
        self.assertIn('OwnerDraftReceiptSummaryView(summary: receipts)', view)
        self.assertIn('grant.routes == [.list, .restore]', s)
        self.assertIn('grant.scope == .personal', s)
    def test_exact_forms_no_pagination_or_override(self):
        s = self.source('App/OwnerDraftComposition.swift')
        self.assertIn('case list, restore', s)
        self.assertIn('text == "scope="', s)
        self.assertIn('String(id) == value', s)
        self.assertNotIn('page=', s); self.assertNotIn('cursor=', s)
        self.assertIn('body.count <= 128', s)
    def test_session_binding_revokes_before_identity_assignment_and_on_root_exit(self):
        s = self.source('App/AppSession.swift')
        for declaration in ['var account: Account?', 'private var token: String?']:
            owner = next(line for line in s.splitlines() if declaration in line).split('didSet')[0]
            self.assertIn('willSet {', owner)
            self.assertIn('invalidateOwnerDraftBrowser();', owner)
        self.assertIn('ContentDraftContextFence.matches(self.currentOwnerDraftContext, context)', s)
        self.assertIn('setOwnerDraftPresentationActive(false)', self.source('App/QuestifyApp.swift'))
        gate = next(line for line in s.splitlines() if 'private var gate = SessionOperationGate()' in line)
        self.assertIn('synchronizeOwnerDraftBrowser()', gate)
        self.assertIn('retainedOwnerDraftBrowser?.browser.invalidate()', s)
    def test_defaults_empty_and_late_approval_recheck(self):
        s = self.source('App/AppCompositionRoot.swift')
        self.assertIn('OwnerDraftReadApproval? = { _ in nil }', s)
        self.assertGreaterEqual(s.count('readApprovalStillValid?() != false'), 2)
        self.assertIn('lhs.role.map { Data($0.utf8) }', s)
    def test_stale_late_restore_and_refresh_are_fenced(self):
        s = self.source('Core/OwnerDraftBrowser.swift')
        self.assertIn('guard current(), detailGeneration == ticket else', s)
        self.assertIn('guard current(), listGeneration == ticket else', s)
        self.assertIn('record.version >= row.version', s)
        self.assertIn('closeDetail(); rows = []; phase = .loading', s)
        self.assertIn('lease.revoke()', s)
    def test_list_back_reopen_fences_retired_request_without_erasing_detail_push(self):
        s = self.source('Core/OwnerDraftBrowser.swift')
        closed = s.split('public func closeList()', 1)[1].split('public func closeDetail()', 1)[0]
        self.assertIn('listGeneration = UUID()', closed)
        self.assertIn('phase = .idle', closed)
        self.assertIn('guard phase != .invalidated', closed)
        self.assertIn('.onDisappear { if route == nil { browser.closeList() } }', self.source('App/OwnerDraftBrowserView.swift'))
    def test_bounded_time_and_no_payload_render(self):
        s = self.source('Core/OwnerDraftBrowser.swift')
        self.assertIn('text.utf8.count <= 40', s)
        self.assertIn('Unsupported server timestamp', s)
        self.assertIn('updateTime = try? box.decode(ContentDraftServerTime.self', self.source('Core/VersionedContentDraftContracts.swift'))
        self.assertNotIn('Date(timeIntervalSince1970:', s)
        self.assertIn('let savedTime: String?', s)
        self.assertIn(r'\A[0-9]', s); self.assertIn(r'?\z', s)
    def test_bilingual_all_new_keys_and_large_type_no_fixed_height(self):
        view = self.source('App/OwnerDraftBrowserView.swift')
        strings = json.loads(self.source('Resources/Localizable.xcstrings'))['strings']
        keys = set(re.findall(r'"(ownerDraft\.[A-Za-z.]+)"', view))
        keys -= {'ownerDraft.row.', 'ownerDraft.notConfigured', 'ownerDraft.retry', 'ownerDraft.detailRetry', 'ownerDraft.detailLoading', 'ownerDraft.unsupported', 'ownerDraft.receipts.state.', 'ownerDraft.receipts.state', 'ownerDraft.receipts.row.'}
        for key in keys:
            self.assertEqual(set(strings[key]['localizations']), {'en', 'zh-Hans'})
        self.assertNotIn('.lineLimit(1)', view); self.assertNotIn('height:', view)
    def test_synthetic_recorder_and_apple_tests_are_authored(self):
        fixture = self.source('App/OwnerDraftFixtureHost.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('URLSession', fixture.split('final class OwnerDraftFixtureTransport')[1])
        self.assertIn('AccountView(account: account)', fixture)
        for path, minimum in [('Tests/CoreTests/OwnerDraftBrowserTests.swift', 12), ('Tests/AppUnitTests/OwnerDraftCompositionTests.swift', 10), ('Tests/AppUITests/OwnerDraftBrowserFlowTests.swift', 9)]:
            self.assertGreaterEqual(len(re.findall(r'func test', self.source(path))), minimum)
if __name__ == '__main__': unittest.main()
