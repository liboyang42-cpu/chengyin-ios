"""Supplementary static checks only; Swift/Apple execution is a separate gate."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class MerchantProfileBenefitsTests(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()
    def test_field_is_distinct_optional_and_bounded(self):
        source = self.read('Core/MerchantOperationsContracts.swift')
        self.assertIn('public var derivativeBenefits: String?', source)
        self.assertIn('decodeIfPresent(String.self, forKey: .derivativeBenefits)', source)
        self.assertIn('if let derivativeBenefits { fields["derivativeBenefits"] = derivativeBenefits }', source)
        self.assertIn('(derivativeBenefits?.utf16.count ?? 0) > 100', source)
        draft = self.read('Core/MerchantOperationsDraft.swift')
        self.assertIn('case .profile(let value): return value.benefitsBlocker', draft)
        self.assertIn('.init("derivativeBenefits", v.derivativeBenefits ?? "")', draft)
        self.assertIn('fields: value.profile.legacyFields', draft)
    def test_normal_editor_and_frozen_review_are_connected(self):
        editor = self.read('App/MerchantOperationsEditor.swift')
        self.assertIn('merchant.operations.field.derivativeBenefits', editor)
        self.assertIn('current.derivativeBenefits = text; model.edit(.profile(current))', editor)
        self.assertIn('confirmation.draft.reviewLines', editor)
        self.assertIn('.profile', self.read('App/MerchantOperationsViews.swift'))
    def test_acknowledged_profile_readback_is_separate_from_write_failure(self):
        source = self.read('Core/MerchantOperationsReading.swift')
        ack = source.split('try await reader.saveReviewed(value.draft, baseline: value.baseline)', 1)[1]
        self.assertIn('if destination == .profile', ack)
        self.assertIn('document = nil; baseline = nil; draft = nil', ack)
        self.assertIn('let current = try await reader.document(destination)', ack)
        self.assertIn('operation == generation, reader.scope == value.scope, reader.isAuthenticated', ack)
        self.assertIn('profileReadbackFailed', ack)
        self.assertIn('isLocked ? .key("merchant.operations.unknownOutcome")', ack)
    def test_role_fence_preserves_journal_and_auth_epoch(self):
        source = self.read('Core/MerchantOperationsReading.swift')
        self.assertIn('viewerRevision: UInt64 = 0', source)
        self.assertIn('self.viewerRevision = viewerRevision', source)
        owner = source.split('public var ownerKey:', 1)[1].split('\n', 1)[0]
        self.assertNotIn('viewerRevision', owner)
        app = self.read('App/AppSession.swift')
        scope = app.split('private var currentMerchantOperationsSession:', 1)[1].split('lazy var merchantOperationsReader', 1)[0]
        self.assertIn('viewerRevision: compositionViewerRevision', scope)
        self.assertIn('epoch: gate.currentStamp', scope)
    def test_catalogs_agree(self):
        fragment = json.loads(self.read('docs/merchant-operations-localizations.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for suffix in ['derivativeBenefits','benefitsHint','benefitsLimit','profileReadback','profileReadbackFailed']:
            key = 'merchant.operations.' + suffix
            for language, value in fragment[key].items():
                self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], value)
    def test_authored_negative_cases_remain_present(self):
        tests = self.read('Tests/CoreTests/MerchantOperationsTests.swift')
        for name in ['testMissingAndNullAreOmittedButExplicitEmptyClears', 'testBenefitsUseServerUTF16BoundaryWithoutTruncation', 'testAcknowledgedReadbackFailureHidesUnverifiedValuesAndRetryOnlyReads', 'testScopeChangeDuringReadbackCannotRestoreOldProfile', 'testUnknownWriteRemainsLockedAndDoesNotReadBackAsAcknowledged', 'testRoleRevisionAndABAChangeScopeWithoutChangingJournalOwner']:
            self.assertIn(name, tests)
if __name__ == '__main__': unittest.main()
