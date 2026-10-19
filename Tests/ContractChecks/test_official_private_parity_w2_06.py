"""Official inbox / my-published source parity wiring checks; not Swift compilation/runtime evidence."""
from pathlib import Path
import json
import os
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
KEYS_FRAGMENT = Path(os.environ.get(
    'OFFICIAL_PRIVATE_PARITY_KEYS',
    ''))
SWIFT = ['App/OfficialPrivateViews.swift', 'App/OfficialActionViews.swift', 'App/OfficialActionFixtureHost.swift',
         'Core/OfficialPrivatePresentation.swift', 'Core/OfficialActionContracts.swift']


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


class OfficialPrivateParityChecks(unittest.TestCase):
    def test_fixed_source_reasons_and_no_free_text(self):
        core = read('Core/OfficialPrivatePresentation.swift')
        self.assertIn('case .decline: return "主体拒绝本场邀约"', core)
        self.assertIn('case .withdraw: return "主体退出本场职责"', core)
        self.assertIn('.respond(partyID: invite.id, type: invite.partyType ?? "", action: action, reason: action.sourceReason)', core)
        view = read('App/OfficialActionViews.swift')
        responder = view.split('struct OfficialInviteResponseActions', 1)[1].split('/// One sheet occurrence', 1)[0]
        self.assertIn('OfficialActionCommand.sourceInboxResponse(to: invite, action: action)', responder)
        self.assertNotIn('TextField', responder)
        self.assertNotIn('reason: reason', responder)
        self.assertIn('OfficialInboxPresentation.actions(for: invite)', responder)
        self.assertIn('requiresOrganizerTransfer(invite, action: action)', responder)

    def test_source_eligibility(self):
        core = read('Core/OfficialPrivatePresentation.swift')
        self.assertIn('invite.partyType == "OFFICIAL" && invite.role == "ORGANIZER"', core)
        self.assertIn('case "INVITED": return [.decline, .accept]', core)
        self.assertIn('case "ACCEPTED", "ACTIVE": return isOrganizerInvite(invite) ? [] : [.withdraw]', core)
        contracts = read('Core/OfficialActionContracts.swift')
        self.assertIn('if type == "OFFICIAL" && reason == nil { return nil }', contracts)
        self.assertIn('!(type == "OFFICIAL" && action == .withdraw)', contracts)

    def test_disabled_gate_and_review_still_in_place(self):
        coordinator = read('Core/OfficialActionCoordinator.swift')
        self.assertIn('guard access.enabled else { throw OfficialActionFailure.disabled }', coordinator)
        self.assertLess(coordinator.index('try locks.insert(lock)'), coordinator.index('try await access.send(review.command)'))
        self.assertIn('[identity.namespace, String(identity.accountID), command.scope]', coordinator)
        self.assertIn('case .respond(let id, _, _, _): return "party:\\(id)"', read('Core/OfficialActionContracts.swift'))
        self.assertIn('enabled: Bool = false', read('Core/OfficialActionService.swift'))
        self.assertIn('let approved:[RegionalMarket:Set<String>]=[:]', read('App/RegionalLaunchConfiguration.swift'))
        fixture = read('App/OfficialActionFixtureHost.swift')
        self.assertIn('let enabled = false', fixture)
        self.assertIn('throw OfficialActionFailure.disabled', fixture)
        self.assertNotIn('HTTPTransport', fixture)
        self.assertIn('OfficialInboxView(reader: OfficialFixtureReader(), actions: coordinator)', fixture)
        sheet = read('App/OfficialActionViews.swift').split('struct OfficialActionSheet', 1)[1].split('struct OfficialPublishEditor', 1)[0]
        self.assertIn('.disabled(busy || !coordinator.enabled || receipt != nil)', sheet)

    def test_published_owner_status_wiring(self):
        view = read('App/OfficialPrivateViews.swift')
        self.assertIn('OfficialPublishedPresentation.ownerStatusKey(event.status)', view)
        self.assertIn('official.published.event.', view)
        core = read('Core/OfficialPrivatePresentation.swift')
        for code, name in [('0', 'draft'), ('1', 'pending'), ('9', 'offline')]:
            self.assertIn('case %s?: return "official.privateParity.published.status.%s"' % (code, name), core)

    def test_existing_identifiers_kept(self):
        view = read('App/OfficialPrivateViews.swift')
        for ident in ['official.inbox.content', 'official.published.content', 'official.invite.', 'official.broadcast.', 'official.stats.content']:
            self.assertIn(ident, view)
        actions = read('App/OfficialActionViews.swift')
        for ident in ['officialAction.confirm', 'officialAction.reviewPayload', 'officialAction.message']:
            self.assertIn(ident, actions)

    def test_new_identifiers_are_prefixed(self):
        for path in SWIFT:
            for ident in re.findall(r'accessibilityIdentifier\("([^"\\]+)', read(path)):
                if ident.startswith('official.') and ident not in {
                        'official.inbox.content', 'official.published.content', 'official.stats.content'} \
                        and not ident.startswith(('official.invite.', 'official.broadcast.')):
                    self.assertTrue(ident.startswith(('official.inbox.', 'official.published.')), ident)

    def test_every_parity_key_is_localized(self):
        known = set(json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text(encoding='utf-8'))['strings'])
        fragment = {}
        if KEYS_FRAGMENT.is_file():
            fragment = json.loads(KEYS_FRAGMENT.read_text(encoding='utf-8'))
            for key, value in fragment.items():
                self.assertTrue(key.startswith('official.privateParity.') and key.isascii(), key)
                self.assertTrue(value.get('en') and value.get('zh-Hans'), key)
        used = set()
        for path in SWIFT:
            used.update(re.findall(r'"(official\.privateParity\.[A-Za-z0-9_.]+)"', read(path)))
        self.assertTrue(used)
        missing = sorted(key for key in used if key not in known and key not in fragment)
        self.assertEqual(missing, [])


if __name__ == '__main__':
    unittest.main()
