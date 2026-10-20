"""Focused static checks only: does not execute Swift, UIKit or XCTest."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class TeamInviteCopyContractTests(unittest.TestCase):
    def test_copy_is_only_synchronous_tap_and_local_only(self):
        source = (ROOT / 'App/TeamComponents.swift').read_text()
        self.assertEqual(source.count('UIPasteboard.general'), 1)
        self.assertIn('Button("team.invite.copy") { copyInvitationCode(code) }', source)
        self.assertIn('model.copyInvitationCode(from: team, code: code, permit: copyPermit)', source)
        self.assertIn('options: [.localOnly: true]', source)
        self.assertIn('UTType.utf8PlainText.identifier: value', source)
        boundary = source.split('func copyInvitationCode(from team:', 1)[1].split('var reviewBinding:', 1)[0]
        self.assertLess(boundary.index('coordinator.synchronizeSession()'), boundary.index('guard let permit'))
        for guard in ['inviteCopyPermit == permit', 'permit.presentationID == presentationID', 'permit.scope == coordinator.scope', '!actionLocked', 'current.id == team.id', 'current.status == .recruiting', 'team.inviteCode == code', 'current.inviteCode == code', 'TeamLookup.validInvite(code)']:
            self.assertIn(guard, boundary)
        self.assertLess(boundary.index('else { return false }'), boundary.index('write(code)'))
        for forbidden in ['Task {', 'await ', 'submit(', 'prepare(', 'URLSession', 'openURL(', 'ShareLink(']:
            self.assertNotIn(forbidden, boundary)

    def test_parent_gate_and_feedback_lifetime(self):
        home = (ROOT / 'App/TeamHomeView.swift').read_text()
        self.assertIn('if !readOnly, detail.team.status == .recruiting, let code = detail.team.inviteCode, TeamLookup.validInvite(code)', home)
        self.assertIn('TeamInvitePreview(team: team, model: model)', home)
        source = (ROOT / 'App/TeamComponents.swift').read_text()
        self.assertIn('.onChange(of: team)', source)
        self.assertIn('.onAppear { copyPermit = model.beginInvitePreview() }', source)
        self.assertIn('.onDisappear { endPreview() }', source)
        self.assertIn('model.endInvitePreview(copyPermit)', source)
        self.assertIn('copyPermit = nil', source)
        self.assertIn('copyMessageKey = nil', source)
        self.assertIn('copied ? "team.invite.copied" : "team.invite.unavailable"', source)
        self.assertIn('Button("team.close") { endPreview(); dismiss() }', source)

    def test_catalog_matches_fragment_for_both_languages(self):
        fragment = json.loads((ROOT / 'Resources/TeamLocalizations.fragment.json').read_text())['strings']
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['team.invite.copy', 'team.invite.copied', 'team.invite.previewOnly']:
            self.assertEqual(fragment[key], catalog[key])
            self.assertEqual(set(catalog[key]['localizations']), {'en', 'zh-Hans'})
        self.assertIn('No invitation was sent', catalog['team.invite.copied']['localizations']['en']['stringUnit']['value'])

    def test_authored_runtime_coverage_is_present_not_executed(self):
        unit = (ROOT / 'Tests/AppUnitTests/TeamNoticePresentationTests.swift').read_text()
        for name in ['testClosedDepartedAndReplacedPreviewPermitsCannotCopy', 'testOnlyExplicitCopyWritesExactCodeAndNeverSubmits', 'testLogoutAccountSwitchAndReauthenticationRejectOldPreview', 'testChangedCodeTeamStatusAndInvalidCodeRejectCopy']:
            self.assertIn(name, unit)
        self.assertIn('testInvitationCopyFeedbackCloseAndReopen', (ROOT / 'Tests/AppUITests/TeamFlowTests.swift').read_text())

if __name__ == '__main__': unittest.main()
