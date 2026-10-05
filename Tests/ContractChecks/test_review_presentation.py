"""Offline presentation guards only; not Swift compilation or measured native contrast."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ReviewPresentationTests(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_waitlist_guidance_is_capability_status_and_deadline_aware(self):
        source = self.read('Core/RegistrationUIForm.swift').split('public enum RegistrationUIWaitlistGuidance')[1]
        for token in ['guard available else { return "registration.form.soldOutHint" }', 'guard !outcomeUnknown', 'status?.state == .waiting', 'status?.offer(at: now)']:
            self.assertIn(token, source)
        view = self.read('App/RegistrationSheetView.swift')
        ticket = view.split('private var ticketSection:')[1].split('private var waitlistSection:')[0]
        for token in ['TimelineView', 'available: flow.waitlistAvailable', 'status: flow.waitlistStatus', 'now: context.date']:
            self.assertIn(token, ticket)
        self.assertIn('.disabled(flow.confirmationBlock != nil)', view)
        self.assertIn('testUnreviewedOfferGuidanceExpiresWhileFormRemainsOpen', self.read('Tests/AppUITests/RegistrationWaitlistUITests.swift'))
    def test_expiry_fixture_is_armed_only_after_the_offered_ui_is_observed(self):
        fixture = self.read('App/RegistrationFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('scenario == .waitlistExpiringOffer ? Date.distantFuture', fixture)
        arm = fixture.split('func armOfferExpiry() {')[1].split('func quote(')[0]
        self.assertIn('guard scenario == .waitlistExpiringOffer', arm)
        self.assertIn('Date().addingTimeInterval(20)', arm)
        self.assertIn('await expiryFlow.loadWaitlist()', fixture)
        self.assertNotIn('now:', fixture)
        view = self.read('App/RegistrationSheetView.swift')
        injected = view.split('init(fixtureFlow: RegistrationUIFlow)')[0].rsplit('#if DEBUG', 1)[1]
        self.assertIn('fixture-only injection', injected)
        tests = self.read('Tests/AppUITests/RegistrationWaitlistUITests.swift').split('func testUnreviewedOfferGuidanceExpiresWhileFormRemainsOpen()')[1]
        self.assertLess(tests.index('wait(for: [offeredExpectation]'), tests.index('arm.tap()'))
        self.assertLess(tests.index('arm.tap()'), tests.index('wait(for: [expiredExpectation]'))
        self.assertIn('timeout: 25', tests)
    def test_review_snapshot_keeps_every_source_binding_and_stays_local(self):
        source = self.read('Core/CooperationFlowContracts.swift')
        review = source.split('public struct CoopFlowRequestReviewContext:')[1].split('public struct CoopFlowPerkTemplate:')[0]
        for token in ['let body = try operation.body()', 'context.session == currentSession',
                      'invitation.recipient == context.recipient', 'invitation.kind == context.kind',
                      'invitation.topicID == context.topicID', 'invitation.originApplyID == context.originApplyID',
                      'invitation.scope == context.scope', 'self.operation = operation; self.requestBody = body',
                      '.recipient(name: name, identity: invitation.recipient)', '"coopflow.review.unknownValue"']:
            self.assertIn(token, review)
        for forbidden in ['URLSession', 'execute(', 'fingerprint', 'grant', 'UUID()']:
            self.assertNotIn(forbidden, review)
        view = self.read('App/CooperationFlowEditors.swift').split('struct CoopFlowTemplateEditor')[0]
        for token in ['ForEach(review.rows)', 'String(identity.id)', 'identity.domain.rawValue', 'String.LocalizationValue(stringLiteral:', 'Button("coopflow.submit") {}.disabled(true)']:
            self.assertIn(token, view)
        self.assertNotIn('fields.keys.sorted()', view)
    def test_essential_amounts_use_explicit_adaptive_color_without_changing_signs(self):
        source = self.read('App/RegistrationSheetView.swift')
        row = source.split('private struct RegistrationAmountRow: View')[1].split('private struct RegistrationIssueText:')[0]
        for token in ['Text(verbatim: deduction && amount != .zero ? "−\\(text)" : text)',
                      '.foregroundStyle(Color.primary).accessibilityIdentifier(key + ".amount")',
                      'RegistrationUIMoney.display(amount, locale: locale, currencyCode: currencyCode)', 'if currencyCode == nil']:
            self.assertIn(token, row)
        self.assertNotIn('Color(red:', row)
        self.assertIn('testEssentialQuoteAmountCaptureInLightAndDarkBothLanguages', self.read('Tests/AppUITests/RegistrationWaitlistUITests.swift'))
    def test_review_and_waitlist_copy_is_bilingual(self):
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        keys = ['registration.form.soldOutHint', 'registration.form.soldOutAvailable',
                'registration.form.soldOutWaiting', 'registration.form.soldOutOffer',
                'coopflow.review.scope.merchant', 'coopflow.review.traffic', 'coopflow.review.perk',
                'coopflow.review.revshare', 'coopflow.review.unknownValue',
                'coopflow.review.identity.club', 'coopflow.review.identity.member']
        for key in keys:
            self.assertEqual(set(catalog[key]['localizations']), {'en', 'zh-Hans'})
            for value in catalog[key]['localizations'].values(): self.assertTrue(value['stringUnit']['value'].strip())
        self.assertNotIn('not available', catalog['registration.form.soldOutWaiting']['localizations']['en']['stringUnit']['value'])
        self.assertNotIn('尚未接入', catalog['registration.form.soldOutOffer']['localizations']['zh-Hans']['stringUnit']['value'])
if __name__ == '__main__': unittest.main()
