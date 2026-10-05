"""Run101 AX-backed selector contracts; this is not simulator execution."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubCustomerFactAccessibilityTests(unittest.TestCase):
    def test_all_positive_customer_checks_verify_exact_fact_row_and_value(self):
        source = (ROOT / 'Tests/AppUITests/ModuleFlowTests.swift').read_text()
        self.assertNotIn('XCTAssertTrue(app.staticTexts["Fixture customer"]', source)
        self.assertEqual(source.count('app.staticTexts["club.gov.fact.displayName"].waitForExistence(timeout: 5)'), 5)
        self.assertEqual(source.count('XCTAssertEqual(app.staticTexts["club.gov.fact.displayName"].label, "Customer, Fixture customer"'), 5)

    def test_each_original_privacy_absence_also_requires_the_actual_row_absent(self):
        source = (ROOT / 'Tests/AppUITests/ModuleFlowTests.swift').read_text()
        lines = source.splitlines()
        old = [i for i, line in enumerate(lines) if 'XCTAssertFalse(app.staticTexts["Fixture customer"].exists' in line]
        self.assertEqual(len(old), 6)
        for index in old:
            self.assertIn('XCTAssertFalse(app.staticTexts["club.gov.fact.displayName"].exists', lines[index + 1])

    def test_row_identifier_remains_source_backed_and_privacy_guards_intact(self):
        facts = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.assertIn('LabeledContent(LocalizedStringKey("club.gov.field." + key))', facts)
        self.assertIn('.accessibilityIdentifier("club.gov.fact." + key)', facts)
        members = (ROOT / 'App/ClubMembersView.swift').read_text()
        for token in ['target.viewerRevision == governance?.viewerRevision', 'target.identity == reader.clubIdentity',
                      'matchesGovernance(target.identity)', 'target.memberID > 0, id > 0']:
            self.assertIn(token, members)

if __name__ == '__main__': unittest.main()
