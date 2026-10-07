"""Protect exact readiness and fail-closed privacy checks; not runtime evidence."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
PREFIX='    /// Only the denied/wrong-member fixture case uses this diagnostic variant.'
AFTER='    private func openClubHistoryTopic('
CASE='''    func testClubCustomerChoiceDeniedAndWrongMemberFailClosed() {
        for (scenario, member) in [("customerDenied", 704), ("customerOwner", 703)] {
            launch(["--uitesting-club-fixture", scenario])
            tapClubCustomerEntry(app.buttons["club.member.\\(member)"])
            chooseClubMemberAction("club.member.choice.customer", label: "Customer detail")
            XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
            XCTAssertFalse(app.staticTexts["club.gov.fact.displayName"].exists)
            app.terminate()
        }
    }
'''
def helper(source):return source.split(PREFIX,1)[1].split(AFTER,1)[0]
def valid_helper(source):
    s=helper(source)
    return ('let result = XCTWaiter.wait(for: [ready], timeout: 10)' in s
        and 'return exists && hittable' in s
        and 'let hittable = exists && element.isHittable' in s
        and 'guard result == .completed else { return }\n        element.tap()' in s
        and s.count('element.tap()')==1
        and 'evaluations.suffix(16)' in s
        and 'XCTAssertEqual(result, .completed, app.debugDescription, file: file, line: line)' in s)
def valid_case(source):
    begin='    func testClubCustomerChoiceDeniedAndWrongMemberFailClosed()'
    method=begin+source.split(begin,1)[1].split('    func testClubCustomerDetailClearsOnRoleRevisionThenRechecks()',1)[0]
    return method==CASE
class ClubCustomerReadinessDiagnosticContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.source=(ROOT/'Tests/AppUITests/ModuleFlowTests.swift').read_text()
    def test_bounded_original_condition_and_failure_result_are_preserved(self):
        self.assertTrue(valid_helper(self.source)); self.assertTrue(valid_case(self.source))
        s=helper(self.source)
        self.assertIn('AFTER_TIMEOUT_ONLY',s)
        self.assertLess(s.index('let result ='),s.index('AFTER_TIMEOUT_ONLY'))
        self.assertIn('if result != .completed {',s)
        self.assertEqual(self.source.count('tapClubCustomerEntry(app.buttons['),1)
    def test_negative_controls_reject_weak_readiness_long_wait_or_extra_tap(self):
        for text in [self.source.replace('return exists && hittable','return exists',1),
                     self.source.replace('for: [ready], timeout: 10','for: [ready], timeout: 15',1),
                     self.source.replace('        element.tap()\n    }\n    private func openClubHistoryTopic','        element.tap(); element.tap()\n    }\n    private func openClubHistoryTopic',1),
                     self.source.replace('guard result == .completed else { return }','guard existsElsewhere else { return }',1)]:
            self.assertFalse(valid_helper(text))
    def test_negative_controls_reject_missing_private_data_guards_or_wrong_member_case(self):
        for text in [self.source.replace('            XCTAssertFalse(app.staticTexts["Fixture customer"].exists)\n','',1),
                     self.source.replace('            XCTAssertFalse(app.staticTexts["club.gov.fact.displayName"].exists)\n','',1),
                     self.source.replace('("customerOwner", 703)','("customerOwner", 704)',1)]:
            self.assertFalse(valid_case(text))
if __name__=='__main__':unittest.main()
