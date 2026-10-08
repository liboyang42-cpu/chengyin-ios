"""Supplementary source checks; no Swift compilation or real clipboard execution."""
import json
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantSettlementProgressContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_existing_batch_reader_and_authorization_are_reused(self):
        app = self.read('App/MerchantSettlementProgressView.swift')
        self.assertIn('reader.snapshot(.batch(.init(displayed.batchID)))', app)
        self.assertIn('snapshot.access.allows("merchant:finance:read")', app)
        query = self.read('Core/MerchantBusinessQuery.swift')
        self.assertIn('.json("api/merchant/finance/public-transfer-batch-detail", ["batchId": .int(id.rawValue)])', query)
        reader = self.read('Core/MerchantBusinessReading.swift')
        self.assertIn('let access = try await service.access(token: session.token)', reader)
        self.assertIn('service.document(query, access: access, token: session.token)', reader)

    def test_paid_requires_all_server_facts_and_timestamp_cannot_advance_pending(self):
        core = self.read('Core/MerchantSettlementProgress.swift')
        self.assertIn('netDirection == "PLATFORM_PAYS_MERCHANT" && paymentState == "PAID"', core)
        self.assertIn('!hasLedgerError && positiveAmount && paidAt != nil && voucher != nil', core)
        self.assertIn('public var voucherForCopy: String? { isPaid ? voucher : nil }', core)
        self.assertIn('id == "paid" && isPaid ? paidAt : nil', core)
        self.assertNotIn('createdAt', core)
        self.assertNotIn('confirmedAt', core)
        self.assertNotIn('Date()', core)

    def test_zero_owed_invoice_and_hold_are_independent(self):
        core = self.read('Core/MerchantSettlementProgress.swift')
        for code in ['ZERO', 'MERCHANT_OWES_PLATFORM', 'PLATFORM_PAYS_MERCHANT', 'LEDGER_ERROR', 'FROZEN', 'CONFIRMED']:
            self.assertIn('"' + code + '"', core)
        self.assertIn('guard netDirection == "PLATFORM_PAYS_MERCHANT", !hasLedgerError', core)
        self.assertIn('switch invoiceState', core)
        self.assertIn('holdState == "FROZEN" ? .paused : .current', core)
        self.assertIn('strictString: true', core)

    def test_current_detail_only_and_existing_fields_are_retained(self):
        row = self.read('App/MerchantBusinessRecordViews.swift')
        self.assertIn('if row.kind == .batch, !compact, access.allows("merchant:finance:read")', row)
        self.assertIn('let progress = try? MerchantSettlementProgress(record: row)', row)
        self.assertIn('ForEach(keys, id: \\.self)', row)
        self.assertIn('"paidAt", "payVoucherNo"', row)
        page = self.read('App/MerchantBusinessViews.swift')
        self.assertIn('guard state.isCurrent, !state.isBusy, state.failureKey == nil else { return nil }', page)
        self.assertIn('MerchantAftercareProgressView(progress: progress)', page)

    def test_copy_guards_before_and_after_read_and_write_has_no_await_gap(self):
        app = self.read('App/MerchantSettlementProgressView.swift')
        initial, after = app.split('let latest = try await reader.snapshot', 1)
        for token in ['intent == intentID', '!busy', '!Task.isCancelled', 'let scope = reader.scope',
                      'reader.isConfigured', 'let baseline = currentSnapshot()', 'Self.matches(baseline, displayed: displayed)']:
            self.assertIn(token, initial)
        for token in ['intentID == ticket', '!Task.isCancelled', 'reader.isConfigured', 'reader.scope == scope',
                      'reader.authorizationGeneration == authorization', 'currentSnapshot() == baseline',
                      'latest.access == baseline.access', 'Self.matches(latest, displayed: displayed)']:
            self.assertLess(after.index(token), after.index('write(voucher)'))
        write_guard = after.split('guard intentID == ticket', 1)[1].split('write(voucher)', 1)[0]
        self.assertNotRegex(re.sub(r'//[^\n]*', '', write_guard), r'\bawait\s+\w')
        self.assertIn('id.rawValue == displayed.batchID', app)
        self.assertIn('return value == displayed', app)

    def test_copy_is_only_click_local_expiring_and_appearance_scoped(self):
        app = self.read('App/MerchantSettlementProgressView.swift')
        self.assertEqual(app.count('UIPasteboard.general.setItems'), 1)
        self.assertIn('.localOnly: true', app)
        self.assertIn('.expirationDate: Date().addingTimeInterval(120)', app)
        self.assertIn('let displayedIntent = copyModel.intentID', app)
        self.assertIn('intent: displayedIntent', app)
        self.assertIn('.onDisappear { copyModel.invalidate() }', app)
        for property in ['progress', 'reader.scope', 'reader.authorizationGeneration', 'scenePhase']:
            self.assertIn('.onChange(of: ' + property + ')', app)
        for forbidden in ['UserDefaults', 'FileManager', 'print(', 'Logger', 'URLSession', '.task(', 'execute(', 'reserve(']:
            self.assertNotIn(forbidden, app)

    def test_bilingual_keys_and_accessibility(self):
        fragment = json.loads(self.read('Resources/MerchantSettlementProgressLocalizations.fragment.json'))
        source = self.read('App/MerchantSettlementProgressView.swift') + self.read('Core/MerchantSettlementProgress.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', source)
        for key in set(re.findall(r'"(merchant\.settlementProgress\.[A-Za-z.]+)"', source)):
            if key.endswith('.'): continue
            self.assertIn(key, fragment)
        for suffix in ['step.created', 'step.confirmed', 'step.paid', 'stepState.done', 'stepState.current', 'stepState.pending', 'stepState.paused']:
            self.assertIn('merchant.settlementProgress.' + suffix, fragment)
        for value in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'].strip())
        app = self.read('App/MerchantSettlementProgressView.swift')
        self.assertIn('.frame(minHeight: 44)', app)
        self.assertIn('.accessibilityElement(children: .combine)', app)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', app)

    def test_payment_time_uses_existing_parsers_and_live_phone_zone_on_both_surfaces(self):
        core = self.read('Core/MerchantSettlementProgress.swift')
        app = self.read('App/MerchantSettlementProgressView.swift')
        rows = self.read('App/MerchantBusinessRecordViews.swift')
        self.assertIn('public static func paymentTimestamp(_ raw: String?) -> Date?', core)
        self.assertIn('try? MerchantAftercareTime.parse(text)', core)
        self.assertIn('return OrderLifecycleTime.date(text)', core)
        self.assertIn('MerchantAftercareTime.parse(String(text.prefix(19))', core)
        self.assertIn('MerchantSettlementTimestampText(raw: time)', app)
        self.assertNotIn('Text(verbatim: time)', app)
        self.assertIn('MerchantAftercareTime.event(date, phoneTimeZone: phoneTimeZone)', app)
        self.assertIn('@State private var phoneTimeZone = TimeZone.current', app)
        self.assertIn('.onAppear { phoneTimeZone = .current }', app)
        self.assertIn('.NSSystemTimeZoneDidChange', app)
        self.assertIn('if row.kind == .batch, key == "paidAt"', rows)
        self.assertIn('MerchantSettlementTimestampText(raw: value.string)', rows)
        self.assertNotIn('MerchantAftercareTime.deadline', app)
        self.assertNotIn('TimeZone(secondsFromGMT:', app)
        tests = self.read('Tests/CoreTests/MerchantSettlementProgressTests.swift')
        for method in ['testShanghaiBareAndJacksonISOResolveTheSamePaymentInstant',
                       'testPaymentDisplayCrossesDayAndFollowsChangedPhoneTimeZone',
                       'testPaymentDisplayPreservesDSTGapAndRepeatedHourOffsets',
                       'testMissingMalformedAndOffsetlessISOTimesNeverInventDates',
                       'testTimePresentationNeverChangesPaidPendingFactsOrCopyAuthorization']:
            self.assertIn('func ' + method, tests)

    def test_authored_tests_cover_interruptions_and_real_read_shape(self):
        core = self.read('Tests/CoreTests/MerchantSettlementProgressTests.swift')
        app = self.read('Tests/AppUnitTests/MerchantSettlementProgressTests.swift')
        for method in ['testThreePaymentStatesHaveStateDrivenProgress', 'testLedgerErrorBlocksProgressAndCopyDespitePaidArtifacts',
                       'testZeroAndOwedAmountsHaveNoPlatformPayoutTimeline', 'testFreshReadUsesExistingOwnedBatchRouteAndNoMerchantOverride']:
            self.assertIn('func ' + method, core)
        for method in ['testExplicitClickFreshReadsThenCopiesExactlyTheVoucher', 'testLogoutAccountAuthorizationAndConfigurationChangesBlockLateRead',
                       'testDismissAndReopenRejectsOldQueuedIntentBeforeRead', 'testRepeatedTapStartsOneReadAndOneClipboardWrite',
                       'testCancelledCopyNeverTouchesClipboard', 'testLateOldReadCannotResetNewAttemptOrCopy',
                       'testNewMerchantGrantBatchVoucherAndPaymentInvalidateFreshRead']:
            self.assertIn('func ' + method, app)
        self.assertNotIn('UIPasteboard', app)
        self.assertIn('URL(string: "https://example.test")!', core)
        self.assertNotIn('example.invalid', core)

if __name__ == '__main__': unittest.main()
