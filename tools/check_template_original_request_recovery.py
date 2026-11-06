#!/usr/bin/env python3
"""Offline source/contract checks only. This does not compile or execute Swift."""
import base64
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
def source(name): return (ROOT / name).read_text()
def method(text, start, end): return text.split(start, 1)[1].split(end, 1)[0]

class TemplateOriginalRecoverySourceChecks(unittest.TestCase):
    def test_donor_protocol_and_paths_are_preserved(self):
        s = source('Core/TemplateAuthoringRequestReceipt.swift')
        for value in ('original-template-author-request-v1', 'api/template/author-requests/submit', 'api/template/author-requests/read'):
            self.assertIn('"' + value + '"', s)
        self.assertNotIn('resumePath', s)

    def test_known_personal_wire_vector(self):
        command = {'originalPath': 'api/template/draft', 'fields': {'description': '', 'isSync': 0, 'title': 'Fixture'}}
        wire = json.dumps(command, separators=(',', ':'), sort_keys=True).encode()
        encoded = base64.b64encode(wire).decode()
        self.assertEqual(json.loads(base64.b64decode(encoded)), command)
        self.assertEqual(hashlib.sha256(wire).hexdigest(), '2884a9352db3d2e907ff0ca84cd77b0c097fd7d9c6478c40186fbe2a5271d703')

    def test_source_binds_payload_hash_to_preserved_bytes(self):
        s = source('Core/TemplateAuthoringRequestReceipt.swift')
        for value in ('ProjectEditRequestContract.digest(bytes) == payloadSHA256', '2_097_152', '32_768', 'payloadBase64Chunks.count <= 86', 'requestId == operationID.uuidString.lowercased()', 'ProjectEditPendingMaterials.exactData(command.descriptor) == expected'):
            self.assertIn(value, s)
        self.assertIn('Set(all.allKeys.map(\\.stringValue)) == Set(["originalPath", "fields"])', s)
        self.assertIn('merchant == nil', s)

    def test_recovery_is_read_only_and_never_clears(self):
        c = source('Core/TemplateAuthoringCoordinator.swift')
        read = method(c, 'public func readOriginalRequest() async {', 'public func loadMine() async')
        self.assertIn('requestService.read(request, session: session)', read)
        for forbidden in ('clearPending', '.submit(', 'Command(', 'Submit(', 'UUID('): self.assertNotIn(forbidden, read)
        service = source('Core/TemplateAuthoringRequestHTTPService.swift').split('public func read(', 1)[1]
        self.assertIn('path: TemplateAuthoringRequestReceipt.readPath, write: false', service)
        self.assertNotIn('resumeMedia', service)

    def test_single_producer_dispatch_and_no_fallback_after_error(self):
        c = source('Core/TemplateAuthoringCoordinator.swift')
        confirm = method(c, 'public func confirm(_ value:', 'private func acceptOriginalReceipt(')
        self.assertEqual(confirm.count('requestService.submit('), 1)
        submit = confirm.index('requestService.submit(')
        self.assertLess(confirm.index('try store.savePending(intent'), submit)
        self.assertLess(confirm.index('guard active(session, stamp)'), submit)
        self.assertLess(confirm.index('return', submit), confirm.index('adapter.submitWithReceipt'))

    def test_legacy_pending_and_exact_result_binding(self):
        s = source('Core/TemplateAuthoringStorage.swift')
        self.assertIn('guard let serverRequest else { return serverReceipt == nil }', s)
        self.assertIn('serverRequest.matches(operationID: operationID, request: request)', s)
        self.assertIn('terminal == serverReceipt.committed', s)
        self.assertIn('savedDraft?.memberTemplateID == id && publishedReceipt == nil', s)
        self.assertIn('publishedReceipt?.memberTemplateID == id && savedDraft == nil', s)
        self.assertIn('if value.serverRequest != nil || value.savedDraft != nil || value.publishedReceipt != nil', s)

    def test_read_has_session_permission_cancellation_fences(self):
        s = source('Core/TemplateAuthoringRequestHTTPService.swift')
        for value in ('current?() == issued', '!Task.isCancelled', 'TemplateAuthoringSavedResult.exactSession', 'current.token.utf8.elementsEqual(c.token.utf8)', 'allowed(path, write: write)'):
            self.assertIn(value, s)
        c = source('Core/TemplateAuthoringCoordinator.swift')
        self.assertIn('!originalRequestBusy && state != .submitting', c)
        self.assertIn('guard active(session, stamp), pending == intent', c)

    def test_terminal_receipt_does_not_regress_or_unlock(self):
        c = source('Core/TemplateAuthoringCoordinator.swift')
        accept = method(c, 'private func acceptOriginalReceipt(', 'public func readOriginalRequest()')
        self.assertIn('prior.state == receipt.state, prior.memberTemplateID == receipt.memberTemplateID', accept)
        self.assertNotIn('clearPending', accept)
        self.assertIn('try store.savePending(saved, session: session)', accept)
        self.assertIn('guard active(session, stamp), pending == intent', accept)
        self.assertIn('receipt.state == "REJECTED" ? .blocked : .uncertain', accept)

    def test_view_action_uses_captured_identity(self):
        s = source('App/TemplateAuthoringView.swift')
        for value in ('coordinator.identity == identity', 'coordinator.pending?.serverRequest?.requestId == requestID',
                      'TemplateAuthoringSavedResult.exactSession(current, session)', 'templateAuthor.readOriginalRequest'):
            self.assertIn(value, s)

    def test_existing_independent_fields_are_retained(self):
        c = source('Core/TemplateAuthoringCoordinator.swift')
        for value in ('localCheckpointForExit', 'publishedReceipt', 'beginNewDraft', 'shelfReader', 'matchesAcknowledgedReadback'):
            self.assertIn(value, c)
        self.assertIn('requestService == nil && adapter.canSimulate', c)
        self.assertIn('value.generation == shelfGeneration, adapter.canSubmit', c)

    def test_swift_tests_are_authored_for_failure_paths(self):
        s = source('Tests/CoreTests/TemplateAuthoringRequestRecoveryTests.swift')
        self.assertGreaterEqual(len(re.findall(r'func test\w+\(', s)), 21)
        for value in ('testLegacyPending', 'testCancellationDuringRead', 'testRepeatedReadWhileInFlight',
                      'testRevokedReadApproval', 'testSessionAndTokenChanges', 'testStorageLoss', 'testHTTPNotFound'):
            self.assertIn(value, s)

    def test_original_response_uses_existing_strict_wire_parser(self):
        service = source('Core/TemplateAuthoringRequestHTTPService.swift')
        self.assertIn('let envelope = try ApprovedTopicReleaseWire.envelope(data)', service)
        self.assertNotIn('OperationAdapterHTTP.envelope(data)', service)
        strict = service.index('ApprovedTopicReleaseWire.envelope(data)')
        self.assertLess(service.index('guard data.count <= 2_097_152'), strict)
        self.assertLess(service.index('TemplateAuthoringSavedResult.exactSession(current.session, c.session)'), strict)
        self.assertLess(strict, service.index('from: JSONEncoder().encode(body)'))
        existing = source('Core/ApprovedTopicReleaseDomain.swift')
        self.assertIn('_ = try ContentDraftJSON.parse(text)', existing)

    def test_duplicate_identity_regressions_use_raw_wire_and_both_endpoints(self):
        tests = source('Tests/CoreTests/TemplateAuthoringRequestRecoveryTests.swift')
        for name in ('testDuplicateProtocolRequestHashAndStateRejectSubmitAndRead',
                     'testDuplicateEnvelopeAndNestedMemberIDRejectSubmitAndRead',
                     'testEscapedDuplicateIdentityAndNestedMemberIDRejectSubmitAndRead'):
            self.assertIn(name, tests)
        self.assertIn('committedRawResponse', tests)
        self.assertIn(r'\u0072equestId', tests)
        self.assertIn(r'\u006demberTemplateId', tests)
        verify = method(tests, 'private func verifyMalformedOriginalResponse(', 'func testDuplicateProtocol')
        self.assertIn('await value.readOriginalRequest()', verify)
        self.assertIn('XCTAssertEqual(value.pending, original)', verify)
        self.assertIn('XCTAssertNil(value.pending?.serverReceipt)', verify)

    def test_malformed_committed_and_wrong_owner_durability_regressions(self):
        tests = source('Tests/CoreTests/TemplateAuthoringRequestRecoveryTests.swift')
        self.assertIn('testMalformedCommittedResultCannotCreateAnyHandoff', tests)
        self.assertIn('testMalformedIdentityFieldTypesKeepSubmitAndReadUnknown', tests)
        self.assertIn('testWrongAccountAfterReadKeepsOriginalOwnersDurableUnknownRecord', tests)
        self.assertIn('store.pending(session: owner, identity: identity), original', tests)
        receipt = source('Core/TemplateAuthoringRequestReceipt.swift')
        self.assertIn('(state != "COMMITTED" || memberTemplateID != nil)', receipt)
        self.assertIn('requestId == value.requestId && payloadSHA256 == value.payloadSHA256', receipt)

    def test_shared_dependencies_are_original_types(self):
        s = source('Core/TemplateAuthoringRequestReceipt.swift')
        self.assertIn('[ProjectEditPostProcessingReceipt.Media]', s)
        self.assertNotIn('struct Media:', s)
        self.assertTrue((ROOT / 'Core/ProjectEditRequestContract.swift').is_file())
        self.assertTrue((ROOT / 'Core/ProjectEditPostProcessingReceipt.swift').is_file())

if __name__ == '__main__': unittest.main(verbosity=2)
