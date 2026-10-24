"""Composition source checks only; no Swift compilation or runtime execution."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class AccessContracts(unittest.TestCase):
    def test_revocable_context_and_collection_bound_access(self):
        s=(ROOT/'Core/ProfileFavoriteRemovalAccess.swift').read_text()
        for x in ['ContentDraftContextFence.matches(context, current)','self.collectionScope == collectionScope','approval.postID == postID','now < approval.expiresAt','!isRevoked','approval.identity.epoch == context.session.epoch','approval.identity.role == context.role']:
            self.assertIn(x,s)
    def test_request_matcher_allows_only_remove_not_toggle(self):
        s=(ROOT/'Core/ProfileFavoriteRemovalAccess.swift').read_text()
        for x in ['Set(fields.keys) == ["id"]','Set(fields.keys) == ["id", "bookmark", "request_id"]','fields["bookmark"] == "0"','raw == id.uuidString','ProfileFavoritesRequestContract.fields']:
            self.assertIn(x,s)
    def test_no_factory_or_runtime_permission_is_invented(self):
        s=(ROOT/'Core/ProfileFavoriteRemovalAccess.swift').read_text()
        self.assertNotIn('URLSession',s)
        self.assertNotIn('OperationEndpointApproval(',s)
        self.assertIn('approval: ProfileFavoriteRemovalApproval',s)
    def test_normal_account_and_settings_entries_use_existing_controller(self):
        self.assertIn('favoriteRemoval: session.makeProfileFavoriteRemovalController', (ROOT/'App/AccountView.swift').read_text())
        self.assertIn('favoriteRemoval: route.access.removal', (ROOT/'App/ProfileSettingsFavoritesRoute.swift').read_text())
    def test_factory_is_default_empty_and_reviewed_deployment_only(self):
        root=(ROOT/'App/AppCompositionRoot.swift').read_text()
        self.assertIn('[ProfileFavoriteRemovalAccess] = { _, _ in [] }',root)
        self.assertIn('guard case .reviewed(let reviewed) = deployment',root)
        self.assertIn('reviewed.storageScope.service == context.session.namespace',root)
    def test_factory_preserves_controller_identity_and_durable_journal(self):
        source=(ROOT/'App/AppSession.swift').read_text()
        for x in ['cached.revisions == revisions', 'favoriteRemovalControllerCache = nil','journal: composition.storage.operationJournal()', 'latest.contains(where: { $0 === captured })','profileFavoritesReader.scope == scope']:
            self.assertIn(x,source)
    def test_transport_fences_before_and_after_dispatch(self):
        source=(ROOT/'Core/ProfileFavoriteRemovalAccess.swift').read_text()
        for x in ['request.value(forHTTPHeaderField: "Authorization") == context.session.token','offered.count == 1 && offered.first === selected','let response = try await underlying.send(request)','guard valid() else { throw ProfileFavoriteRemovalFailure.stale }']:
            self.assertIn(x,source)
if __name__=='__main__':unittest.main()
