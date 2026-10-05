"""Native-source checks only. They neither execute Swift nor prove Apple/runtime behavior."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class InstalledDraftReceiptContracts(unittest.TestCase):
    def source(self, path): return (ROOT / path).read_text()
    def test_closed_historical_wire_statuses_and_all_false_capabilities(self):
        source = self.source('Core/InstalledDraftReceipts.swift')
        for raw in ['HISTORICAL_RECEIPTS_ONLY', 'NOT_ENABLED', 'OWNER_ONLY', 'EXACT_REVISION',
                    'STALE_BINDING', 'BINDING_UNVERIFIABLE', 'HISTORICAL_INSTALLATION', 'POST_INSTALL_POLICY_UNAVAILABLE']:
            self.assertIn(f'"{raw}"', source)
        for flag in ['textPreviewAllowed', 'editingAllowed', 'exportAllowed', 'publicationAllowed', 'executionAllowed', 'commercialUseAllowed']:
            self.assertIn('.' + flag, source)
        self.assertIn('box.decode(Bool.self, forKey: flag) == false', source)
        self.assertNotIn('case allowed', source)
    def test_bounded_decode_and_identity_consistency(self):
        source = self.source('Core/InstalledDraftReceipts.swift')
        for boundary in ['decoded.count < 50', 'seen.insert(receipt.installationId).inserted',
                         '!hasMore || decoded.count == 50', 'versionId.utf16.count <= 512',
                         'installedAt.utf8.count <= 40', 'value.utf8.count == 64',
                         'receipt.targetDraftId == record.id', 'receipt.installedTargetVersion == record.version',
                         'receipt.installedTargetPayloadHash == record.payloadHash']:
            self.assertIn(boundary, source)
        self.assertIn('case .exact: return exact', source)
        self.assertIn('case .stale: return !exact', source)
        self.assertIn('case .unverifiable: return receipt.installedTargetPayloadHash == nil', source)
    def test_omission_and_invalid_are_explicit_and_unknown_fields_are_not_stored(self):
        contracts = self.source('Core/VersionedContentDraftContracts.swift')
        self.assertIn('installedModulesInvalid = box.contains(.installedModules) && installedModules == nil', contracts)
        source = self.source('Core/InstalledDraftReceipts.swift')
        self.assertIn('record.installedModulesInvalid ? .invalid : .omitted', source)
        projection = source.split('public struct OwnerDraftInstalledReceipts:', 1)[1]
        for term in ['payloadJson', 'versionId:', 'termsHash', 'contentHash', 'rightsJson', '[String: Any]']:
            self.assertNotIn(term, projection)
        self.assertIn('enum Availability: String, Decodable', source)
        self.assertIn('enum Binding: String, Decodable', source)
    def test_metadata_is_not_encoded_in_immutable_journal_material(self):
        contracts = self.source('Core/VersionedContentDraftContracts.swift')
        record = contracts.split('public struct ContentDraftRecord:', 1)[1].split('public struct ContentDraftDocument<', 1)[0]
        encoding = record.split('public func encode(to encoder:', 1)[1].split('public static func ==', 1)[0]
        self.assertNotIn('forKey: .installedModules', encoding)
        self.assertNotIn('installedModulesInvalid', encoding)
        equality = record.split('public static func ==', 1)[1].split('public func validate', 1)[0]
        self.assertNotIn('installedModules', equality)
        self.assertIn('public struct InstalledDraftModules: Decodable, Equatable', self.source('Core/InstalledDraftReceipts.swift'))
        self.assertIn('func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) async throws', contracts)
        self.assertIn('func mutate(_ attempt: ContentDraftPreparedDispatch)', contracts)
    def test_only_fresh_validated_restore_projects_receipts(self):
        source = self.source('Core/OwnerDraftBrowser.swift')
        self.assertIn('includeReceipts: Bool = false', source)
        self.assertIn('includeReceipts ? OwnerDraftInstalledReceipts(record: record) : nil', source)
        self.assertEqual(source.count('includeReceipts: true'), 1)
        restore = source.split('public func restore(id:', 1)[1].split('public func closeList()', 1)[0]
        self.assertLess(restore.index('try record.validate(identity: row.identity)'), restore.index('includeReceipts: true'))
        self.assertIn('guard !Task.isCancelled else { closeDetail(); return }', restore)
        self.assertIn('detailGeneration == ticket', restore)
        self.assertIn('if route == nil { browser.closeList() }', self.source('App/OwnerDraftBrowserView.swift'))
    def test_receipt_view_has_no_content_actions_or_raw_fields(self):
        source = self.source('App/OwnerDraftBrowserView.swift').split('struct OwnerDraftReceiptSummaryView:', 1)[1]
        for term in ['Button(', 'NavigationLink', 'TextEditor(', 'payloadJson', 'versionId', 'termsHash', 'contentHash', '.mutate(', 'URL(']:
            self.assertNotIn(term, source)
        self.assertIn('summary.hasMore', source)
        self.assertIn('Text(verbatim: row.installedTime)', source)
        self.assertNotIn('.lineLimit(1)', source); self.assertNotIn('height:', source)
    def test_receipt_copy_is_bilingual_including_dynamic_states(self):
        strings = json.loads(self.source('Resources/Localizable.xcstrings'))['strings']
        for key, value in strings.items():
            if key.startswith('ownerDraft.receipts.'):
                self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'}, key)
        for state in ['omitted', 'invalid', 'notEnabled', 'ownerOnly', 'historical']:
            self.assertIn('ownerDraft.receipts.state.' + state, strings)
    def test_every_composition_sign_in_supplies_the_required_recorder(self):
        source = self.source('Tests/AppUnitTests/OwnerDraftCompositionTests.swift')
        self.assertIn('recorder: OwnerDraftFixtureTransport', source)
        calls = re.findall(r'await signIn\(([^)]*)\)', source)
        self.assertGreaterEqual(len(calls), 4)
        for arguments in calls:
            self.assertRegex(arguments, r'\brecorder\s*:', arguments)

    def test_independent_adversarial_probes_are_retained(self):
        source = self.source('Tests/CoreTests/InstalledDraftReceiptReviewTests.swift')
        for test in ['testUnavailableStatesCannotHideCapabilityOrBindingEscalation',
                     'testMalformedTailInvalidatesWholeHistoryRatherThanKeepingTrustedPrefix',
                     'testReceiptNumericBooleansStringsAndOverflowDoNotBecomeIdentities',
                     'testVersionLimitIsUTF16AndFiftyDoesNotRequireHasMore',
                     'testFrozenSynthesizedLegacyEncodingMatchesRecordAndWholeMutationBytes',
                     'testNestedUnknownDataNeverEntersProjectionJournalOrRecordDescription',
                     'testDuplicateKnownAndUnknownReceiptKeysRejectWholeHTTPEnvelope',
                     'testReceiptMetadataCannotMaskForeignOwnerOrRegressingDraft',
                     'testListBackReopenAndNewRestoreRetireBothLateSuccessAndLateFailure']:
            self.assertIn('func ' + test, source)
        app = self.source('Tests/AppUnitTests/OwnerDraftCompositionTests.swift')
        for test in ['testLateReceiptAfterLogoutAndSameAccountReloginCannotReachNewSession',
                     'testRootLifetimeReplacementKeepsFreshReceiptStateAfterLateOldRestore']:
            self.assertIn('func ' + test, app)

    def test_synthetic_lifecycle_and_journal_regressions_are_authored(self):
        source = self.source('Tests/CoreTests/InstalledDraftReceiptTests.swift')
        for test in ['testMetadataDoesNotChangeLegacyRecordEncodingEqualityPayloadOrMutation',
                     'testAsyncDurableJournalReopensAndCASRetainsCallerHeldReceiptFreeSnapshot',
                     'testBackCancelAndInvalidationSuppressLateReceipts',
                     'testNewerRestoreCannotBeOverwrittenByRetiredReceiptResponse']:
            self.assertIn('func ' + test, source)
        fixture = self.source('App/OwnerDraftFixtureHost.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('pendingRestoreResponse = response', fixture)
        self.assertNotIn('URLSession', fixture.split('final class OwnerDraftFixtureTransport', 1)[1])
        self.assertGreaterEqual(len(re.findall('func test', source)), 15)

if __name__ == '__main__': unittest.main()
