"""Source and wiring checks, not Swift compilation, XCTest, MapKit or visual execution."""
from pathlib import Path
import json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class PlayOperatingSummaryLifecycleContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def owner(self):return self.read('App/PlayOperatingSummaryPresentation.swift')
 def view(self):return self.read('App/PlayPreferenceViews.swift').split('@MainActor struct PlayOperatingSummaryView:')[1]
 def testSourceFencesOwnerExactReadSnapshotAndRetainedFactory(self):
  s=self.owner()
  for token in ['PlayExperiencePresentationKey(model: runtime)','private let interaction: PlayInteractionContext','runtime.interactionContext == interaction','runtime.snapshot == snapshot','ObjectIdentifier(summary) == coordinator','currentSummary() === summary','snapshot.result.topicID == summary.topicID']:
   self.assertIn(token,s)
 def testExistingBeforeCompletionNavigationAndPrivateTitleRemain(self):
  s=self.read('App/PlayExperienceView.swift')
  self.assertIn('NavigationLink("playx.os.title")',s)
  self.assertIn('source.accepts(model, summary: summary, currentSummary: { factory(topicID) })',s)
  self.assertIn('.accessibilityIdentifier("playx.os.open")',s)
  self.assertNotIn('availability == .completed',self.owner())
  old=self.read('Tests/AppUITests/PlayPreferenceFlowTests.swift')
  self.assertIn('testOperatingSummaryIsSeparatePrivateDestination',old)
  self.assertIn('"preference", "-AppleLanguages"',old)
 def testViewRequiresScopedOwnerAndNeverReadsRetainedSummaryDirectly(self):
  s=self.view()
  self.assertIn('sourceIsCurrent: @escaping @MainActor () -> Bool = { false }',s)
  self.assertIn('@State private var sourceIsCurrent:',s)
  self.assertIn('_sourceIsCurrent = State(initialValue: sourceIsCurrent)',s)
  self.assertIn('presentation.displayedSummary(model: model, current: sourceIsCurrent)',s)
  for token in ['model.summary','await model.load()', 'await model.revoke(']:self.assertNotIn(token,s)
 def testEveryReadClearsVisibleDataAndCancelsOlderPublication(self):
  s=self.owner()
  for token in ['task?.cancel(); generation = UUID(); let stamp = generation','summary = nil; review = nil; loading = true','await withTaskCancellationHandler','onCancel: { work.cancel() }','guard generation == stamp','!work.isCancelled','model.summary == summary']:
   self.assertIn(token,s)
 def testFailureAndChangedSourceCannotPublishRetainedPrivateRows(self):
  s=self.owner()
  for token in ['guard active, !loading, current()','model.issue == nil','model.phase == "ready" || model.phase == "unknown"','let received = model.summary, received.topicID == model.topicID']:
   self.assertIn(token,s)
 def testSceneCloseAndRevocationClearDisplayAndConfirmation(self):
  s=self.view()
  for token in ['if scenePhase != .active { Color.clear }','else if !sourceIsCurrent()','PlayExperienceIssueView(issue: .staleSession)','.onDisappear { confirm = false; presentation.retire() }','if next != .active { confirm = false; presentation.retire() }','if !current { confirm = false; presentation.retire() }']:
   self.assertIn(token,s)
 def testConfirmationBindsReadModelAndTagAndConsumesBeforeSuspension(self):
  s=self.owner()
  for token in ['guard review == value else { return }', 'guard value.read == generation','value.model == ObjectIdentifier(model)','model.unresolvedTagIDs.isEmpty','displayed.tags.contains(where: { $0.id == value.tagID && !$0.revoked })','await model.revoke(tagID: value.tagID)']:
   self.assertIn(token,s)
  start=s.index('func revoke(');end=s.index('private func perform',start);body=s[start:end]
  self.assertLess(body.index('review = nil'),body.index('await perform('))
 def testRetirementCannotUnlockUnknownWritesOrMintAuthority(self):
  s=self.owner();retire=s.split('func retire() {')[1].split('func displayedSummary')[0]
  for token in ['summary = nil; review = nil','task?.cancel()']:self.assertIn(token,retire)
  for token in ['unresolvedTagIDs.remove', 'unresolvedTagIDs =', '.load(', '.revoke(']:self.assertNotIn(token,retire)
  for token in ['PlayExperienceService(', 'OperationEndpointApproval(', 'URLSession', 'UserDefaults', '.enabled =']:
   self.assertNotIn(token,s+self.view())
 def testOriginalTagCapabilityAndUnknownReadbackContractRemain(self):
  service=self.read('Core/PlayExperienceService.swift');model=self.read('Core/PlayOperatingSummary.swift')
  self.assertIn('postWithoutBody: true, capability: .tags',service)
  self.assertIn('unresolvedTagIDs.insert(tagID); phase = "submitting"',model)
  self.assertIn('value.tags.contains { $0.id == id && !$0.revoked }',model)
 def testOriginalMapHasNoLocationLayerAndNoDuplicateIDCollapse(self):
  s=self.read('App/PlayPreferenceOriginalSummaryContent.swift')
  self.assertIn('interactionModes: [.pan, .zoom]',s);self.assertIn('ForEach(Array(anchors.enumerated()), id: \\.offset)',s)
  self.assertIn('.privacySensitive()',s);self.assertIn('.excludingAll',s)
  for token in ['UserAnnotation','CLLocationManager','requestWhenInUseAuthorization','UserDefaults','summaryFactory']:
   self.assertNotIn(token,s)
 def testAllUsedSummaryLabelsHaveBothExistingTranslations(self):
  s=self.view()+self.read('App/PlayPreferenceOriginalSummaryContent.swift')
  names=set(re.findall(r'(?:Text|Button|Section|ProgressView|navigationTitle|confirmationDialog)\("(playx\.[A-Za-z.]+)"',s))
  catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
  for name in names:
   for language in ['en','zh-Hans']:self.assertTrue(catalog[name]['localizations'][language]['stringUnit']['value'])
 def testTwelveRealServiceRegressionsAreAuthored(self):
  s=self.read('Tests/AppUnitTests/PlayOperatingSummaryPresentationTests.swift')
  self.assertEqual(len(re.findall(r'func test',s)),12)
  for token in ['PlayExperienceService(configuration:','PlayOperatingSummaryCoordinator','PlayExperienceCoordinator','nextFailure','suspendNext','testCancelledWritePreservesUnknown','testEqualSnapshotRefresh','testUncompletedNormalRoute']:
   self.assertIn(token,s)
if __name__=='__main__':unittest.main()
