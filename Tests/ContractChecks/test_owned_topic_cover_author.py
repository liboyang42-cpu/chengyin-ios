"""Offline consumer boundaries and coverage inventory, not Swift execution or provider acceptance."""
from pathlib import Path
import json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class OwnedCoverAuthorContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def test_producer_paths_cannot_use_arbitrary_image_urls(self):
  source=self.read('Core/OwnedTopicCoverClient.swift')
  for path in ['api/topic/cover/upload','api/topic/cover/selection/current','api/topic/cover/selection/status']:self.assertIn(path,source)
  self.assertIn('SHA256.hash(data: bytes)',source)
  self.assertIn('maximumContentBytes = 10 * 1024 * 1024',source)
  self.assertNotIn('URL(string:',source)
  self.assertNotIn('api/common/uploadOSS',source)
 def test_live_composition_is_default_off_and_bounded(self):
  root=self.read('App/AppCompositionRoot.swift');session=self.read('App/AppSession.swift')
  self.assertIn('OwnedTopicCoverApproval? = { _ in nil }',root)
  self.assertIn('nativePicker: Bool = false',self.read('Core/OwnedTopicCoverClient.swift'))
  self.assertIn('makeOwnedTopicCoverTransport(64 * 1024)',session)
  self.assertIn('makeOwnedTopicCoverTransport(OwnedTopicCoverClient.maximumContentBytes)',session)
  self.assertIn('self.projectConfigurationRevision == revision',session)
  self.assertIn('ownedTopicCoverConfigurationRevision() == revision',root)
 def test_picker_reuses_sanitized_selected_only_adapter(self):
  view=self.read('App/OwnedTopicCoverAuthorView.swift')
  for token in ['RetainedNativeImagePicker: OwnedTopicCoverSelecting','selectionApproval:','permitsNativePicker','RetainedImageSanitizer.sanitize(bytes)','renderedAsset == review.command.asset','flow.claimUpload(original)']:self.assertIn(token,view)
  for absent in ['PHPhotoLibrary','URLSession','AsyncImage','Data(contentsOf:']:self.assertNotIn(absent,view)
 def test_journal_keeps_original_unknown_command_and_local_receipt_recovery(self):
  flow=self.read('Core/OwnedTopicCoverAuthorFlow.swift');journal=self.read('Core/OwnedTopicCoverJournal.swift')
  self.assertIn('journal.beginUpload',flow);self.assertIn('journal.beginSelection',flow)
  self.assertIn('source.status(saved.command',flow);self.assertIn('source.select(saved.command',flow)
  self.assertIn('journal.rememberUpload',flow);self.assertIn('journal.rememberSelection',flow)
  self.assertIn('if unsavedUpload != nil { state = .uploadReceiptUnstored; return }',flow)
  self.assertNotIn('jpeg',journal);self.assertNotIn('token',journal)
 def test_native_regressions_cover_real_factory_claim_and_old_presentation(self):
  tests='\n'.join(self.read(p) for p in ['Tests/AppUnitTests/OwnedTopicCoverCompositionTests.swift','Tests/AppUnitTests/OwnedTopicCoverPresentationTests.swift','Tests/CoreTests/OwnedTopicCoverAuthorFlowTests.swift','Tests/CoreTests/OwnedTopicCoverClientTests.swift'])
  for marker in ['testActualFactoryQueuedUploadAfterGrantABA','testHeldActualCloneEmpty401AfterGrantABA','testOldSheetDismissalCannotCloseReplacement','testImageFlowOwnsActualRead','testSelectionReceiptWriteFailureSurvivesReopen','testReceivedReceiptCanRecoverLocally','testReceiptFailureReopenRequiresExplicitCurrentRead']:self.assertIn(marker,tests)
  self.assertEqual(len(re.findall(r'func test\w+\(',tests)),39)
 def test_two_complete_ui_journeys_and_bilingual_keys_are_saved(self):
  for name in ['Selection','Recovery']:
   source=self.read(f'Tests/AppUITests/OwnedTopicCover{name}FlowTests.swift')
   self.assertEqual(len(re.findall(r'func test\w+\(',source)),1)
   for marker in ['900 seconds','ownedCover.choose','ownedCover.upload','ownedCover.confirm','coverSelectCount','coverRequestIDs']:self.assertIn(marker,source)
  fragment=json.loads(self.read('docs/owned-topic-cover-localizations.json'));self.assertEqual(len(fragment),44)
  for key,entry in fragment.items():self.assertTrue(key.startswith('ownedCover.'));self.assertEqual(set(entry),{'en','zh-Hans'})
  fixture=self.read('App/OwnedTopicCoverSynthetic.swift');self.assertTrue(fixture.startswith('#if DEBUG'));self.assertIn('UIGraphicsImageRenderer',fixture)
  self.assertNotIn('OwnedTopicCoverSynthetic',self.read('App/AppSession.swift'))
  author=self.read('App/OwnedTopicCoverAuthorView.swift')
  self.assertIn('.disabled(!flow.canReviewSelection(asset))',author)
  self.assertIn('ownedCover.readForSelection',author)
  self.assertIn('ownedCover.currentRequired',author)
  self.assertEqual(author.count('.disabled(!flow.canReadCurrentDetails)'),2)
  self.assertIn('ownedCover.receiptBeforeCurrent',author)
  self.assertIn('guard flow.canReadCurrentDetails else { return }',author)
  self.assertIn('if flow.hasUnstoredUploadReceipt {',author)
  self.assertIn('if flow.hasUnstoredSelectionReceipt {',author)
  self.assertNotIn('flow.state == .selectionReceiptUnstored',author)
  self.assertNotIn('flow.state == .uploadReceiptUnstored',author)
  flow=self.read('Core/OwnedTopicCoverAuthorFlow.swift')
  self.assertIn('guard isCurrent, !isBusy, !hasUnstoredReceipt, snapshot == original',flow)
  self.assertIn('guard isCurrent, !hasUnstoredReceipt, let saved',flow)
