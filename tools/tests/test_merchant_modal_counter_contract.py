"""Source contract only; modal snapshot behavior requires Apple UI acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class MerchantModalCounterContractTests(unittest.TestCase):
    def test_each_wait_poll_uses_fresh_exact_unique_snapshot_counter(self):
        source = (ROOT / 'Tests/AppUITests/MerchantOnboardingFlowTests.swift').read_text()
        helper = source.split('private func assertCount(', 1)[1].split('private func beginReapply', 1)[0]
        self.assertLess(helper.index('NSPredicate {'), helper.index('try? app.snapshot()'))
        for required in ['node.identifier == id', 'node.elementType == .staticText', 'pending.append(contentsOf: node.children)',
                         'counts.count == 1 && counts[0].label == String(count)', 'timeout: 5']:
            self.assertIn(required, helper)
        for forbidden in ['.tap()', '.debugDescription.contains', 'timeout: 10', 'cached']:
            self.assertNotIn(forbidden, helper.split('let expected', 1)[1])

    def test_confirmation_and_write_assertions_remain(self):
        source = (ROOT / 'Tests/AppUITests/MerchantOnboardingFlowTests.swift').read_text()
        for required in ['XCTAssertEqual(dialog.label, "Submit this merchant application?"', '"configured Chengyin service"',
                         '"uploaded license reference"', 'assertCount("merchant.onboarding.fixture.writeCount", 0)',
                         'assertCount("merchant.onboarding.fixture.writeCount", 1)', 'assertCount("merchant.onboarding.fixture.uploadCount", 0)',
                         'tapSubmissionDialogButton("Cancel")', 'tapSubmissionDialogButton("Submit for review")',
                         'XCTAssertEqual(status.label, "Under review")']:
            self.assertIn(required, source)

if __name__ == '__main__': unittest.main()
