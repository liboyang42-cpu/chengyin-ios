#!/usr/bin/env python3
"""Offline source-shape regression checks, not Swift compilation or runtime evidence."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

def source(path):
    return (ROOT / path).read_text()

class OriginalPublishingRequestSourceChecks(unittest.TestCase):
    def test_original_routes_and_protocols_are_literal_and_separate(self):
        activity = source('Core/ActivityCreateRequestContract.swift')
        state = source('Core/ProjectStateRequestContract.swift')
        for suffix in ['submit', 'read', 'resume-post-processing']:
            self.assertIn('api/activity/create-requests/' + suffix, activity)
        for suffix in ['context', 'submit', 'read']:
            self.assertIn('api/project/state-requests/' + suffix, state)
        self.assertIn('original-activity-create-request-v1', activity)
        self.assertIn('original-project-state-request-v1', state)

    def test_personal_scope_has_no_absent_merchant_or_market_producer(self):
        files = ['ActivityCreateRequestContract.swift', 'ProjectStateRequestContract.swift', 'PublishModesService.swift']
        for name in files:
            text = source('Core/' + name)
            for unsupported in ['MerchantActivityCreateContract', 'TemplateOwnShelfMarketContext', 'TemplateOwnShelfMarketAction', 'prepareMerchantActivity', 'prepareOwnShelf']:
                self.assertNotIn(unsupported, text)
        self.assertIn('session.role == "club"', source('Core/PublishModesService.swift'))

    def test_payload_uses_original_sorted_bytes_digest_and_chunks(self):
        for name in ['ActivityCreateRequestContract', 'ProjectStateRequestContract']:
            text = source('Core/' + name + '.swift')
            self.assertIn('ProjectEditRequestContract.digest(bytes)', text)
            self.assertIn('2_097_152', text)
            self.assertIn('32_768', text)
            self.assertIn('UUID(uuidString: requestId)?.uuidString.lowercased() == requestId', text)
        self.assertIn('ProjectEditRequestContract.payloadBytes(fields)', source('Core/ActivityCreateRequestContract.swift'))

    def test_receipts_require_original_identity_and_business_facts(self):
        a = source('Core/ActivityCreateRequestContract.swift')
        s = source('Core/ProjectStateRequestContract.swift')
        for text in [a, s]:
            self.assertIn('requestId == submit.requestId', text)
            self.assertIn('payloadSHA256 == submit.payloadSHA256', text)
            self.assertIn('["NOT_FOUND", "RUNNING", "COMMITTED", "REJECTED"]', text)
        self.assertIn('(state != "COMMITTED" || committed)', a)
        self.assertIn('$0 > 0 ? $0 : nil', a)
        self.assertIn('(state != "COMMITTED" || terminal)', s)
        self.assertIn('kind == ProjectStateRequestContract.resourceKind(command.originalPath)', s)
        self.assertIn('originalResult?.object?["applied"] == .bool(false)', s)

    def test_postprocessing_is_bound_to_original_fingerprint(self):
        text = source('Core/ActivityCreateRequestContract.swift')
        self.assertIn('original-activity-create-postprocess-v1', text)
        self.assertIn('processing?.requestID == requestId', text)
        self.assertIn('processing?.payloadSHA256 == payloadSHA256', text)
        text = source('Core/PublishModesService.swift')
        self.assertIn('saved.receipt?.committed == true, saved.receipt?.processing?.canResume == true', text)
        self.assertIn('resume ? saved.submit.resumePath : saved.submit.readPath', text)

    def test_intent_and_lock_precede_dispatch_without_legacy_fallback(self):
        text = source('Core/PublishModesService.swift').split('public func submit(')[1].split('public var canReadActivityReceipt')[0]
        dispatch = text.index('await transport.send(request)')
        for marker in ['store.saveActivityRequest(', 'store.saveStateRequest(', 'try journal.write(record)', 'reviews.removeValue(forKey: review.id)']:
            self.assertLess(text.index(marker), dispatch)
        self.assertNotIn('build(review.request', text)
        self.assertEqual(text.count('try journal.clear(record)'), 2)
        self.assertEqual(text.count('guard receipt.terminal else { return .unknown }'), 2)

    def test_unknown_intent_is_not_removed_or_automatically_resent(self):
        service = source('Core/PublishModesService.swift')
        store = source('Core/PublishModesDraftStore.swift')
        self.assertIn('previous == nil || previous?.receipt?.terminal == true', service)
        self.assertIn('$0.targetKey == review.targetKey && $0.receipt?.terminal != true', service)
        self.assertNotIn('storage.remove(', store)
        recovery = service.split('public func readActivityOutcome')[1].split('// No automatic resend')[0]
        self.assertNotIn('.submitPath', recovery)
        self.assertNotIn('api/activity/publish', recovery)

    def test_state_index_crash_window_is_fail_closed(self):
        text = source('Core/PublishModesDraftStore.swift')
        save = text.split('public func saveStateRequest')[1]
        self.assertLess(save.index('storage.write(indexBytes'), save.index('storage.write(bytes, key: key)'))
        self.assertIn('guard let value = try stateRequest(id: $0, session: session) else { throw PublishModesError.storage }', text)
        self.assertNotIn('compactMap { try stateRequest', text)
        self.assertIn('Set(ids).count == ids.count', text)

    def test_compare_and_swap_immutability_and_owner_scoping(self):
        text = source('Core/PublishModesDraftStore.swift')
        self.assertIn('try activityRequest(session: session) == expected', text)
        self.assertIn('try stateRequest(id: value.id, session: session) == expected', text)
        self.assertIn('expected?.submit.requestId != value.submit.requestId', text)
        self.assertGreaterEqual(text.count('value.receipt?.originalResult == expected?.receipt?.originalResult'), 2)
        self.assertIn('value.ownerKey == session.storageKey, value.valid', text)
        self.assertIn('publishing.activity.request.v1.', text)
        self.assertIn('publishing.state.requests.v1.', text)

    def test_original_template_identity_is_not_generic_id(self):
        text = source('Core/PublishModesContracts.swift')
        self.assertIn('project.resource.kind == .template ? "template_id" : "id"', text)
        self.assertIn('f["publish_status"] = .string(project.online ? "0" : "1")', text)

    def test_read_recovery_requires_its_own_grant_and_saved_request(self):
        text = source('Core/PublishModesService.swift')
        self.assertIn('activityReceiptApproval: OperationEndpointApproval? = nil', text)
        self.assertIn('activityRequestStore: PublishingDraftStore? = nil', text)
        self.assertIn('activityReceiptApproval?.allows', text)
        self.assertIn('try store.stateRequest(id: saved.id, session: session) == saved', text)
        self.assertIn('pending.operationID.uuidString.lowercased() == saved.submit.requestId', text)
        self.assertIn('pending.operationID.uuidString.lowercased() == saved.id', text)

    def test_activity_owner_restores_receipt_and_preserves_unknown_lock(self):
        text = source('App/PublishingModesViews.swift')
        for marker in ['retainedActivityReceipt(session: account)', 'readActivityOutcome(session: account)', 'startAnotherActivity()', 'outcome != .unknown, !lockUnavailable', 'ignoredCompletedRequest', 'receiptReadUnavailable']:
            self.assertIn(marker, text)
        self.assertIn('ActivityPublishingTimeRangePresenter', text)
        self.assertIn('ActivityTemplateSelectionLifetimeAnchor', text)
        self.assertIn('makeProfessional', text)
        self.assertIn('makeTemplateAuthoring', text)
        self.assertIn('questifyBottomAction', text)

    def test_state_history_survives_absent_list_row(self):
        text = source('App/PublishingManagementViews.swift')
        self.assertIn('ForEach(requests)', text)
        self.assertIn('service.readStateOutcome(saved, session: account)', text)
        self.assertIn('A missing list row does not confirm deletion', text)
        self.assertIn('requestAccount == account, service?.currentSession == account', text)
        self.assertIn('hasPendingRequest(project.resource)', text)

    def test_original_response_boundaries_reuse_existing_strict_wire(self):
        text = source('Core/PublishModesService.swift')
        ordinary = text.split('public func read(_ query:')[1].split('public func identityRegistered')[0]
        self.assertIn('OperationAdapterHTTP.envelope(data)', ordinary)
        self.assertNotIn('ApprovedTopicReleaseWire.envelope(data)', ordinary)
        self.assertEqual(text.count('OperationAdapterHTTP.envelope(data)'), 1)
        self.assertEqual(text.count('ApprovedTopicReleaseWire.envelope(data)'), 4)
        for start, end in [('public func prepareProject(', 'public func cancel('),
                           ('public func submit(', 'public var canReadActivityReceipt'),
                           ('private func activityOutcome(', 'public func stateRequests('),
                           ('public func readStateOutcome(', '// No automatic resend')]:
            section = text.split(start)[1].split(end)[0]
            self.assertIn('ApprovedTopicReleaseWire.envelope(data)', section)
            self.assertNotIn('OperationAdapterHTTP.envelope(data)', section)

    def test_raw_response_regressions_cover_every_new_protocol_flow(self):
        text = source('Tests/CoreTests/PublishingOriginalRequestRecoveryTests.swift')
        for scenario in ['OriginalStateContext', 'OriginalActivitySubmit', 'OriginalStateSubmit', 'OriginalActivityReadAndResume', 'OriginalStateRead']:
            self.assertRegex(text, r'func test' + scenario + r'Rejects?DuplicateIdentityAndUnboundedRawResponses')
        self.assertIn('var rawHandler: ((URLRequest) throws -> Data)?', text)
        self.assertIn('escaped duplicate identity', text)
        self.assertIn('excessive depth', text)
        self.assertIn('excessive size', text)
        self.assertIn('count: 40', text)
        self.assertIn('count: 4 * 1024 * 1024', text)
        self.assertIn('error as? ApprovedTopicReleaseError, .invalidResponse', text)

    def test_tests_cover_required_failure_and_restoration_boundaries(self):
        core = source('Tests/CoreTests/PublishingOriginalRequestRecoveryTests.swift')
        ui = source('Tests/AppUnitTests/ActivityPublishingRequestRecoveryOwnerTests.swift')
        self.assertGreaterEqual(len(re.findall(r'func test', core)), 15)
        for phrase in ['NotFoundAndRunning', 'JournalFailure', 'InterruptedStatePersistence', 'MalformedCommit', 'AccountIsolation', 'PostProcessingResume', 'FailedJournalClear']:
            self.assertIn(phrase, core)
        self.assertIn('TerminalReceiptWithRemainingJournalLockCannotStartAnother', ui)
        self.assertIn('AccountChangeAndBackground', ui)

if __name__ == '__main__':
    unittest.main(verbosity=2)
