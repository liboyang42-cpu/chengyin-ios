"""Finite source-bearing review budgets and pre-persistence wiring; not native runtime."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

def compact(value): return json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode()
def tokens(value):
    if isinstance(value, dict): return 2 + sum(1 + tokens(v) for v in value.values())
    if isinstance(value, list): return 2 + sum(tokens(v) for v in value)
    return 1

class ReviewRequestBodyBudgetContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def fixture(self, name, part): return json.loads(self.read('Tests/Fixtures/ReviewRequestBudget/' + name + '-' + part + '.json'))
    def test_shared_limit_is_finite_and_exclusively_for_review_prepare_submit(self):
        s = self.read('Core/ApprovedTopicReviewRequestBody.swift')
        self.assertIn('maximumSourceBodyBytes = 16 * 1024', s)
        self.assertIn('maximumSelectorBodyBytes = 4096', s)
        method = s.split('public static func maximumBytes(for path:', 1)[1].split('public static func encode', 1)[0]
        self.assertIn('path == ApprovedTopicReviewPath.prepare || path == ApprovedTopicReviewPath.submit', method)
        self.assertIn('? maximumSourceBodyBytes : maximumSelectorBodyBytes', method)
        self.assertNotIn('ProjectMerchantDraftPath', method)
        self.assertNotIn('ApprovedTopicReleasePublicationPath', method)
        self.assertIn('guard encoded.count <= maximumBytes(for: path, fields: fields)', s)
        self.assertIn('fields["sourceSelections"] != nil ? maximumBytes(for: path) : maximumSelectorBodyBytes', s)
    def test_client_and_outer_route_share_budget_without_relaxing_other_routes(self):
        client = self.read('Core/ApprovedTopicReviewClient.swift')
        self.assertIn('let encoded = try ApprovedTopicReviewRequestBody.encode(body, path: path)', client)
        self.assertNotIn('encoded.count <= 4096', client)
        route = self.read('App/ApprovedReleaseCompositionRoute.swift')
        self.assertIn('if self == .reviewPrepare || self == .reviewSubmit {', route)
        self.assertIn('guard bytes.count <= ApprovedTopicReviewRequestBody.maximumBytes(for: path) else { return nil }', route)
        self.assertIn('} else {\n            guard bytes.count <= 4096 else { return nil }', route)
        self.assertLess(route.index('bytes.count <= ApprovedTopicReviewRequestBody.maximumBytes'), route.index('ApprovedTopicReleaseWire.envelope(bytes)'))
        self.assertIn('ApprovedMerchantReviewSource.decodeSelections(selected)', route)
        self.assertIn('guard bytes.count <= ApprovedTopicReviewRequestBody.maximumBytes(for: path, fields: value) else { return nil }', route)
    def test_complete_actual_submit_command_is_checked_before_any_journal_replace(self):
        j = self.read('Core/ApprovedTopicReviewJournal.swift')
        can = j.split('public func canBegin(', 1)[1].split('public func begin(', 1)[0]
        self.assertIn('try ApprovedTopicReviewRequestBody.preflight(.init(capture: capture), capture: capture)', can)
        begin = j.split('public func begin(', 1)[1].split('public func record(', 1)[0]
        self.assertIn('let command = ApprovedTopicReviewCommand(capture: capture, requestID: requestID)', begin)
        exact = 'try ApprovedTopicReviewRequestBody.preflight(command, capture: capture)'
        self.assertLess(begin.index('let command ='), begin.index(exact))
        self.assertLess(begin.index(exact), begin.index('let record = Record('))
        self.assertLess(begin.index(exact), begin.index('return try replace('))
        self.assertIn('command: command, capture: capture', begin)
        helper = self.read('Core/ApprovedTopicReviewRequestBody.swift').split('public static func preflight(', 1)[1]
        self.assertIn('ApprovedTopicReviewCommand.decode(.object(command.fields), capture: capture)', helper)
        self.assertIn('encode(command.fields, path: ApprovedTopicReviewPath.submit)', helper)
    def test_historical_read_does_not_rewrite_or_drop_full_command(self):
        j = self.read('Core/ApprovedTopicReviewJournal.swift')
        read = j.split('public func read(', 1)[1].split('private func replace(', 1)[0]
        self.assertIn('ApprovedTopicReviewCommand.decode(commandValue, capture: capture)', read)
        for forbidden in ['RequestBody.preflight', 'storage.write', 'storage.remove', 'removeAll']:
            self.assertNotIn(forbidden, read)
        client = self.read('Core/ApprovedTopicReviewClient.swift')
        self.assertIn('path == ApprovedTopicReviewPath.status ? record.command.readSelectorFields : record.command.fields', client)
        self.assertIn('send(record.command.readSelectorFields, session: session, path: ApprovedTopicReviewPath.current)', client)
    def test_real_nine_source_prepare_submit_mismatch_fixture_is_preserved(self):
        name = 'nine_prepare_fits_submit_does_not'; p = self.fixture(name, 'prepare'); s = self.fixture(name, 'submit')
        self.assertEqual((len(compact(p)), tokens(p)), (3901, 243))
        self.assertEqual((len(compact(s)), tokens(s)), (4105, 251))
        self.assertLessEqual(len(compact(p)), 4096); self.assertGreater(len(compact(s)), 4096)
        self.assertEqual(p['sourceSelections'], s['sourceSelections'])
    def test_all_thirty_two_maximum_width_ids_fit_both_byte_and_token_limits(self):
        name = 'thirty_two_native_maximum'; p = self.fixture(name, 'prepare'); s = self.fixture(name, 'submit')
        self.assertEqual((len(compact(p)), tokens(p)), (13630, 841))
        self.assertEqual((len(compact(s)), tokens(s)), (13843, 849))
        self.assertEqual(len(s['sourceSelections']), 32)
        self.assertEqual(len(compact(s['sourceSelections'][0])), 422)
        for name in ['memberTemplateId']:
            ids = [row[name] for row in s['sourceSelections']]
            self.assertEqual(ids, list(range(2**63-32, 2**63)))
        self.assertEqual(s['observedAuditTaskVersion'], 2**31-1)
        self.assertEqual(s['topicId'], 2**63-1); self.assertEqual(s['sourceConfigVersion'], 2**63-1)
        backend = dict(s, requestId='a'*128)
        self.assertEqual(len(compact(backend)), 13935)
        self.assertLessEqual(len(compact(backend)), 16384); self.assertLessEqual(tokens(backend), 1024)
    def test_fixtures_remain_exact_owner_source_hash_shapes_and_capture_bindings(self):
        for name in ['nine_prepare_fits_submit_does_not', 'eleven_small_ids', 'thirty_two_native_maximum']:
            p = self.fixture(name, 'prepare'); s = self.fixture(name, 'submit'); c = self.fixture(name, 'prepare-response-data')
            self.assertEqual(set(p), {'topicId', 'observedAuditTaskId', 'sourceSelections'})
            self.assertEqual(set(s), set(p) | {'observedAuditTaskVersion', 'sourceConfigVersion', 'snapshotHash', 'requestId'})
            self.assertEqual(c['summary']['selectedMerchantSources'], s['sourceSelections'])
            self.assertEqual(c['summary']['productType'], 1); self.assertEqual(c['summary']['publishMode'], 'pro')
            self.assertFalse(c['approvalProof']); self.assertFalse(c['releaseAllocated'])
            for row in s['sourceSelections']:
                self.assertEqual(set(row), {'memberTemplateId', 'source', 'merchantConfirmation'})
                for key, kind in [('source', 'MERCHANT_AI_TEMPLATE_SOURCE_V1'), ('merchantConfirmation', 'MERCHANT_STORE_FACTS_CONFIRMATION_V1')]:
                    ref = row[key]; self.assertEqual(set(ref), {'kind', 'sourceId', 'sourceVersion', 'contentHash'})
                    self.assertEqual(ref['kind'], kind); self.assertEqual(ref['sourceVersion'], 1)
                    self.assertRegex(ref['contentHash'], r'^[0-9a-f]{64}$'); self.assertTrue(0 < ref['sourceId'] <= 2**63-1)
    def test_swift_regressions_cover_full_command_recovery_and_malicious_boundaries(self):
        core = self.read('Tests/CoreTests/ApprovedTopicReviewRequestBudgetTests.swift')
        app = self.read('Tests/AppUnitTests/ApprovedTopicReviewRouteBudgetTests.swift')
        self.assertEqual(len(re.findall(r'\bfunc test\w+\(', core)), 9)
        self.assertEqual(len(re.findall(r'\bfunc test\w+\(', app)), 5)
        for token in ['3901', '4105', '13630', '13843', 'requestID: uuid', 'reopened.retryExact', 'original.command.readSelectorFields', 'XCTAssertEqual(storage.data, persisted)', 'count: 1024 * 1024', 'XCTAssertEqual(storage.writes, 0)', 'XCTAssertEqual(storage.removals, 0)', 'XCTAssertEqual(storage.values, before)']:
            self.assertIn(token, core)
        for token in ['to: 16384', 'to: 16385', 'to: 4096', 'to: 4097', 'values.append', '"publicationAuthority"', 'ProjectMerchantDraftPath.resolve']:
            self.assertIn(token, app)

if __name__ == '__main__': unittest.main()
