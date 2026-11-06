"""Portable source contracts only. Does not compile Swift or execute iOS/HTTP."""
from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[2]
class ProjectOriginalRequestRecoveryContract(unittest.TestCase):
 def text(self,p):return (ROOT/p).read_text()
 def test_original_protocol_routes_and_bounded_original_bytes(self):
  s=self.text('Core/ProjectEditRequestContract.swift')
  for v in ['original-project-edit-request-v1','api/topic/edit-requests/submit','api/topic/edit-requests/read','api/topic/edit-requests/resume-post-processing','payloadBase64Chunks.count <= 86','bytes.count <= 2_097_152','ProjectEditRequestContract.digest(bytes) == payloadSHA256','return original == restored']:self.assertIn(v,s)
 def test_paired_submit_keeps_independent_original_route_guard(self):
  s=self.text('Core/ProjectEditHTTPService.swift').split('public func submit(',1)[1].split('static func decodeAcknowledgment',1)[0]
  self.assertLess(s.index('persisted.dispatchStarted == true'),s.index('approval.allows'))
  for v in ['path: path)','path: ProjectEditRequestContract.submitPath)','dispatched.serverRequest = envelope','dispatched.dispatchStarted = true','ProjectEditLocalStore.exactPending(saved, dispatched)']:self.assertIn(v,s)
  self.assertLess(s.index('try store.savePending(dispatched'),s.index('transport.send(request)'))
  self.assertNotIn('path: path, body:',s)
 def test_recovery_is_read_only_without_fallback(self):
  s=self.text('Core/ProjectEditHTTPService.swift').split('public func retrySameRequest(',1)[1].split('public func resumePostProcessing',1)[0]
  self.assertIn('terminalReceipt(operation: operation',s);self.assertIn('catch { return .unknown }',s)
  for v in ['submit(', 'transport.send', 'savePending','clearPending']:self.assertNotIn(v,s)
 def test_legacy_uuid_never_claims_receipt(self):
  s=self.text('Core/ProjectEditHTTPService.swift').split('public func terminalReceipt(operationID:',1)[1].split('private func exactRequest',1)[0]
  self.assertIn('nil',s);self.assertNotIn('transport.send',s)
  coordinator=self.text('Core/ProjectEditCoordinator.swift')
  self.assertIn('pending.serverRequest != nil && pending.dispatchStarted == true',coordinator)
 def test_restore_lock_precedes_remote_preflight(self):
  s=self.text('Core/ProjectEditCoordinator.swift').split('public func load() async',1)[1].split('public func restoredDraft',1)[0]
  self.assertLess(s.index('pending = try store.pending'),s.index('await service.preflight'))
  self.assertIn('if pending != nil { state = .unknown',s)
 def test_request_and_stored_owner_checked_after_read(self):
  s=self.text('Core/ProjectEditHTTPService.swift').split('public func terminalReceipt(operation:',1)[1].split('public func retrySameRequest',1)[0]
  self.assertEqual(s.count('exactRequest(operation, session: session)'),2)
  self.assertLess(s.index('transport.send'),s.rindex('exactRequest'))
  full=self.text('Core/ProjectEditHTTPService.swift')
  for v in ['operation.ownerKey == session.ownerKey','ProjectEditLocalStore.exactPending(persisted, operation)','requestId"]?.text == sent.requestId','payloadSHA256"]?.text == sent.payloadSHA256','body["state"]?.text == "COMMITTED"']:self.assertIn(v,full)
 def test_no_downgrade_of_committed_writer_fact(self):
  s=self.text('Core/ProjectEditCoordinator.swift').split('private func apply(',1)[1]
  self.assertIn('if operation.serverRequestCommitted == true',s)
  self.assertIn('case .committedReceipt, .postProcessingReceipt, .unknown: break',s)
  self.assertIn('completed.postProcessing = postProcessing ?? operation.postProcessing',s)
 def test_decorator_preserves_recovery_owner(self):
  s=self.text('Core/ProjectAuthorInputReader.swift').split('final class ProjectAuthorInputService',1)[1]
  for v in ['original.supportsRequestReadback','original.supportsPostProcessingResume','original.terminalReceipt(operation: operation','original.retrySameRequest(operation','original.resumePostProcessing(operation']:self.assertIn(v,s)
 def test_ui_only_calls_original_owner(self):
  s=self.text('App/ProjectEditView.swift')
  self.assertIn('if model.coordinator.canCheckOutcome',s);self.assertIn('await coordinator.resumePostProcessing()',s)
  self.assertIn('guard ownsVisit, !busy, coordinator.canResumePostProcessing',s)
  catalog=json.loads(self.text('Resources/ProjectOriginalRecovery.xcstrings'))['strings']
  for row in catalog.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
 def test_exact_composition_proposal_has_no_installed_grant(self):
  s=self.text('App/ProjectEditCompositionRoute.swift')
  for v in ['Set(fields.keys) == Set(["protocolVersion", "requestId", "originalPath", "payloadSHA256", "payloadBase64Chunks"])','ProjectEditRequestContract.digest(payload) == command.payloadSHA256','route.path == command.originalPath','case .home, .detail, .requestRead: return .projectRead']:self.assertIn(v,s)
  runtime=self.text('Core/BusinessRuntimeConfiguration.swift');self.assertIn('routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]',runtime)
 def test_receipt_wire_uses_existing_duplicate_and_resource_validator(self):
  s=self.text('Core/ProjectEditHTTPService.swift').split('static func decodeRequestReceipt',1)[1]
  self.assertIn('ApprovedTopicReleaseWire.envelope(data)',s)
  tests=self.text('Tests/CoreTests/ProjectOriginalRequestRecoveryTests.swift')
  for name in ['testDuplicateOriginalReceiptIdentityAndEscapedAliasesStayUnknown','testOversizedOrDeepOriginalReceiptCannotUnlock','testTransportFailureAndMalformedCommitCannotStandInForTerminalReceipt']:self.assertIn(name,tests)
 def test_original_recovery_and_continuation_do_not_require_detail_snapshot(self):
  s=self.text('App/ProjectEditView.swift')
  self.assertIn('            if model.coordinator.isLocked {',s)
  self.assertNotIn('                if model.coordinator.isLocked {',s)
  self.assertIn('            if let completed = model.coordinator.acknowledgedContinuation {',s)
  self.assertNotIn('                if let completed = model.coordinator.acknowledgedContinuation {',s)
  tests=self.text('Tests/AppUnitTests/ProjectOriginalRequestPresentationTests.swift')
  for name in ['testOfflineDetailStillAllowsOriginalModelReadAndExplicitContinuation','testOwnerChangesDuringOfflineRecoveryKeepOldDurableIntentPrivate']:self.assertIn(name,tests)
 def test_existing_project_toggle_test_identity_is_retained(self):
  s=self.text('Tests/CoreTests/PublishingModesTests.swift')
  self.assertIn('func testProjectToggleUsesMultipartAndReviewedExpectedStatus()',s)
  self.assertNotIn('func testProjectToggleRetainsReviewedOriginalFieldsInDurableEnvelope()',s)
  for value in ['XCTAssertEqual(review.request.encoding, .form)','XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")','XCTAssertEqual(original.command?.originalPath, "api/topic/update_user_status")','XCTAssertEqual(original.command?.fields, ["expectedUserStatus": .string("0"), "id": .string("17")])']:self.assertIn(value,s)
 def test_authored_tests_cover_real_service_not_live_network(self):
  s=self.text('Tests/CoreTests/ProjectOriginalRequestRecoveryTests.swift')
  self.assertEqual(s.count('func test'),12)
  for v in ['testRestartRestoresPendingBeforeFailedDetailAndReadOnlyGrantRecovers','testLegacyLocalUUIDRemainsLockedAndMakesZeroRecoveryRequests','testRunningAndNotFoundOnlyReadOriginalAndNeverResend','testAccountChangeDuringReadCannotAcknowledgeOldOperation','testReplacedDurableRecordDuringReadCannotConsumeReceipt','testMissingReadGrantNeverSubstitutesSubmitGrant','testAuthorInputDecoratorForwardsOriginalRecoveryWithoutNewOwner']:self.assertIn(v,s)
  self.assertNotIn('URLSession',s)
if __name__=='__main__':unittest.main()
