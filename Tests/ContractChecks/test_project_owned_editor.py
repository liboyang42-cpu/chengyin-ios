"""Supplementary source checks; Swift model and UI methods require Apple execution."""
from pathlib import Path
import json, re, unittest
ROOT=Path(__file__).resolve().parents[2]
class ProjectOwnedEditorContracts(unittest.TestCase):
    def read(self,path): return (ROOT/path).read_text()
    def test_normal_owned_list_detail_and_submit_status_routes(self):
        self.assertIn('SessionCreatorProjectsView(session: session)',self.read('App/AccountView.swift'))
        self.assertIn('SessionCreatorProjectsView(session: session)',self.read('App/SessionPublisherLifecycleView.swift'))
        self.assertIn('SessionCreatorProjectsView(session: session)',self.read('App/ProjectEditLaunchView.swift'))
        host=self.read('App/ProjectOwnedContentViews.swift')
        for token in ['ProjectEditRemoteTarget(project: value.project, readerScope: value.scope)','ProjectRemoteEditorDestination','reader.scope == target.readerScope','session.projectEditor(target: $0)','TopicDetailView']:
            self.assertIn(token,host)
    def test_rows_capture_original_scope_before_dispatch(self):
        ui=self.read('App/CreatorContentViews.swift')
        for token in ['let rowScope = key.scope','reader.scope == rowScope','rows.contains(project)','onOpenProject(project, rowScope)']:
            self.assertIn(token,ui)
    def test_factory_uses_no_derived_mode_or_version(self):
        source=self.read('App/AppSession.swift').split('func projectEditor(target:')[1].split('private func projectEditorService')[0]
        for token in ['creatorContentReader.scope == target.readerScope','topicID: target.topicID','currentProjectEditSession','retainedProjectEditors[key]']:
            self.assertIn(token,source)
        self.assertNotIn('product: target',source); self.assertNotIn('baseRevision =',source)
        target=self.read('Core/ProjectEditRemoteTarget.swift')
        self.assertIn('case "member": owner = .personal',target); self.assertIn('case "merchant": owner = .merchant',target)
        self.assertIn('default: return nil',target)
        list_source=self.read('App/CreatorContentViews.swift')
        self.assertLess(list_source.index('var onOpenProject:'),list_source.index('let onOpen:'))
    def test_explicit_completed_only_continuation_and_old_capture_fences(self):
        source=self.read('Core/ProjectEditCoordinator.swift').split('public var canContinueAcknowledged')[1].split('public func checkOutcome')[0]
        for token in ['state == .acknowledged','initial.topicID != nil','pending?.serverAcknowledged == true','capture.generation == generation','capture.session == capturedSession','guard active(session, stamp)','store.advanceAcknowledged','state = .blocked']:
            self.assertIn(token,source)
        self.assertNotIn('service.submit',source)
    def test_baseline_saved_before_exact_completed_record_clear(self):
        source=self.read('Core/ProjectEditLocalStore.swift').split('public func advanceAcknowledged')[1].split('public static func exactPending')[0]
        self.assertLess(source.index('try save('),source.index('try clearPending('))
        self.assertEqual(source.count('Self.exactPending(current, expected)'),2)
        self.assertGreaterEqual(source.count('isCurrent()'),3)
        self.assertEqual(source.count('storedPendingMatches(expected, session: session)'),2)
        self.assertIn('throw ProjectEditContinuationFailure.baselineSaved',source)
        self.assertIn('encoder.outputFormatting = [.sortedKeys]',self.read('Core/ProjectEditLocalStore.swift'))
    def test_shared_controller_and_model_fence_retained_dismissals(self):
        host=self.read('App/ProjectOwnedContentViews.swift')
        for token in ['navigation.presentation(presented)','selection?.id == original.id','navigation.retire(scope: original)']:
            self.assertIn(token,host)
        model=self.read('App/ProjectEditView.swift')
        for token in ['var canEdit: Bool { ownsVisit','!leftBeforeInitialLoad','guard ownsVisit else { return }','guard generation == stamp, ownsVisit','if ownsVisit { coordinator.cancelReview() }']:
            self.assertIn(token,model)
    def test_read_only_transport_and_unknown_receipt_contract_unchanged(self):
        service=self.read('Core/ProjectEditHTTPService.swift')
        self.assertIn('approval.allows',service); self.assertIn('dispatchStarted == true { return .unknown }',service)
        self.assertIn('terminalReceipt(operationID:',service)
        target=self.read('App/ProjectOwnedContentFixture.swift')
        self.assertTrue(target.startswith('#if DEBUG')); self.assertTrue(target.strip().endswith('#endif'))
        self.assertNotIn('URLSession',target)
        ui=self.read('App/ProjectEditView.swift')
        self.assertIn('if model.coordinator.canSimulate {',ui)
        self.assertIn('projectRemote.unknownNoReceipt',ui)
        mode=self.read('App/ProjectEditModeReviewController.swift')
        self.assertIn('controller.presentation?.id == original.id',mode)
        self.assertIn('copy?.id == original.id, context == original.context',mode)
        self.assertIn('copy = nil; presentation = nil',mode)
        self.assertIn('copyForMode(original.draft, to: original.product)',mode)
    def test_bilingual_fragment_and_authored_regressions(self):
        strings=json.loads(self.read('Resources/ProjectOwnedContentLocalizations.fragment.json'))['strings']
        self.assertEqual(len(strings),13)
        for entry in strings.values(): self.assertEqual(set(entry['localizations']),{'en','zh-Hans'})
        for path,count in [('Tests/CoreTests/ProjectEditRemoteTests.swift',11),('Tests/AppUnitTests/ProjectOwnedEditorTests.swift',15),('Tests/AppUITests/ProjectOwnedEditorFlowTests.swift',3),('Tests/AppUITests/ProjectOwnedModeCopyFlowTests.swift',1)]:
            self.assertEqual(len(re.findall(r'func test\w+',self.read(path))),count)
if __name__=='__main__': unittest.main()
