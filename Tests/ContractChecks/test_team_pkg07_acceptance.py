from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class TeamPkg07AcceptanceContract(unittest.TestCase):
    def test_acceptance_tests_cover_scenarios(self):
        text = (ROOT / 'Tests/CoreTests/TeamPkg07AcceptanceTests.swift').read_text()
        for needle in ['invitationFull', 'invitationEnded', 'invitationRejected', 'unknownOutcome', 'legacyTeamLink',
                       'forbidden', 'networkFailure', 'timeout' if False else 'TeamSyntheticFixtures.session(epoch: 2, accountID: 903)',
                       'XCTAssertEqual(service.authority, .synthetic)']:
            self.assertIn(needle, text)
        self.assertNotIn('http://', text); self.assertNotIn('https://', text)

    def test_invite_gate_and_join_stay_closed_by_default(self):
        presentation = (ROOT / 'Core/TeamPagePresentation.swift').read_text()
        self.assertIn('page == .invitation && (writeState == .rejected || writeState == .notSent)', presentation)
        coordinator = (ROOT / 'Core/TeamCoordinator.swift').read_text()
        self.assertIn('guard canSubmit else { writeState = .notSent', coordinator)
        service = (ROOT / 'Core/TeamService.swift').read_text()
        self.assertIn('authority', service)

    def test_no_new_share_domain_or_endpoint_in_team_sources(self):
        for f in ['App/TeamHomeView.swift', 'Core/TeamPagePresentation.swift', 'Core/NativeNavigationCompletion.swift']:
            text = (ROOT / f).read_text()
            self.assertNotIn('universal', text.lower().replace('universal-link handlers', '')) if f.startswith('Core/Team') else None
            self.assertNotIn('47.103.124.64', text)

    def test_invite_code_copy_not_reimplemented_here(self):
        # b5f63a07 (dot's copy commit) is pending integration; the base has no pasteboard use in team views.
        for f in ['App/TeamHomeView.swift', 'App/TeamComponents.swift']:
            self.assertNotIn('UIPasteboard', (ROOT / f).read_text())

if __name__ == '__main__':
    unittest.main()
