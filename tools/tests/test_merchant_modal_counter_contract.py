"""Source contracts only; native confirmation and app-hosted tests require Apple."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class MerchantModalCounterContractTests(unittest.TestCase):
    def test_no_background_counter_query_while_alert_is_present(self):
        source = (ROOT / 'Tests/AppUITests/MerchantOnboardingFlowTests.swift').read_text()
        helper = source.split('private func tapSubmissionDialogButton(', 1)[1].split('private func reviewAndConfirm', 1)[0]
        before, after = helper.split('action.tap()', 1)
        self.assertNotIn('assertCount(', before)
        self.assertLess(after.index('XCTWaiter.wait(for: [dismissed]'), after.index('assertCount('))
        self.assertIn('if actionTitle == "Cancel"', after)
        counter = source.split('private func assertCount(', 1)[1].split('private func beginReapply', 1)[0]
        self.assertIn('XCTAssertFalse(app.alerts.firstMatch.exists', counter)
        self.assertIn('exists == true AND label == %@', counter)
        self.assertIn('timeout: 5', counter)
        self.assertNotIn('snapshot()', counter)

    def test_actual_fixture_counters_are_monotonic_not_reset_by_cancel(self):
        source = (ROOT / 'App/MerchantOnboardingFixtureSupport.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        for counter in ['submissionCount', 'uploadCount']:
            writes = re.findall(r'\b' + counter + r'\s*(?:\+=|-=|=)\s*\d+', source)
            self.assertEqual(writes, [counter + ' = 0', counter + ' += 1'])
        model = (ROOT / 'App/MerchantOnboardingModel.swift').read_text()
        cancel = model.split('func cancelConfirmation()', 1)[1].split('func submitConfirmed()', 1)[0]
        self.assertNotIn('submissionCount', cancel)
        self.assertNotIn('uploadCount', cancel)

    def test_original_disclosure_and_exact_before_after_counts_remain(self):
        source = (ROOT / 'Tests/AppUITests/MerchantOnboardingFlowTests.swift').read_text()
        for required in ['XCTAssertEqual(dialog.label, "Submit this merchant application?"', '"configured Chengyin service"',
                         '"uploaded license reference"', 'assertCount("merchant.onboarding.fixture.writeCount", 0)',
                         'assertCount("merchant.onboarding.fixture.writeCount", 1)', 'assertCount("merchant.onboarding.fixture.uploadCount", 0)',
                         'tapSubmissionDialogButton("Cancel")', 'tapSubmissionDialogButton("Submit for review")',
                         'XCTAssertEqual(status.label, "Under review")']:
            self.assertIn(required, source)
        flow = source.split('private func reviewAndConfirm()', 1)[1].split('private func capture', 1)[0]
        self.assertLess(flow.index('tapSubmissionDialogButton("Cancel")'), flow.index('tapSubmissionDialogButton("Submit for review")'))

if __name__ == '__main__': unittest.main()
