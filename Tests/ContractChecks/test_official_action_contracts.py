"""Additive action boundary checks; not Swift compilation/runtime evidence."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
class OfficialActionSourceChecks(unittest.TestCase):
    def test_dormant_host_and_adapter(self):
        service=(ROOT/'Core/OfficialActionService.swift').read_text()
        self.assertIn('enabled: Bool = false',service)
        self.assertNotIn('URLSession',service)
        session=(ROOT/'App/AppSession.swift').read_text()
        self.assertIn('let access = OfficialActionProductionFactory(',session)
        self.assertIn('approval: runtimeDependencies.officialActionApproval',session)
        production=(ROOT/'Core/OfficialActionProduction.swift').read_text()
        self.assertIn('case .arrival, .inviteMerchants: return nil',production)
    def test_durable_lock_and_stale_snapshot(self):
        source=(ROOT/'Core/OfficialActionCoordinator.swift').read_text()
        self.assertLess(source.index('try locks.insert(lock)'),source.index('try await access.send(review.command)'))
        self.assertIn('fresh == review.snapshot',source)
        self.assertIn('[identity.namespace, String(identity.accountID), command.scope]',source)
        self.assertNotIn('retry(',source)
    def test_fixture_bypasses_production_session(self):
        app=(ROOT/'App/QuestifyApp.swift').read_text()
        self.assertEqual(app.count('contains("--official-action-fixture")'),2)
        fixture=(ROOT/'App/OfficialActionFixtureHost.swift').read_text()
        self.assertIn('let enabled = false',fixture)
        self.assertNotIn('HTTPTransport',fixture)
    def test_additive_hosts_keep_read_scope(self):
        home=(ROOT/'App/SessionHomeFeedView.swift').read_text()
        self.assertIn('actions:session.officialActionCoordinator',home)
        self.assertIn('.id(session.officialEventReader.scope)',home)
        self.assertIn('OfficialParticipationActions', (ROOT/'App/OfficialEventDetailView.swift').read_text())
        self.assertIn('OfficialInviteResponseActions', (ROOT/'App/OfficialPrivateViews.swift').read_text())
    def test_catalog_exact_merge(self):
        fragment=json.loads((ROOT/'docs/official-action-localizations.json').read_text())['strings']
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for key,value in fragment.items():self.assertEqual(catalog[key],value)
