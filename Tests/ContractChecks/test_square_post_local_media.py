"""Source-only boundaries. Authored Swift XCTest remains separate and NOT_RUN here."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SquarePostLocalMediaSourceTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def contracts(self):
        return self.read('Core/SquarePostLocalMediaContracts.swift')

    def selection(self):
        return self.read('Core/SquarePostLocalMediaSelection.swift')

    def test_scope_is_only_square_local_and_has_no_network_or_shared_grant(self):
        source = self.contracts() + self.selection()
        for forbidden in ['URLSession', 'URLRequest', 'URL(string:', 'api/', 'SquareWorkspaceService',
                          'SquareWorkspaceGrants', 'ClubCommunity', 'ProjectTopic', 'AVPlayer',
                          'PhotosPicker', 'PHPicker', 'CLLocation', 'FileManager', 'UserDefaults',
                          'uploadReceipt', 'canPublish', 'canUpload']:
            self.assertNotIn(forbidden, source)
        for required in ['SquareWorkspaceSession', 'draftID: String', 'SquareWorkspaceLane']:
            self.assertIn(required, source)

    def test_actual_chunks_are_counted_and_hashed_before_non_public_evidence_mint(self):
        source = self.contracts()
        for required in ['hasher.update(data: ownedChunk)', 'hasher.finalize()',
                         'description.reportedByteCount == lifecycle.count', 'description.reference == token.reference',
                         'description.kind == token.kind', 'guard lifecycle.count > 0',
                         'fileprivate init(token: SquarePostLocalMediaInspectionToken',
                         'appDecodingPerformed: Bool { false }']:
            self.assertIn(required, source)
        self.assertNotIn('public init(token:', source)
        self.assertIn('if let failure = lifecycle.failure { throw failure }', source)
        self.assertIn('failure = .byteLimit; throw', source)
        self.assertIn('private final class Lifecycle', source)
        self.assertIn('private let lifecycle = Lifecycle()', source)
        self.assertEqual(source.count('lifecycle.lock.lock(); defer { lifecycle.lock.unlock() }'), 2)
        self.assertIn('lifecycle.finished = true', source)

    def test_policy_has_no_product_defaults_and_success_still_requires_app_decode(self):
        source = self.contracts() + self.selection()
        for name in ['maximumItems', 'maximumImages', 'maximumVideos', 'allowsMixed',
                     'maximumImageBytes', 'maximumVideoBytes', 'maximumTotalBytes',
                     'maximumVideoDurationMilliseconds']:
            self.assertIn(name, source)
            self.assertNotRegex(source, rf'{name}:\s*(?:Int64|Int|Bool)\?\s*=')
        self.assertIn('guard let policy else { return .policyUnavailable }', source)
        self.assertIn('metadataWithinPolicyAwaitingAppDecode', source)
        self.assertIn('addingReportingOverflow', source)

    def test_completions_are_bound_to_owner_lease_scope_item_version_and_attempt(self):
        source = self.selection()
        for token in ['token.owner == owner', 'token.lease == lease', 'token.scope == scope',
                      '$0.id == token.selectionID', 'items[index].reference == token.reference',
                      'items[index].kind == token.kind', 'current == token']:
            self.assertIn(token, source)
        self.assertIn('items[index].phase = .selected', source)
        self.assertIn('lease = UUID()', source)
        self.assertIn('revision = UUID()', source)
        self.assertIn('previous != identity', source)
        self.assertIn('.failed(.sourceBytesChanged)', source)
        self.assertIn('@MainActor public final class SquarePostLocalMediaSelection', source)

    def test_order_duplicates_cleanup_and_no_silent_prefix_success(self):
        source = self.selection()
        self.assertIn('items.append(item)', source)
        self.assertIn('Set(ids) == Set(items.map(\\.id))', source)
        self.assertIn('items.contains(where: { $0.reference == removed }) ? [] : [removed]', source)
        self.assertNotIn('.prefix(', source)
        self.assertIn('items[index] = .init(id: id, reference: reference, kind: kind, phase: .selected)', source)

    def test_authored_swift_cases_cover_boundaries_without_claiming_runtime(self):
        contracts = self.read('Tests/CoreTests/SquarePostLocalMediaContractsTests.swift')
        selection = self.read('Tests/CoreTests/SquarePostLocalMediaSelectionTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', contracts)), 11)
        self.assertEqual(len(re.findall(r'func test\w+\(', selection)), 14)
        for token in ['.noBytes', '.byteCountMismatch', '.wrongReference', '.wrongKind',
                      'Int64.max', 'appDecodingPerformed', 'abc is not a video']:
            self.assertIn(token, contracts)
        self.assertIn('testCopiedPrefixCannotMintEvidenceAfterOriginalAttemptExceedsLimit', contracts)
        self.assertIn('var copiedPrefix = original', contracts)
        self.assertIn('testInspectionAliasesShareActualByteCountAndDigestBeforeOneFinish', contracts)
        for token in ['testReorderAndInterleavedChecksBindToIDsRatherThanOldOffsets',
                      'testEqualReplacementAndSourceVersionABARetireOldAttempt',
                      'testPolicyChangeInvalidatesPreviewAndPendingCheckButPreservesBoundDescriptions',
                      'testLastRepeatedReferenceOnlyIsReportedForLocalCleanup',
                      'testSameReferenceVersionRejectsChangedBytesUntilNewVersionIsSelected',
                      'testAllSquareScopeChangesRejectOldBytesAndReleaseOnlyLocalReferences']:
            self.assertIn(token, selection)
        self.assertNotRegex(contracts + selection, r'\.complete\([^\n]*\.beginInspection\(')

    def test_stale_evidence_replay_does_not_consume_an_inspection_twice(self):
        source = self.read('Tests/CoreTests/SquarePostLocalMediaSelectionTests.swift')
        for name, attempt, receiver in [
            ('testBackgroundOrReturnInvalidationNeedsNewScopeLeaseAndNewInspection', 'old', 'value'),
            ('testRetainedOwnerReferenceCannotRestoreAnEarlierSelectionState', 'pending', 'retainedOwner'),
        ]:
            with self.subTest(name=name):
                match = re.search(rf'    func {name}\(\) throws \{{\n(.*?)\n    \}}', source, re.S)
                self.assertIsNotNone(match)
                body = match.group(1)
                self.assertEqual(body.count(f'let staleEvidence = try evidence({attempt})'), 1)
                self.assertNotIn(f'.complete(try evidence({attempt}))', body)
                self.assertGreaterEqual(body.count(f'XCTAssertFalse({receiver}.complete(staleEvidence))'), 3)
                self.assertIn(
                    f'XCTAssertThrowsError(try evidence({attempt})) {{ XCTAssertEqual($0 as? SquarePostLocalMediaIssue, .finished) }}',
                    body,
                )
                for required in [
                    'XCTAssertEqual(value.snapshot, closed)',
                    'XCTAssertEqual(value.snapshot, inspecting)',
                    f'XCTAssertNotEqual(fresh.token.lease, {attempt}.token.lease)',
                    'XCTAssertTrue(value.complete(try evidence(fresh)))',
                    '.metadataWithinPolicyAwaitingAppDecode',
                ]:
                    self.assertIn(required, body)


if __name__ == '__main__':
    unittest.main()
