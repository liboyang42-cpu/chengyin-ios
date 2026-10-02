"""Portable UI source regressions; not Apple compilation, XCTest, or visual evidence."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WorkbenchUINavigationChecks(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_enrollment_ticket_identifier_does_not_replace_descendant_routes(self):
        source = self.text('App/ClubEnrollmentView.swift')
        self.assertIn('title(ticket.name, fallback: "club.enroll.unnamedTicket").font(.headline)\n'
                      '                        .accessibilityIdentifier("club.enroll.ticket.\\(ticket.id)")', source)
        self.assertNotIn('}.padding(.vertical, 6).accessibilityIdentifier("club.enroll.ticket.', source)
        for identifier in ['club.enroll.profile.', 'club.enroll.checkin.']:
            self.assertIn('.accessibilityIdentifier("' + identifier, source)
        self.assertIn('identity == reader.identity, identity == access.identity', source)
        self.assertIn('.onDisappear { reader.suspend() }', source)

    def test_nearby_application_preserves_its_withdraw_control(self):
        source = self.text('App/NearbyTeamViews.swift')
        self.assertIn('}.accessibilityElement(children: .contain)\n'
                      '                        .accessibilityIdentifier("nearby.application.', source)
        self.assertIn('if application.status == .pending { expiry(application.applyExpireTime); actionButton(.withdraw(application.id)) }', source)
        self.assertIn('.disabled(model.running || !coordinator.allowed(action))', source)

    def test_reveal_checks_viewport_and_keeps_gestures_above_keyboard(self):
        source = self.text('Tests/AppUITests/FailureScreenshot.swift')
        for fragment in ['navigationBar.frame.maxY', 'toolbar.frame.minY', 'keyboard.frame.minY',
                         'fullyVisible && (!requiresHittable || element.isHittable)',
                         'bounds.minY + bounds.height * startFraction',
                         'guard attempt < maximumSwipes, bounds.height > 80, app.frame.height > 0 else { break }']:
            self.assertIn(fragment, source)

    def test_merchant_scrolls_before_existence_assertion_and_checks_retained_lock(self):
        source = self.text('Tests/AppUITests/MerchantEngagementFlowTests.swift')
        helper = source.split('private func tap(', 1)[1].split('private func prepareSegment', 1)[0]
        self.assertLess(helper.index('reveal(element, app: app)'), helper.index('element.waitForExistence'))
        for fragment in ['reveal(locked, app: app, towardTop: true)',
                         'XCTAssertTrue(locked.waitForExistence(timeout: 5))',
                         'reveal(receipt, app: app)',
                         'merchant.engagement.liveDisabled',
                         'XCTAssertFalse(app.buttons["merchant.engagement.confirm"].exists)']:
            self.assertIn(fragment, source)

    def test_received_applications_require_successful_navigation(self):
        source = self.text('Tests/AppUITests/CooperationFlowUITests.swift')
        self.assertIn('app.descendants(matching: .any)["coopflow.workbench"]', source)
        self.assertNotIn('app.otherElements["coopflow.workbench"]', source)
        self.assertIn('app.navigationBars["Received club applications"].waitForExistence', source)
        self.assertEqual(source.count('openReceivedApplications(app)'), 4)
        for fragment in ['XCTAssertFalse(submit.isEnabled)', 'XCTAssertEqual(app.alerts.count, 0)',
                         'XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)',
                         'Sign in to view your cooperation']:
            self.assertIn(fragment, source)

    def test_governance_requires_specific_fact_value_and_cleared_customer_route(self):
        source = self.text('Tests/AppUITests/ClubGovernanceFlowTests.swift')
        self.assertIn('identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)', source)
        for fragment in ['fact("title", containing: "Fixture chapter"',
                         'fact("title", containing: "Fixture puzzle"',
                         'fact("displayName", containing: "Fixture customer"',
                         'XCTAssertFalse(customer.exists)',
                         'XCTAssertFalse(app.buttons["club.gov.route.customer"].exists)',
                         'XCTAssertFalse(app.staticTexts["¥0"].exists)']:
            self.assertIn(fragment, source)


if __name__ == '__main__':
    unittest.main()
