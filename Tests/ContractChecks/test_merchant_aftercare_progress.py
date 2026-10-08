"""Source/structural checks only; not Swift execution or iOS UI acceptance."""
import json
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantAftercareProgressContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_real_refund_document_is_validated_and_renders_inside_current_snapshot(self):
        document = self.read('Core/MerchantBusinessDocuments.swift')
        self.assertIn('_ = try MerchantAftercareProgress(refundID: id.rawValue, fields: object)', document)
        self.assertIn('guard case .refund(let id) = query, let fields = payload.object else { return nil }', document)
        app = self.read('App/MerchantBusinessViews.swift')
        snapshot = app.index('if let snapshot = state.snapshot, state.isCurrent')
        rendered = app.index('MerchantAftercareProgressView(progress: progress)', snapshot)
        self.assertLess(snapshot, rendered)
        self.assertIn('Section { rowActions(refund, access: snapshot.access) }', app)
        self.assertIn('.onDisappear { editor = nil; pendingMutation = nil; model.invalidate() }', app)
        self.assertIn('.onChange(of: reader.authorizationGeneration)', app)
        self.assertIn('authorization == coordinator.reader.authorizationGeneration', app)
        self.assertIn('return try .init(query: query, payload: Self.unwrap(body))', self.read('Core/MerchantBusinessService.swift'))

    def test_platform_opinion_and_money_are_separate(self):
        core = self.read('Core/MerchantAftercareProgress.swift')
        self.assertIn('funds: Funds { processing == .refunded ? .confirmed : .unconfirmed }', core)
        for code in ['WAITING_PLATFORM_REVIEW', 'PLATFORM_REJECTED', 'REFUND_PROCESSING',
                     'MANUAL_REFUND_PENDING', 'MANUAL_REFUND_REVIEW', 'REFUNDED', 'UNKNOWN']:
            self.assertIn('"' + code + '"', core)
        view = self.read('App/MerchantAftercareProgressView.swift')
        for key in ['platform', 'opinion', 'funds']:
            self.assertIn('accessibilityIdentifier("merchant.aftercareProgress.' + key + '")', view)
        self.assertIn('if progress.amount.raw != nil', view)
        self.assertIn('Text("merchant.aftercareProgress.amountUnknown")', view)
        self.assertIn('Text("merchant.business.opinionOnly")', view)

    def test_history_has_only_recorded_events_and_no_effects(self):
        core = self.read('Core/MerchantAftercareProgress.swift')
        self.assertIn('platformTakeoverAt = try Self.timestamp(fields, "platformTakeoverAt")', core)
        self.assertIn('seen.insert(id).inserted', core)
        self.assertIn('row.mbInt("refundId", minimum: 1) == refundID', core)
        for forbidden in ['Date()', 'timeIntervalSinceNow', 'URLSession', 'execute(', 'reserve(', 'UserDefaults', 'FileManager']:
            self.assertNotIn(forbidden, core)
        view = self.read('App/MerchantAftercareProgressView.swift')
        for forbidden in ['AsyncImage', 'URLSession', 'evidenceUrl', 'Button(', 'NavigationLink', '.task']:
            self.assertNotIn(forbidden, view)
        self.assertIn('ForEach(progress.events)', view)
        self.assertIn('MerchantAftercareTime.event(time, phoneTimeZone: phoneTimeZone)', view)
        self.assertIn('MerchantAftercareTime.deadline(deadline)', view)
        self.assertIn('.NSSystemTimeZoneDidChange', view)

    def test_every_new_literal_and_dynamic_key_is_bilingual(self):
        fragment = json.loads(self.read('Resources/MerchantAftercareProgressLocalizations.fragment.json'))
        source = self.read('App/MerchantAftercareProgressView.swift') + self.read('Core/MerchantAftercareProgress.swift')
        literals = set(re.findall(r'"(merchant\.aftercareProgress\.[A-Za-z]+)"', source))
        for key in literals:
            self.assertIn(key, fragment)
        for suffix in ['opinion.PENDING', 'opinion.AGREE', 'opinion.REJECT', 'funds.confirmed', 'funds.unconfirmed',
                       'decision.AGREE', 'decision.REJECT', 'decision.EVIDENCE', 'evidence.recorded', 'evidence.unavailable',
                       'actor.MERCHANT_OWNER', 'actor.MERCHANT_MANAGER', 'actor.MERCHANT_CHECKIN',
                       'actor.MERCHANT_MARKETING', 'actor.MERCHANT_FINANCE', 'actor.unknown']:
            self.assertIn('merchant.aftercareProgress.' + suffix, fragment)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][locale]['stringUnit']['value'].strip())

    def test_authored_behavior_covers_failure_repetition_and_interruption(self):
        tests = self.read('Tests/CoreTests/MerchantAftercareProgressTests.swift')
        for case in ['testSevenPlatformStatesKeepEveryMerchantOpinionIndependent',
                     'testMissingAmountRemainsUnknownAndNegativeAmountIsRejected',
                     'testDuplicateOrCrossRefundResponseIsRejectedByRealDocumentBoundary',
                     'testReadTransportPreservesTakeoverAndResponseFacts',
                     'testDismissedDetailCannotBeRestoredByLateResponse',
                     'testRepeatedRefreshKeepsNewerResultWhenOldResponseArrivesLast',
                     'testAccountChangeOrCancellationCannotDisplayOldProgress']:
            self.assertIn('func ' + case, tests)

if __name__ == '__main__':
    unittest.main()
