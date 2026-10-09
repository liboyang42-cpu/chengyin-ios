import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import ci138_coupon_square_publication_driver as driver


class CI138CouponSquarePublicationDriverTests(unittest.TestCase):
    def setUp(self):
        self.contract = driver.contract()

    def source(self, name):
        return (driver.ROOT / 'Tests/AppUITests' / name).read_text()

    def test_current_sources_and_unchanged_boundaries_validate(self):
        driver.validate_current()

    def test_every_inverse_restores_exact_preimage_and_method_inventory(self):
        for path, row in self.contract['files'].items():
            current = (driver.ROOT / path).read_bytes()
            original = driver.previous_source(path, current)
            self.assertEqual(driver.digest(original), row['before_sha256'])
            self.assertEqual(re.findall(rb'func (test\w+)\(', current),
                             re.findall(rb'func (test\w+)\(', original))

    def test_unknown_or_partial_source_is_rejected(self):
        for path in self.contract['files']:
            current = (driver.ROOT / path).read_bytes()
            with self.assertRaises(ValueError):
                driver.previous_source(path, current + b'\n')
            original = driver.previous_source(path, current)
            with self.assertRaises(ValueError):
                driver.previous_source(path, original)
        with self.assertRaises(ValueError):
            driver.previous_source('App/CouponCodeView.swift', b'')

    def test_contract_mutation_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            changed = Path(directory) / 'contract.json'
            changed.write_text(json.dumps(self.contract) + '\n')
            with patch.object(driver, 'CONTRACT', changed), self.assertRaises(ValueError):
                driver.contract()

    def test_exact_inverse_replays_unchanged_prior_planner(self):
        from tools.run_ui_shard import measured_weights
        driver.validate_current()
        from tools.run138_current_source_projection import frozen_context
        component = frozen_context('coupon')
        with tempfile.TemporaryDirectory() as directory:
            previous_ui = Path(directory) / 'AppUITests'
            previous_ui.mkdir()
            for source in (component.root / 'Tests/AppUITests').glob('*.swift'):
                relative = 'Tests/AppUITests/' + source.name
                raw = source.read_bytes()
                if relative in self.contract['files']:
                    raw = driver.previous_source(relative, raw)
                (previous_ui / source.name).write_bytes(raw)
            costs = measured_weights(previous_ui, driver.ROOT / 'tools/ui_duration_weights.json')
            self.assertEqual(costs['OwnedCouponCodeJourneyUITests'], 360)
            self.assertEqual(costs['SquareWorkspaceFlowTests'], 132.249)
            self.assertEqual(costs['ApprovedTopicFrozenCoverPublicationFlowTests'], 908)

    def test_coupon_cancels_actual_presentation_then_requires_fresh_confirmation(self):
        source = self.source('OwnedCouponCodeJourneyUITests.swift')
        cancel = source.index('let sheet = app.sheets.firstMatch')
        reopen = source.index('tap("couponCode.review"); XCTAssertTrue(confirm.waitForExistence', cancel)
        section = source[cancel:reopen]
        self.assertIn('if app.popovers.firstMatch.exists', section)
        self.assertIn('dismissFixtureConfirmationPopover(in: app)', section)
        self.assertIn('app.sheets.buttons["Cancel"].tap()', section)
        self.assertIn('XCTWaiter.wait(for: [dismissed], timeout: 5)', section)
        self.assertIn('XCTAssertFalse(app.images["couponCode.qr"].exists); assertIssues(0)', section)
        self.assertIn('confirm.tap()', source[reopen:])
        self.assertIn('XCTAssertTrue(app.images["couponCode.qr"].waitForExistence(timeout: 5)); assertIssues(1)', source)
        self.assertIn('Owned coupon reopened with fresh review and no retained code', source)

    def test_square_shared_helper_uses_keyboard_viewport_and_direction(self):
        source = self.source('SquareWorkspaceFlowTests.swift')
        helper = source.split('private func reveal(', 1)[1].split('private func launch(', 1)[0]
        self.assertIn('towardTop: !upwards, maximumSwipes: 10', helper)
        self.assertNotIn('element.identifier', helper)
        self.assertNotIn('app.swipeUp()', helper)
        self.assertIn('XCTAssertTrue(element.exists', helper)
        self.assertIn('XCTAssertTrue(element.isHittable', helper)
        self.assertIn('XCTAssertEqual(status.label, "已保存在本机", app.debugDescription)', source)
        self.assertIn('"label == %@", "Local only"', source)
        self.assertIn('XCTAssertFalse(app.alerts.firstMatch.exists)', source)

    def test_square_complete_methods_charge_all_private_reveal_call_sites(self):
        source = self.source('SquareWorkspaceFlowTests.swift')
        bodies = dict((name, body) for body, name in re.findall(
            r'(?m)^    (func (test\w+)\b[\s\S]*?^    })', source))
        expected = {'testChineseComposerAndLocalDraftEntry': 3,
                    'testSuspendedRecoveryDisablesNewDraftTypingAndCompetingResume': 2,
                    'testDefaultWorkspaceHasNoEnabledNetworkActions': 0}
        for name, count in expected.items():
            self.assertEqual(len(re.findall(r'(?<!\w)reveal\(', bodies[name])), count)

    def test_frozen_request_reveals_before_read_and_retains_recovery_semantics(self):
        source = self.source('ApprovedTopicFrozenCoverPublicationFlowTests.swift')
        unconfirmed = source.index('XCTAssertTrue(app.staticTexts["approvedRelease.publication.unconfirmed"]')
        reveal = source.index('revealFixtureElement(requestValue, in: app, maximumSwipes: 10, requiresHittable: false)')
        wait = source.index('requestValue.waitForExistence(timeout: 5)')
        read = source.index('let request = requestValue.label')
        self.assertTrue(unconfirmed < reveal < wait < read)
        for retained in ['XCTAssertFalse(request.isEmpty)',
                         'value("approvedRelease.publication.requestID", request, in: app)',
                         'value("approvedRelease.selectedCover.selection", "9", in: app)',
                         'value("approvedRelease.publication.releaseID", "501", in: app)',
                         'value("approvedRelease.publication.manifestHash", String(repeating: "a", count: 64), in: app)',
                         'XCTAssertFalse(app.buttons["approvedRelease.publication.retry"].exists)',
                         'XCTAssertEqual(Array(target.label.utf8), Array(expected.utf8))']:
            self.assertIn(retained, source)

    def test_complete_method_costs_are_unmeasured_additive_and_include_square_recovery(self):
        costs = driver.complete_method_costs()
        self.assertEqual(sorted(costs.values()), [110, 120, 380, 940])
        self.assertEqual(len(costs), 4)
        for method, seconds in costs.items():
            self.assertGreater(seconds, self.contract['complete_method_costs'][method]['historical_seconds'])
            self.assertFalse(self.contract['complete_method_costs'][method]['measured'])

    def test_publication_exception_is_explicitly_pending_not_old_908_approval(self):
        rows = [row for row in self.contract['complete_method_costs'].values() if row['candidate_seconds'] > 900]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['historical_seconds'], 908)
        self.assertIn('REQUIRES_EXPLICIT_NEW_SOURCE_BOUND_940_SECOND_EXCEPTION', rows[0]['exception_status'])

    def test_standalone_shards_include_reserve_but_do_not_claim_aggregate_fit(self):
        for row in self.contract['standalone_shards'].values():
            self.assertGreater(row['after_seconds'], row['before_seconds'])
            self.assertLessEqual(row['after_seconds'] + self.contract['startup_reserve_seconds'],
                                 self.contract['deadline_seconds'])
        self.assertIn('aggregate all candidates', self.contract['integration_status'])


if __name__ == '__main__':
    unittest.main()
