"""Focused source contract only. Not Swift compilation or runtime proof."""
from pathlib import Path
import json, unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
class PublishReceiptSourceChecks(unittest.TestCase):
    def test_receipt_is_publish_only_and_separate(self):
        source = read('Core/TemplateAuthoringPublishReceipt.swift')
        for token in ['struct TemplateAuthoringPublishReceipt: Codable, Equatable', 'request.path == "/api/template/publish"', 'response["data"]?.integer', 'pending.savedDraft == nil', 'pending.publishedReceipt == self', 'requestHash == ProjectStoryImageTarget.hash(data)']:
            self.assertIn(token, source)
        self.assertNotIn('typealias TemplateAuthoringPublishReceipt', source)
    def test_existing_adapter_authority_remains_closed_and_single_send(self):
        source = read('Core/TemplateAuthoringService.swift')
        self.assertIn('transport: (any TemplateAuthoringTransport)? = nil', source)
        self.assertIn('transport?.authority == .injectedHTTP', source)
        submit = source.split('public func submitWithReceipt')[1]
        self.assertEqual(submit.count('transport.send(request)'), 1)
        self.assertIn('try TemplateAuthoringContract.requireSuccess(data, httpStatus: status)', submit)
        self.assertIn('outcome == .acknowledged ? try? TemplateAuthoringPublishReceipt.responseID', submit)
    def test_optional_atomic_journal_and_readback(self):
        source = read('Core/TemplateAuthoringStorage.swift')
        self.assertIn('publishedReceipt: TemplateAuthoringPublishReceipt? = nil', source)
        self.assertIn('value.savedDraft != nil || value.publishedReceipt != nil', source)
        self.assertIn('pending(session: session, identity: value.identity) == value', source)
        coordinator = read('Core/TemplateAuthoringCoordinator.swift')
        self.assertIn('terminal.publishedReceipt = try .init', coordinator)
        self.assertEqual(coordinator.count('try store.savePending(terminal, session: session)'), 1)
    def test_normal_entry_keeps_draft_flow_and_excludes_project_return(self):
        host, launch = read('App/TemplateAuthoringView.swift'), read('App/TemplateAuthoringLaunchView.swift')
        self.assertEqual(host.count('TemplateAuthoringPublishResultPreferenceKey.self'), 1)
        self.assertIn('TemplateAuthoringPublishResultObservation.capture(model: model, eligible: onSavedDraft == nil)', host)
        self.assertEqual(launch.count('TemplateAuthoringSaveFlow('), 1)
        self.assertEqual(launch.count('TemplateAuthoringPublishCompletion('), 1)
        self.assertEqual(launch.count('session.templateAuthoringEditor()'), 1)
        self.assertEqual(launch.count('TemplateAuthoringMineView('), 2)
    def test_fresh_visit_clock_and_retirement(self):
        source = read('App/TemplateAuthoringPublishFlow.swift')
        for token in ['latest.state == .editing', 'latest.editableNow()', 'self.generation == value.generation', 'value.signal.isCurrent()', 'value.signal.result.isCurrent(in: self.coordinator)', 'func retire() { suspend(); latest = nil; admitted = nil }', 'TemplateAuthoringSaveFlowController.liveSchedule', 'controller.retire()', 'controller.suspend()']:
            self.assertIn(token, source)
        self.assertNotIn('URLSession', source)
    def test_five_explicit_bilingual_keys_and_review_semantics(self):
        catalog = json.loads(read('Resources/CreatorPublishResult.xcstrings'))['strings']
        self.assertEqual(len(catalog), 5)
        for row in catalog.values(): self.assertEqual(set(row['localizations']), {'en','zh-Hans'})
        self.assertIn('review', catalog['templatePublishResult.detail']['localizations']['en']['stringUnit']['value'])
        panel = read('App/TemplateAuthoringPublishResultPresentation.swift')
        self.assertEqual(panel.count('tableName: "CreatorPublishResult"'), 5)
        for key in catalog: self.assertIn('"'+key+'"', panel)
if __name__ == '__main__': unittest.main()
