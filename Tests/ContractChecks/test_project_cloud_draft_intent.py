"""Source-contract checks only. Does not execute Swift, iOS, HTTP, or a server writer."""
import json, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class ProjectCloudDraftIntentContracts(unittest.TestCase):
 def text(self, path): return (ROOT/path).read_text()
 def test_three_intents_share_one_original_payload(self):
  s=self.text('Core/ProjectEditSubmissionIntent.swift')
  for x in ['case ordinary','case saveCloudDraft','case submitServerDraft','payload["saveDraft"] == .number(1)','payload["saveDraft"] == .number(0)','ProjectEditValidation.issues(draft, scope: scope, baseline: baseline)']: self.assertIn(x,s)
  for x in ['URLRequest','URLSession','OperationEndpointApproval','savePending']: self.assertNotIn(x,s)
 def test_missing_completeness_only_is_optional(self):
  s=self.text('Core/ProjectEditSubmissionIntent.swift')
  self.assertIn('guard self == .saveCloudDraft, scope == .full else { return all }',s)
  self.assertIn('draft.startDate.isEmpty && (baseline?.draft.startDate.isEmpty ?? true)',s)
  self.assertIn('return all.filter { !absent.contains($0.id) }',s)
  for x in ['"name"','"dateOrder"','"coordinates"','"references"','"price"','"completionRules"','"recruitmentCarryOver"']: self.assertNotIn('absent.insert('+x+')',s)
 def test_original_pending_material_contract_is_not_rewritten(self):
  s=self.text('Core/ProjectEditDraft.swift');self.assertNotIn('intent: ProjectEditSubmissionIntent',s)
  self.assertNotIn('publishReadiness.pendingMaterials',s)
  tests=self.text('Tests/CoreTests/ProjectEditPendingMaterialsTests.swift')
  self.assertIn('XCTAssertEqual(after, before); XCTAssertNil(after["pendingMaterials"])',tests)
 def test_server_draft_fact_is_optional_strict_and_current(self):
  s=self.text('Core/ProjectEditContract.swift')
  for x in ['public var isServerDraft: Bool?', 'if case .bool(let value)? = body["isDraft"]', 'body["isDraft"] == nil || body["isDraft"] == .null','else { throw ProjectEditError.invalidContract }','topicID == nil || baseline?.isServerDraft == true']: self.assertIn(x,s)
  http=self.text('Core/ProjectEditHTTPService.swift')
  self.assertIn('fresh.snapshot == baseline',http);self.assertIn('operation.baseline?.isServerDraft == true',http)
 def test_cloud_save_never_broadcasts_and_keeps_original_routes(self):
  c=self.text('Core/ProjectEditContract.swift');story=self.text('Core/ProjectEditStoryContract.swift')
  self.assertIn('intent != .saveCloudDraft && topicID == nil && draft.publishToCreative',c)
  self.assertIn('if editing && (payload["saveDraft"] == .number(1) || payload["saveDraft"] == .number(0)) { return updatePath }',story)
  self.assertIn('!chapters.isEmpty || payload["saveDraft"] == .number(1)',story)
 def test_wire_rejects_unknown_flags_and_submit_without_existing_id(self):
  for name, source in [('Core/ProjectEditStoryContract.swift','payload'),('App/ProjectEditCompositionRoute.swift','fields')]:
   s=self.text(name)
   self.assertIn('value == .number(1) || value == .number(0)',s)
   self.assertIn(source+'["publishToCreative"] == .number(0)',s)
   self.assertIn('if value == .number(0)',s)
 def test_cloud_quota_handling_does_not_install_permissions(self):
  s=self.text('Core/ProjectEditHTTPService.swift')
  self.assertIn('== .saveCloudDraft || fresh.capability.allowsCreate',s)
  self.assertIn('path: path)',s);self.assertIn('path: ProjectEditRequestContract.submitPath)',s)
  self.assertIn('routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]',self.text('Core/BusinessRuntimeConfiguration.swift'))
 def test_exact_request_is_saved_before_transport(self):
  s=self.text('Core/ProjectEditHTTPService.swift').split('public func submit(',1)[1].split('static func decodeAcknowledgment',1)[0]
  self.assertLess(s.index('dispatched.serverRequest = envelope'),s.index('try store.savePending(dispatched'))
  self.assertLess(s.index('try store.savePending(dispatched'),s.index('transport.send(request)'))
  self.assertIn('ProjectEditLocalStore.exactPending(saved, dispatched)',s)
 def test_reentry_and_result_reads_do_not_resend(self):
  s=self.text('Core/ProjectEditCoordinator.swift').split('public func load() async',1)[1].split('public func restoredDraft',1)[0]
  self.assertLess(s.index('pending = try store.pending'),s.index('await service.preflight'))
  for x in ['service.submit','clearPending','retrySameRequest']: self.assertNotIn(x,s)
  retry=self.text('Core/ProjectEditHTTPService.swift').split('public func retrySameRequest(',1)[1].split('public func resumePostProcessing',1)[0]
  self.assertIn('terminalReceipt(operation: operation',retry);self.assertNotIn('submit(',retry)
 def test_known_cloud_fact_is_owner_bound_and_not_published_handoff(self):
  c=self.text('Core/ProjectEditCoordinator.swift');s=self.text('App/ProjectEditView.swift')
  self.assertIn('capturedSession == currentSession() && pending?.ownerKey == currentSession()?.ownerKey && pending?.serverRequestCommitted == true && pending?.payload["saveDraft"] == .number(1)',c)
  self.assertIn('coordinator.state == .acknowledged && !coordinator.savedCloudDraft',s)
  self.assertIn('if operation.serverRequestCommitted == true',c)
  http=self.text('Core/ProjectEditHTTPService.swift')
  self.assertIn('bundle.reviewState != "DRAFT" || bundle.published',http)
  self.assertIn('operation.payload["saveDraft"] == .number(0), bundle.reviewState == "DRAFT"',http)
 def test_intent_review_reuses_immutable_original_capture(self):
  s=self.text('App/ProjectEditView.swift')
  for x in ['guard let lease = currentReviewLease() else { return }','coordinator.prepare(draft, intent: intent)','guard currentReviewLease() == lease else { cancelReview(); return }','guard reviewIsCurrent(value), canEdit, !busy else { return }']: self.assertIn(x,s)
  form=self.text('App/ProjectEditDetailForms.swift')
  self.assertIn('ProjectCloudDraftIntentSummary(intent: confirmation.intent)',form)
  self.assertIn('confirmation.intent == .ordinary || canSimulate',form)
  self.assertIn('Button(action: confirm)',form)
 def test_three_choices_keep_existing_busy_and_lease_fences(self):
  s=self.text('App/ProjectEditView.swift')
  for x in ['model.saveLocal()','model.review()','model.review(intent: .saveCloudDraft)','model.review(intent: .submitServerDraft)']:self.assertIn(x,s)
  self.assertEqual(s.count('.disabled(!model.canReview)'),3)
  self.assertIn('.disabled(!model.canSaveLocal)',s)
 def test_cloud_and_unknown_receipts_remain_outside_detail_dependency(self):
  s=self.text('App/ProjectEditView.swift')
  for x in ['            if model.coordinator.savedCloudDraft {','            if model.coordinator.isLocked {','            if model.coordinator.hasCommittedRequestReceipt {']:self.assertIn(x,s);self.assertNotIn('    '+x,s)
  self.assertIn('ProjectCloudDraftProcessingFacts(receipt: model.coordinator.pending?.postProcessing)',s)
  self.assertIn('NavigationLink { cloudDraftProjectsHost() }',s)
 def test_primary_hosts_use_existing_my_projects_route(self):
  for path in ['App/ProjectEditLaunchView.swift','App/SessionPublishingModesView.swift']:
   self.assertEqual(self.text(path).count('cloudDraftProjectsHost: { AnyView(SessionCreatorProjectsView(session: session)) }'),2)
 def test_presentation_has_bilingual_strings_and_no_writer(self):
  s=self.text('App/ProjectCloudDraftReceiptPresentation.swift')
  for x in ['URLSession','URLRequest','AsyncImage','Task {','savePending','OperationEndpointApproval']:self.assertNotIn(x,s)
  strings=json.loads(self.text('Resources/ProjectCloudDraftReceipt.xcstrings'))['strings']
  for row in strings.values():
   self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
   for locale in row['localizations'].values():self.assertTrue(locale['stringUnit']['value'].strip())
 def test_memory_transport_and_original_ui_flow_tests_are_authored(self):
  core=self.text('Tests/CoreTests/ProjectCloudDraftIntentTests.swift');app=self.text('Tests/AppUnitTests/ProjectCloudDraftReviewFlowTests.swift')
  self.assertEqual(core.count('func test'),12);self.assertEqual(app.count('func test'),5)
  for s in [core,app]:self.assertNotIn('URLSession',s);self.assertIn('ProjectEditHTTPService',s)
  for x in ['testLostResponseRestartUsesOnlyOriginalReadAndRetainsCloudFactOnLaterFailure','testCloudReceiptIsHiddenAfterAccountSwitchAndOldDurableRecordRemains']:self.assertIn(x,core)
  for x in ['testIntentChangeInvalidatesOldSheetAndKeepsNewImmutableCloudPayload','testRestartReadRecoversCloudSaveWithoutAutomaticSubmitOrPublicationHandoff']:self.assertIn(x,app)
if __name__=='__main__': unittest.main()
