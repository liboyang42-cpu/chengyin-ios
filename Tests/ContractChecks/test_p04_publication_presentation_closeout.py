"""P04 source-level presentation and authority checks. Not a Swift/runtime test."""
from pathlib import Path
import json
import re
import unittest
ROOT=Path(__file__).resolve().parents[2]
LEAVES=['ApprovedMerchantReviewSourceSection','ApprovedReleasePublicationConfirmationView','ApprovedReleaseSummarySection','ApprovedTopicReviewObservationSection','ApprovedTopicReviewRequestView','ApprovedTopicReviewSummarySection','ApprovedTopicSelectedCoverSection']
class P04PublicationPresentationCloseoutTests(unittest.TestCase):
    def source(self, name):return (ROOT/'App'/(name+'.swift')).read_text()
    def contains(self, name, values):
        for value in values:self.assertIn(value,self.source(name))
    def testExistingEditorStillOwnsNormalReviewAndPublicationEntrypoints(self):
        self.contains('ProjectEditView',['ApprovedReleasePreparationView(original: original) { approvedRelease.close(original) }','if reviewRequest.isPresented(original) { ApprovedTopicReviewRequestView(original: original) { reviewRequest.close(original) } }'])
        self.contains('ApprovedReleasePreparationView',['ApprovedReleasePublicationConfirmationView(original: captured, cancel: model.cancel, confirm: model.confirm)'])
    def testHelpersContainOnlyPresentation(self):
        source=self.source('PublisherLifecycleHostHooks').split('// P04 presentation only.')[1]
        for value in ['.listStyle(.insetGrouped)','.font(Theme.Font.body)','.tint(Theme.Color.accent(in: domain))','.background(Theme.Color.bgPage(in: domain))','func p04FactRow()','func p04RecoveryRecord()']:self.assertIn(value,source)
        for value in ['Task','@State','onAppear','onDisappear','URLRequest','coordinator','grant:','journal:','.disabled(','.id(']:self.assertNotIn(value,source)
    def testPublishConfirmationStillUsesExactCapturedConfirmation(self):
        self.contains('ApprovedReleasePublicationConfirmationView',['let original: ApprovedTopicReleasePublishFlow.Confirmation','ApprovedReleaseSummarySection(prepared: original.prepared, identifierPrefix: "approvedRelease.confirm")','{ confirm(original) }','{ cancel(original) }','.onDisappear { cancel(original) }','.buttonStyle(.borderedProminent)','.frame(maxWidth: .infinity, minHeight: 44)'])
    def testReviewModelKeepsExactReceiptAndRetryFences(self):
        self.contains('ApprovedTopicReviewRequestView',['guard !isWorking, flow.canReadStatus, flow.snapshot == original else','guard !isWorking, flow.canRetryExact, flow.snapshot == original else','guard !isWorking, flow.canObserve, flow.snapshot == original else','guard owns(original), let claim = flow.claim(original) else','confirmation?.id == original.id && flow.confirmation?.id == original.id && flow.isCurrent'])
    def testRecoveryControlsRemainExplicitAndCapabilityBound(self):
        self.contains('ApprovedTopicReviewRequestView',['{ model.check(captured) }','.disabled(!flow.canReadStatus)','if captured.current?.receipt == nil','{ model.retry(captured) }','.disabled(!flow.canRetryExact)','topicReview.recoveryUnavailable','topicReview.changed','.onDisappear { original.flow.close() }'])
    def testReviewObservationDoesNotImplyApprovalOrPublication(self):
        self.contains('ApprovedTopicReviewObservationSection',['topicReview.currentNotice','topicReview.currentDifferent','topicReview.currentFailed','{ model.observe(original) }','.disabled(!model.flow.canObserve)','switch model.flow.observation'])
    def testCoverReadRetainsSeparateMediaGrantAndCapturedLifetime(self):
        self.contains('ApprovedTopicSelectedCoverSection',['if !cover.permitsReviewRequest','topicReview.coverSelection.notLoaded','imageController.open(asset: cover.ownedAsset, session: session, source: source, parentCurrent: parentCurrent)','.disabled(!parentCurrent() || !source.permits(.readAsset, session: session))','.onDisappear { if let originalImage { imageController.close(originalImage) } }'])
    def testMerchantSelectionRemainsOwnedByOriginalPresentation(self):
        self.contains('ApprovedMerchantReviewSourceSection',['model.selectSource(choice, from: presentation)','model.flow.selectedSources[group.memberTemplateID] == choice.selection','topicReview.sources.older','.p04RecoveryRecord()'])
    def testSummaryFactsRemainVerbatimSelectableAndWrap(self):
        for name in ['ApprovedReleaseSummarySection','ApprovedTopicReviewSummarySection','ApprovedTopicReviewObservationSection','ApprovedTopicSelectedCoverSection']:
            source=self.source(name);self.assertIn('.p04FactRow()',source);self.assertIn('.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)',source)
        self.contains('ApprovedReleaseSummarySection',['Text(verbatim: block.content ?? "").fixedSize(horizontal: false, vertical: true)'])
    def testOriginalLocalizedLabelsAndWarningsResolveInBothLanguages(self):
        keys=set()
        for name in LEAVES:
            for match in re.finditer(r'LocalizedStringResource\("([^"\\]+)",\s*defaultValue:\s*"(?:\\.|[^"\\])*"(?:,\s*table:\s*"([^"\\]+)")?,\s*locale: locale\)',self.source(name)):
                keys.add((match[2] or 'Localizable',match[1]))
        self.assertEqual(len(keys),109)
        catalogs={table:json.loads((ROOT/'Resources'/(table+'.xcstrings')).read_text())['strings'] for table,_ in keys}
        for table,key in keys:
            for lang in ['en','zh-Hans']:
                unit=catalogs[table][key]['localizations'][lang]['stringUnit'];self.assertEqual(unit['state'],'translated');self.assertTrue(unit['value'].strip())
    def testReviewLoadingAndConfirmationHostKeepOriginalIdentity(self):
        self.contains('ApprovedTopicReviewRequestView',['if original.flow.isCurrent','if model.isWorking','.task(id: original.id) { await model.load() }','.sheet(item: model.binding(confirmation))','if model.owns(captured)','confirm: { model.confirm(captured) }, cancel: { model.cancel(captured) }'])
    def testStyleHelpersHaveSingleDefinition(self):
        source='\n'.join(p.read_text() for p in (ROOT/'App').glob('*.swift'))
        for value in ['struct P04LifecycleSurface: ViewModifier','func p04LifecycleSurface()','func p04FactRow()','func p04RecoveryRecord()']:self.assertEqual(source.count(value),1)
if __name__=='__main__':unittest.main()
