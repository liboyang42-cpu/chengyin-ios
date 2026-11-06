"""Source-only tag-recovery contracts. No Swift, storage, HTTP or Apple execution claimed."""
from pathlib import Path
import unittest,re
ROOT=Path(__file__).resolve().parents[2]
class PlayTagRevocationRecoveryContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def model(self):return self.read('Core/PlayOperatingSummary.swift')
 def journal(self):return self.read('Core/PlayTagRevocationRecovery.swift')
 def testWriteAheadPersistenceCompletesBeforeOriginalPost(self):
  s=self.model().split('public func revoke(tagID: Int)')[1]
  self.assertLess(s.index('recovery.recordTagRevocation(intent, key: key)'),s.index('service.revokeTag(tagID: tagID, token: session.token)'))
  self.assertIn('recorded = stored; try check(session, generation)',s)
  self.assertIn('guard stored.value == intent',s)
 def testReadRehydratesExactOwnerTopicBeforeAnyNetwork(self):
  s=self.model().split('private func load(reconciling acknowledged:')[1].split('public func revoke')[0]
  self.assertLess(s.index('readTagRevocation(key)'),s.index('service.operatingSystem('))
  self.assertIn('pending.value.validate(session: session, topicID: topicID)',s)
  self.assertIn('unresolvedTagIDs = pending.map { [$0.value.tagID] } ?? []',s)
 def testActiveReadbackNeverClearsOrResends(self):
  s=self.model();self.assertIn('provesRevocationOrAbsence(raw, tagID: pending.value.tagID)',s)
  self.assertIn('guard let tags = raw["tags"].array else { return false }',s)
  self.assertIn('seen.insert(id).inserted else { return false }',s)
  self.assertIn('return seen.contains(tagID) ? status == "REVOKED" : true',s)
  self.assertIn('recovery.readTagRevocation(key) == expected',s)
  self.assertEqual(s.count('service.revokeTag('),1)
  self.assertIn('guard phase == "ready", unresolvedTagIDs.isEmpty',s)
  for token in ['retryTag','retryRevocation','recovery.clearTagRevocation(pending, key: key); try check(session, generation)']:
   if token.startswith('retry'):self.assertNotIn(token,s+self.journal())
   else:self.assertIn(token,s)
 def testOtherViewersCannotClearLiveIntent(self):
  s=self.model()
  self.assertIn('private static var liveRevocations: Set<UUID> = []',s)
  self.assertLess(s.index('Self.liveRevocations.insert(intent.id)'),s.index('recovery.recordTagRevocation(intent'))
  self.assertIn('!Self.liveRevocations.contains(pending.value.id) || acknowledged == pending.value.id',s)
  self.assertIn('defer { if let activeID { Self.liveRevocations.remove(activeID) } }',s)
 def testDefinitiveFailureRequiresExactPersistedClearBeforeUnlock(self):
  s=self.model().split('if let recorded, error is PlayExperienceError')[1]
  self.assertIn('if case PlayExperienceError.rejected = error',s)
  self.assertIn('if case PlayExperienceError.disabled = error',s)
  self.assertLess(s.index('recovery.clearTagRevocation(recorded, key: key)'),s.index('unresolvedTagIDs.remove(tagID)'))
  self.assertIn('catch { fail(error, session, generation); return }',s)
 def testLocalMarkerHasNoCredentialsContentOrNetworkIdempotency(self):
  s=self.journal().split('public struct PlayTagRevocationRecoverySnapshot')[0]
  for token in ['schema','originEpoch','topicID','tagID','owner.matches(session)','expected.utf8.elementsEqual(key.utf8)']:self.assertIn(token,s)
  for token in ['session.token','let token','let tagValue','URLRequest','URLSession','requestId','requestID']:self.assertNotIn(token,s)
 def testDedicatedSlotAndCASPreserveOldSlots(self):
  s=self.read('Core/PlayDurableRecovery.swift')
  for name in ['completion','paused','game']:self.assertIn('binding: key + ":'+name+'"',s)
  self.assertIn('tagRevocation = try PlayEncryptedSlot(binding: key + ":tag"',s)
  ext=s.split('extension PlayDurableRecovery: PlayTagRevocationRecovery')[1].split('private struct PlayEncryptedSnapshot')[0]
  for token in ['guard old.data == nil','generation: snapshot.generation','persistedBytes: data','value.owner == owner','try intent.validate(key: key)']:self.assertIn(token,ext)
  for token in ['completion.write','paused.write','game.write','try?']:self.assertNotIn(token,ext)
 def testNormalFactoryInjectsOriginalConstructionOrExplicitUnavailable(self):
  s=self.read('App/AppSession.swift').split('func playOperatingSummary(topicID: Int)')[1].split('/// P056')[0]
  for token in ['composition.storage.playRecovery.make','recovery: recovery','PlayUnavailableTagRevocationRecovery()','PlayRecoveryAccountRole(rawValue: account.effectiveRole)','role: role.rawValue','matchesContinuationSession(captured, viewerRevision: viewer)', 'suffix: "summary:\\(viewer)"']:self.assertIn(token,s)
  for token in ['PlayMemory','enabled:', 'OperationEndpointApproval','try? composition']:self.assertNotIn(token,s)
 def testUnavailableStorageNeverLooksEmpty(self):
  s=self.journal().split('class PlayUnavailableTagRevocationRecovery')[1].split('/// Synthetic-only')[0]
  self.assertEqual(s.count('throw PlayExperienceError.persistenceUnavailable'),3)
  self.assertNotIn('return nil',s)
 def testOriginalRequestShapeAndServerCapabilityUnchanged(self):
  s=self.read('Core/PlayExperienceService.swift').split('public func revokeTag')[1].split('func scopeFields')[0]
  self.assertIn('postWithoutBody: true, capability: .tags',s)
  self.assertIn('raw["id"].tolerantInteger == tagID, raw["status"].text == "REVOKED"',s)
  for token in ['intent','requestID','UUID','retry']:self.assertNotIn(token,s)
 def testAllThirtyFourNativeRegressionsAreAuthored(self):
  paths=['Tests/CoreTests/PlayTagRevocationRecoveryTests.swift','Tests/CoreTests/PlayOperatingSummaryRecoveryTests.swift','Tests/AppUnitTests/PlayTagRevocationCompositionTests.swift']
  values=[self.read(p) for p in paths]
  self.assertEqual([len(re.findall(r'func test',s)) for s in values],[19,12,3])
  for token in ['testRestartWithActiveReadbackRemainsUnknownAndNeverResends','testOtherViewerCannotClearLiveWriteEvenIfItsReadOmitsTag','testIdentityChangesAfterDurableRecordCannotSendOldRequest']:self.assertIn(token,values[1])
  self.assertIn('sessionDependencies: { _ in .dormant }',values[2])
 def testExistingVisibleRecoveryContractStillUsesOriginalCoordinator(self):
  s=self.read('App/PlayOperatingSummaryPresentation.swift')
  self.assertIn('await model.load()',s);self.assertIn('await model.revoke(tagID: value.tagID)',s)
  self.assertIn('model.unresolvedTagIDs.isEmpty',s)
  self.assertNotIn('unresolvedTagIDs.remove',s)
if __name__=='__main__':unittest.main()
