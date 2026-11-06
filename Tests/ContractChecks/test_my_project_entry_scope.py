"""Source contract: project/my scope comes from the entry, not data.scope. Does not execute Swift."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MyProjectEntryScopeTests(unittest.TestCase):
    def setUp(self):
        self.service = (ROOT / 'Core/CreatorContentService.swift').read_text()
        self.view = (ROOT / 'App/CreatorContentViews.swift').read_text()
        self.nav = (ROOT / 'App/MyProjectStateNavigation.swift').read_text()
        self.host = (ROOT / 'App/ProjectOwnedContentViews.swift').read_text()
        self.session = (ROOT / 'App/AppSession.swift').read_text()

    def test_only_merchant_entry_sends_scope(self):
        self.assertIn('static func merchantWireScope', self.service)
        self.assertIn('return "MERCHANT"', self.service)
        self.assertIn('throw APIError.invalidRequest', self.service)
        self.assertNotIn('fields["scope"] = "MERCHANT"', self.service.split('merchantWireScope')[0])

    def test_browse_only_uses_entry_and_access_not_response_scope(self):
        self.assertNotIn('serverScope', self.view)
        self.assertNotIn('responseScope', self.nav)
        self.assertIn('entryScope: entryScope, canManageProjects: canManageProjects', self.view)
        self.assertIn('merchant:project:manage', self.nav)
        self.assertIn('session.merchantAccess()', self.host)
        self.assertIn('allows(.projects)', self.host)

    def test_activity_editor_stays_behind_the_closed_approval(self):
        self.assertIn('activityEditingApproval: @escaping (RuntimeDependencyContext) -> ActivityEditingGrants = { _ in .init() }', self.session)
        self.assertIn('makeActivityEditor: { session.activityEditingController(id: $0) }', self.host)
        self.assertIn('liveAccess.isBrowseOnly', self.host)
        self.assertIn('isServerSaveReceipt', self.nav)
