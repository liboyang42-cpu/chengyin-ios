"""Source-only W02 boundary checks. These do not execute or typecheck Swift."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class VersionedContentDraftSourceContracts(unittest.TestCase):
    def text(self, name):
        return (ROOT / name).read_text()

    def test_routes_and_no_publication(self):
        source = self.text('Core/VersionedContentDraftService.swift')
        self.assertIn('case save, restore, list, delete', source)
        self.assertIn('"api/content-draft/"', source)
        self.assertNotIn('case publish', source)
        self.assertNotIn('URLSessionTransport()', source)

    def test_wire_field_names_and_form_reads(self):
        source = self.text('Core/VersionedContentDraftService.swift')
        self.assertIn('"draft_id": String(id)', source)
        self.assertIn('fields["business_type"] = type.rawValue', source)
        self.assertIn('application/x-www-form-urlencoded; charset=utf-8', source)
        self.assertIn('body: attempt.body', source)
        self.assertIn('encoder.encode(mutation.command)', self.text('Core/VersionedContentDraftCoordinator.swift'))
        contracts = self.text('Core/VersionedContentDraftContracts.swift')
        command = contracts.split('public struct Command:')[1].split('public let operationID')[0]
        for field in ['id', 'businessType', 'clientDraftKey', 'subjectId', 'payloadJson', 'expectedVersion', 'deviceId', 'scope']:
            self.assertIn(f'public let {field}:', command)
        self.assertNotIn('ownerMemberId:', command)
        self.assertNotIn('operationID:', command)

    def test_default_unconfigured_and_explicit_read_only_composition(self):
        source = self.text('Core/VersionedContentDraftService.swift')
        self.assertIn('grant: ContentDraftRouteGrant? = nil', source)
        self.assertIn('context.market == .china', source)
        composition = self.text('App/AppCompositionRoot.swift')
        self.assertIn('OwnerDraftReadApproval? = { _ in nil }', composition)
        self.assertIn('OwnerDraftReadRoute(url: url, baseURL: api.baseURL)', composition)
        route = self.text('App/OwnerDraftComposition.swift')
        self.assertIn('case list, restore', route)
        self.assertNotIn('case save', route)

    def test_fence_precedes_error_and_401_side_effect(self):
        source = self.text('Core/VersionedContentDraftService.swift')
        tail = source.split('result = try await transport.send(request)', 1)[1]
        self.assertLess(tail.index('try check(route, identity: identity)'), tail.index('JSONDecoder().decode(Code.self'))
        before_callback = source.split('onUnauthorized(lease.context)', 1)[0]
        self.assertTrue(before_callback.rstrip().endswith('try check(route, identity: identity)'))
        self.assertIn('private var revoked = false', source)
        self.assertIn('if !ContentDraftContextFence.matches(current(), context) { revoked = true }', source)

    def test_unknown_journal_and_known_conflict_are_distinct(self):
        source = self.text('Core/VersionedContentDraftCoordinator.swift')
        self.assertLess(source.index('try await journal.replace(original, with: dispatchedValue)'), source.index('try await service.mutate'))
        self.assertIn('if !original.value.dispatched && rejection', source)
        self.assertIn('phase == .conflict, pending == nil', source)
        self.assertIn('try await journal.clear(matching: dispatched)', source)
        readback = source.split('public func fetchLatestForConflict()', 1)[1].split('public func resolveConflict', 1)[0]
        self.assertNotIn('journal.clear', readback)

    def test_exact_canonical_payload_and_distinct_typed_seam(self):
        source = self.text('Core/VersionedContentDraftContracts.swift')
        self.assertIn('ContentDraftDocument<Payload: Codable & Equatable>', source)
        self.assertIn('payloadHash == Self.hash(payloadJson)', source)
        self.assertIn('receipt.version == command.expectedVersion + 1', source)
        self.assertIn('command.expectedVersion == 0 ||', source)
        self.assertIn('try ContentDraftRecord.json(Self.encode(value)) == ContentDraftRecord.json(record.payloadJson)', source)
        parser = self.text('Core/VersionedContentDraftJSON.swift')
        self.assertNotIn('Double(', parser)
        self.assertIn('case object([Data: ContentDraftJSON])', parser)
        self.assertNotIn('ProjectEditDraft', source)

    def test_complete_wire_document_is_validated_before_envelope_interpretation(self):
        source = self.text('Core/VersionedContentDraftService.swift')
        self.assertIn('ContentDraftJSON.parse(responseText)', source)
        self.assertLess(source.index('ContentDraftJSON.parse(responseText)'), source.index('JSONDecoder().decode(Code.self'))
        self.assertIn('case .object =', source)

    def test_authority_and_journal_comparisons_are_byte_exact(self):
        source = self.text('Core/VersionedContentDraftService.swift')
        self.assertIn('ContentDraftContextFence.matches(current(), context)', source)
        self.assertIn('ContentDraftContextFence.matches(grant.context, lease.context)', source)
        contracts = self.text('Core/VersionedContentDraftContracts.swift')
        self.assertIn('lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8)', contracts)
        self.assertIn('lhs.role.utf8.elementsEqual(rhs.role.utf8)', contracts)
        self.assertIn('lhs.updatedByDevice.utf8.elementsEqual(rhs.updatedByDevice.utf8)', contracts)

    def test_identity_validation_covers_java_trim_edges(self):
        source = self.text('Core/VersionedContentDraftContracts.swift')
        self.assertIn('first > 0x20, last > 0x20', source)

    def test_journal_key_cannot_split_on_request_scope_aliases(self):
        contracts = self.text('Core/VersionedContentDraftContracts.swift')
        scope = contracts.split('public struct ContentDraftJournalScope:')[1].split('public struct ContentDraftPending:')[0]
        self.assertNotIn('public let identity: ContentDraftIdentity', scope)
        for field in ['ownerMemberID: Int64', 'businessType: ContentDraftBusinessType', 'clientDraftKey: String']:
            self.assertIn('public let ' + field, scope)

    def test_recorder_scenarios_authored_and_no_live_hosts(self):
        tests = self.text('Tests/CoreTests/VersionedContentDraftTests.swift')
        names = re.findall(r'func (test\w+)\(', tests)
        self.assertGreaterEqual(len(names), 19)
        for term in ['Late401', 'ABAEven', 'SameKeyBytes', 'UnknownThenConflict', 'Malformed', 'WrongResolvedOwner', 'ListUsesForm']:
            self.assertTrue(any(term in n for n in names), term)
        self.assertIn('private typealias Recorder = ContentDraftRecordingTransport', tests)
        self.assertIn('final class ContentDraftRecordingTransport: HTTPTransport', self.text('Core/VersionedContentDraftService.swift'))
        self.assertNotIn('URLSession', tests)
        self.assertEqual(re.findall(r'https://([^/" ]+)', tests), ['draft-fixture.example'])

if __name__ == '__main__':
    unittest.main()
