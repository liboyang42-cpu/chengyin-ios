"""Structural preservation only; actual XCTest rerun is independently required."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class WaitlistReviewUIContracts(unittest.TestCase):
    def test_cancel_confirmation_retains_negative_and_terminal_assertions(self):
        source = (ROOT / 'Tests/AppUITests/RegistrationWaitlistUITests.swift').read_text()
        method = source.split('func testWaitingAndLeavingRemainInTheRegistrationForm()')[1].split('func testOfferRequires')[0]
        self.assertLess(method.index('confirmation.buttons["Cancel"].tap()'), method.index('confirmation.buttons["Leave waitlist"].tap()'))
        self.assertIn('XCTAssertTrue(app.staticTexts["Waiting for an available place"].exists, app.debugDescription)', method)
        self.assertEqual(method.count('XCTAssertFalse(app.staticTexts["Waitlist entry cancelled"].exists)'), 2)
        self.assertIn('XCTAssertTrue(app.staticTexts["Waitlist entry cancelled"].waitForExistence(timeout: 5), app.debugDescription)', method)
        self.assertEqual(method.count('XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)'), 2)
        self.assertIn('XCTAssertTrue(app.navigationBars["Activity registration"].exists)', method)

    def test_order_diagnostic_does_not_relax_the_pending_exact_assertion(self):
        source = (ROOT / 'Tests/AppUITests/RegistrationWaitlistOrderUITests.swift').read_text()
        self.assertIn('"订单号, OFFLINE-WAITLIST-9417"', source)
        self.assertEqual(source.count('XCTAssertTrue(app.staticTexts[orderNumber].waitForExistence(timeout: 5), app.debugDescription)'), 2)
        self.assertIn('XCTAssertFalse(review.isEnabled)', source)
