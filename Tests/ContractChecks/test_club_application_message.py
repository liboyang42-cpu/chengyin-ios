import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class ClubApplicationMessageContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_frozen_message_reaches_dispatch(self):
        c = self.read('Core/ClubActionCoordinator.swift')
        self.assertIn('public let joinMessage: String', c)
        self.assertIn('joinMessage: confirmation.joinMessage', c)
        self.assertIn('joinMessage: joinMessage', self.read('Core/ClubActionWriting.swift'))
    def test_bounds_apply_at_all_boundaries(self):
        self.assertIn('message.utf16.count <= maximumUTF16Count', self.read('Core/ClubActionContracts.swift'))
        for path in ['Core/ClubActionCoordinator.swift', 'Core/ClubActionWriting.swift', 'Core/ClubActionService.swift']:
            self.assertIn('ClubApplicationMessage.isValid(joinMessage, for: action)', self.read(path))
    def test_current_join_json_preserves_numeric_id_and_only_application_message(self):
        s = self.read('Core/ClubActionService.swift')
        self.assertIn('if action != .leave {', s)
        self.assertIn('request.setValue("application/json", forHTTPHeaderField: "Content-Type")', s)
        self.assertIn('["id": clubID]', s)
        self.assertIn('if action == .apply { fields["joinMessage"] = joinMessage }', s)
    def test_optional_verbatim_received_message(self):
        self.assertIn('decodeIfPresent(String.self, forKey: .joinMessage)', self.read('Core/ClubManagementContracts.swift'))
        self.assertIn('Text(verbatim: message).accessibilityIdentifier("club.management.joinMessage")', self.read('App/ClubManagementView.swift'))
    def test_review_and_identity_reset(self):
        s = self.read('App/ClubActionPanel.swift')
        self.assertIn('value.joinMessage', s)
        self.assertIn('joinMessage: reviewedMessage', s)
        self.assertIn('joinMessage = ""; revision', s)
        self.assertIn('.onChange(of: identity)', s)
    def test_all_protocol_conformers_accept_message(self):
        for path in ['Core/ClubActionWriting.swift', 'App/ClubActionFixtureSupport.swift', 'Tests/CoreTests/ClubActionCoordinatorTests.swift']:
            self.assertIn('expectedIdentity: ClubReadIdentity, joinMessage: String', self.read(path))
