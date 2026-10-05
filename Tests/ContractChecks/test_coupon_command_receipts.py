"""Offline source/fixture checks, NOT execution of Swift, AppSession or the iOS UI."""
import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'Tests/Fixtures/CouponCommandReceipts'

class CouponCommandReceiptChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_real_java_golden_vectors_match_independent_binary_encoder(self):
        def string(value):
            if value is None: return struct.pack('>i', -1)
            encoded = value.encode('utf-8')
            return struct.pack('>i', len(encoded)) + encoded
        rows = json.loads((FIXTURES / 'java-canonical-vectors.json').read_text())
        self.assertEqual(len(rows), 12)
        for row in rows:
            raw = struct.pack('>i', 1) + string(row['operation']) + struct.pack('>iqq', 1, row['merchantId'], row['ownerMemberId'])
            if row['operation'] == 'PUBLISH':
                raw += string(row['name']) + string(row['description'])
                raw += struct.pack('>iqqq', row['couponType'], row['publishCount'], row['startMilliseconds'], row['endMilliseconds'])
            else: raw += struct.pack('>q', row['couponId'])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row['payloadHash'], row['label'])
        hashes = {r['label']: r['payloadHash'] for r in rows}
        self.assertEqual(hashes['null-description'], hashes['count-decimal-integral'])
        self.assertEqual(hashes['null-description'], hashes['count-exponent-integral'])
        self.assertEqual(hashes['null-description'], hashes['different-actor-not-in-hash'])
        self.assertNotEqual(hashes['null-description'], hashes['empty-description'])
        self.assertNotEqual(hashes['null-description'], hashes['millisecond-difference'])

    def test_production_jackson_fixtures_distinguish_rejection_and_missing(self):
        success = json.loads((FIXTURES / 'command-publish-succeeded.json').read_text())
        reject = json.loads((FIXTURES / 'command-publish-rejected.json').read_text())
        self.assertEqual(success['code'], 200)
        self.assertEqual(success['data']['id'], success['data']['commandReceipt']['couponId'])
        self.assertEqual(reject['code'], 500)
        self.assertEqual(reject['data']['commandReceipt']['outcome'], 'REJECTED')
        self.assertIsNone(reject['data']['commandReceipt']['couponId'])
        self.assertIsNone(reject['data']['commandReceipt']['couponStatusAtExecution'])
        self.assertEqual(success['data']['commandReceipt']['completedAt'], '2026-10-04T22:00:00.123+08:00')

    def test_owner_fixture_privacy_projection_and_minimal_decode(self):
        owner = json.loads((FIXTURES / 'coop-profile-owner.json').read_text())['data']
        self.assertEqual((owner['id'], owner['memberId']), (11, 9001))
        for key in ['phone', 'wechat', 'businessLicense', 'status', 'accountStatus', 'delFlag']:
            self.assertNotIn(key, owner)
        source = self.read('Core/CouponCommandReceipts.swift')
        identity = source.split('struct CouponCommandOwnerIdentity: Decodable {')[1].split('/// Added only')[0]
        self.assertIn('let id: Int', identity); self.assertIn('let memberId: Int', identity)
        self.assertIn('identity.id == merchantID, identity.memberId > 0', identity)
        self.assertNotIn('phone', identity)

    def test_protocol_default_nil_and_owner_permission_is_v1_only(self):
        runtime = self.read('Core/CouponManagementRuntime.swift')
        self.assertEqual(runtime.count('commandProtocol: CouponCommandProtocolApproval? = nil'), 3)
        branch = runtime.split('if let approval = commandProtocol {')[1]
        self.assertIn('access.permissions.contains("merchant:coop:manage")', branch)
        self.assertIn('access.permissions.contains("merchant:coupon:manage")', runtime)
        self.assertIn('after == access', branch)
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('else if read.commandProtocol != nil { throw APIError.notConfigured }', root)
        self.assertIn('fresh.commandProtocol?.revision == capability.revision', root)

    def test_new_journal_is_before_dispatch_and_legacy_is_never_upgraded(self):
        source = self.read('Core/CouponManagementCoordinator.swift')
        self.assertLess(source.index('record.command = try adapter.prepareCommand'), source.index('try locks.acquire(record)'))
        self.assertLess(source.index('try locks.acquire(record)'), source.index('await adapter.submit'))
        recovery = source.split('public func recoverPendingCommands()')[1].split('private func refreshAfterMutation')[0]
        for forbidden in ['UUID()', 'adapter.submit', 'prepareCommand', 'locks.acquire', 'sendReviewed', 'sendConfirmed']:
            self.assertNotIn(forbidden, recovery)
        self.assertIn('after == permission', recovery)
        self.assertIn('case .receipt', recovery); self.assertIn('case .rejected', recovery)
        self.assertIn('default: issue = .locked', recovery)
        self.assertIn('public var command: CouponCommandIdentity? = nil', self.read('Core/CouponManagementLocks.swift'))

    def test_exact_payload_wire_and_whole_hash_checked_before_terminal(self):
        source = self.read('Core/CouponCommandReceipts.swift')
        for expected in ['wire.contentType == expected.contentType, wire.data == expected.data', 'try validatePayload(record: record)', '(try? command.validatePayload(record: record)) != nil', r'\A[0-9a-f]{64}\z']:
            self.assertIn(expected, source)
        for dimension in ['receipt.actorMemberId == command.actorMemberID', 'receipt.ownerMemberId == command.ownerMemberID', 'receipt.merchantId == command.merchantID', 'receipt.requestId == command.requestID', 'receipt.operation == command.operation', 'receipt.version == command.version', 'receipt.payloadHash == command.payloadHash']:
            self.assertIn(dimension, source)

    def test_usable_recovery_surface_and_apple_tests_are_authored(self):
        self.assertIn('await model.core.recoverPendingCommands()', self.read('App/CouponManagementView.swift'))
        self.assertIn('func pendingCommands(ownerKey:', self.read('App/SessionCouponManagementView.swift'))
        self.assertIn('testV1ReadOnlyReceiptRecoveryAfterRestartAndNotFoundKeepsJournal', self.read('Tests/AppUITests/CouponCommandRecoveryFlowTests.swift'))
        self.assertIn('testV1FinalBoundaryRevocationRetainsJournalWithoutDispatch', self.read('Tests/AppUnitTests/CouponRuntimeCompositionTests.swift'))
        self.assertIn('testPersistedWireMismatchAndUnrelatedCorruptFileNeverUnlock', self.read('Tests/CoreTests/CouponCommandReceiptTests.swift'))

if __name__ == '__main__': unittest.main()
