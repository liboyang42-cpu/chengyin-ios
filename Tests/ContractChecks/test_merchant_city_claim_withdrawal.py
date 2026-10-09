"""Narrow source/identity wiring checks. Swift runtime tests remain separately unrun."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantCityClaimWithdrawalContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_identity_mapping_is_scoped_and_conflicts_fail_closed(self):
        source = self.read('Core/MerchantCityClaimWithdrawal.swift')
        for token in ['snapshot.query == .city', 'snapshot.access.allows(.projects)',
                      'let merchantID = snapshot.access.merchantID, merchantID > 0',
                      'let poiID = row["id"].safeInteger, poiID > 0',
                      'row["applicationType"].safeInteger == 2', 'row["auditStatus"].safeInteger == 0',
                      'row["poiId"] == .null || row["poiId"].safeInteger == poiID',
                      'row["merchantId"] == .null',
                      'row["applicantMerchantId"].safeInteger == merchantID',
                      'rows.filter({ $0["id"].integer == poiID || $0["poiId"].integer == poiID }).count == 1',
                      'rows.contains(row)']:
            self.assertIn(token, source)
        self.assertNotIn('row["status"]', source)

    def test_row_and_command_both_use_verified_target(self):
        view = self.read('App/MerchantContentViews.swift')
        block = view.split('let target = MerchantCityClaimWithdrawal(row: row, snapshot: snapshot)', 1)[1].split('case .query', 1)[0]
        for token in ['model.coordinator.isCurrent', 'model.coordinator.snapshot == snapshot',
                      'model.coordinator.snapshot?.observedAt == snapshot.observedAt',
                      'model.prepare(.cancelClaim(poiID: target.poiID))',
                      'model.coordinator.busy || model.coordinator.locked || model.coordinator.review != nil']:
            self.assertIn(token, block)
        command = self.read('Core/MerchantContentCommands.swift')
        self.assertIn('try need(MerchantCityClaimWithdrawal(poiID: id, snapshot: snapshot) != nil)', command)
        self.assertIn('return form("api/merchant/city-node/claim/cancel", ["poiId": String(id)])', command)

    def test_review_uses_frozen_target_and_keeps_existing_cancel(self):
        source = self.read('App/MerchantContentViews.swift')
        self.assertIn('MerchantCityClaimWithdrawal(poiID: poiID, snapshot: review.baseline)', source)
        self.assertIn('Button("action.cancel") { model.cancel(); dismiss() }', source)
        self.assertIn('!model.coordinator.service.permitsWrites', source)
        self.assertIn('merchant.cityClaim.withdrawConsequence', source)

    def test_source_correction_has_explicit_negative_and_coordinator_cases(self):
        tests = self.read('Tests/CoreTests/MerchantCityClaimWithdrawalTests.swift')
        for method in ['testMatchingExplicitPOIIDIsAcceptedButConflictAndAliasOnlyAreRejected',
                       'testDuplicateAndConflictingAliasRowsCannotSelectOneTarget',
                       'testOnlyCurrentAuthorizedCityApplicationRowsCanBeUsed',
                       'testNonClaimNonPendingAndVisibilityStatusDoNotAuthorizeWithdrawal',
                       'testCancellingReviewDispatchesNothingEvenWithZeroQuota',
                       'testChangedReviewStatusStopsConfirmationBeforeDispatch',
                       'testReloadInvalidatesOldReviewAndResolvedApplicationCannotBeReused']:
            self.assertIn('func ' + method, tests)
        self.assertIn('XCTAssertNil(MerchantCityClaimWithdrawal', tests)
        old = self.read('Tests/CoreTests/MerchantContentContractTests.swift')
        self.assertIn('testClaimCancellationUsesRoamPOIIDOnlyFromScopedCityApplications', old)
        self.assertIn('validate(against: conflict)', old)

    def test_existing_ui_case_is_updated_without_adding_methods(self):
        source = self.read('Tests/AppUITests/MerchantContentFlowTests.swift')
        self.assertEqual(source.count('    func test'), 7)
        self.assertIn('testCityClaimWithdrawalReviewUsesSourcePOIAndCanCancel', source)
        self.assertNotIn('testCityClaimDoesNotTreatApplicationIDAsPOIID', source)
        self.assertIn('tap("merchant.content.review.cancel", in: app)', source)
        fragment = json.loads(self.read('Resources/MerchantCityClaimWithdrawalLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 2)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
