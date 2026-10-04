"""Source contracts; exact native popup and outcomes remain simulator acceptance gates."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubCustomerPopoverContractTests(unittest.TestCase):
    def test_choice_uses_unique_native_leaf_scoped_to_real_sheet(self):
        source = (ROOT / 'Tests/AppUITests/ModuleFlowTests.swift').read_text()
        helper = source.split('private func chooseClubMemberAction(', 1)[1].split('private func cancelClubMemberChoice', 1)[0]
        for token in ['app.sheets.firstMatch', 'sheet.buttons.matching(identifier: id)', 'leaves.count == 1',
                      'descendants(matching: .button).count == 0', 'snapshot.label == label', 'snapshot.isEnabled',
                      'leaf.isHittable', 'sheet.frame.contains(snapshot.frame)', 'app.frame.insetBy(dx: 4, dy: 4).contains(snapshot.frame)']:
            self.assertIn(token, helper)
        self.assertNotIn('tap(app.buttons["club.member.choice.', source)

    def test_cancel_dismisses_without_navigating_and_original_privacy_assertions_remain(self):
        source = (ROOT / 'Tests/AppUITests/ModuleFlowTests.swift').read_text()
        for token in ['dismissFixtureConfirmationPopover(in: app', 'tapFixtureSheetAction("Cancel", in: sheet',
                      'XCTWaiter.wait(for: [dismissed], timeout: 5)', 'testClubCustomerChoiceDeniedAndWrongMemberFailClosed',
                      'testClubCustomerDetailClearsOnAccountSwitch', 'testClubCustomerRoleABADoesNotRestoreOldPrivateDestination',
                      'XCTAssertFalse(app.staticTexts["Fixture customer"].exists)', 'XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))']:
            self.assertIn(token, source)

if __name__ == '__main__': unittest.main()
