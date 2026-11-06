"""Invite detail opens the injected public topic and Back re-reads that invite. Source only."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()


class CooperationProjectNavigationContract(unittest.TestCase):
    def setUp(self):
        self.nav = read('App/CooperationProjectNavigation.swift')
        self.detail = read('App/CooperationInviteDetailView.swift')
        self.browser = read('App/CooperationBrowserView.swift')
        self.actions = read('App/CooperationInviteActionSections.swift')

    def test_missing_or_non_positive_topic_does_not_open(self):
        self.assertIn('var opens: Bool { topicID > 0 }', self.nav)
        self.assertIn('if let route, route.opens, destination != nil', self.nav)
        self.assertIn('if CooperationProjectNavigation(topicID: topicID, invite: invite).opens, let destination', self.nav)
        self.assertIn('CooperationTopicReference(id: topic)', self.detail)
        self.assertNotIn('publisherDestination', self.nav + self.detail)
        self.assertNotIn('reviewOwner', self.nav)
        self.assertNotIn('selfPlayDestination', self.nav)

    def test_list_injects_the_same_destination_into_both_details(self):
        received = 'CooperationInviteDetailView(key: CooperationInviteKey(id: row.id, direction: direction), reader: reader, peerReader: peerReader)'
        sent = 'CooperationInviteDetailView(key: CooperationInviteKey(id: linked, direction: .sent), reader: reader, peerReader: peerReader)'
        self.assertIn(received, self.browser)
        self.assertIn(sent, self.browser)
        self.assertEqual(self.browser.count('.environment(\\.cooperationProjectDestination, topicDestination)'), 2)
        self.assertIn('CooperationProjectNavigationLink(topicID: topic, invite: key, destination: topicDestination, openedTopic: $openedTopic)', self.detail)

    def test_back_rereads_the_same_invite_and_keeps_filters(self):
        self.assertIn('resource: "invite.\\(key.direction.rawValue).\\(key.id).return.\\(topicReturn)"', self.detail)
        self.assertIn('guard key.id > 0 else { throw CooperationReadFailure.unavailable }', self.detail)
        self.assertIn('return try await phoneCopy.load(reader: reader, key: key)', self.detail)
        self.assertIn('guard previous != nil, next == nil else { return }', self.detail)
        self.assertIn('topicReturn &+= 1', self.detail)
        self.assertIn('resource: "inbox.\\(direction.rawValue)"', self.browser)
        self.assertIn('.onChange(of: reader.scope) { _, _ in topicFilter = nil }', self.browser)
        self.assertNotIn('topicFilter = nil', self.browser.split('private func invitationSection', 1)[1])
        for banned in ['api/coop/invite', 'perform(', 'URLSession', 'HTTPTransport']:
            self.assertNotIn(banned, self.nav + self.detail)

    def test_scope_change_closes_the_destination_and_retry_stays_independent(self):
        self.assertIn('CooperationProjectNavigationHost(scope: reader.scope, authenticated: reader.isAuthenticated, reader: ObjectIdentifier(reader))', self.browser)
        for hook in ['reader.scope', 'ObjectIdentifier(reader)', 'reader.isAuthenticated', 'key']:
            self.assertIn('onChange(of: %s' % hook, self.detail)
        self.assertIn('openedTopic = nil', self.detail)
        self.assertNotIn('cooperation.retry', self.nav)
        self.assertIn('Button("cooperation.retry", action: retry)', read('App/CooperationComponents.swift'))
        self.assertIn('Button("cooperation.detail.deposit.pay") {}.disabled(true)', self.actions)
        self.assertIn('NavigationLink { CoopFlowHandleEditor(inviteID: invite.id, action: .cancel, currentStatus: 1) }', self.actions)


if __name__ == '__main__':
    unittest.main()
