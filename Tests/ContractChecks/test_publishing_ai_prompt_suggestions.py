"""Narrow source assertions. This is not a Swift compiler or UI runtime."""
from pathlib import Path
import json,unittest
R=Path(__file__).resolve().parents[2]
def read(p):return (R/p).read_text()
class PublishingAIPromptChecks(unittest.TestCase):
 def test_source_supported_local_suggestions_and_bilingual_values(self):
  c=read('Core/PublishingAIPromptSuggestion.swift');r=json.loads(read('Resources/CreatorAIPrompts.xcstrings'))['strings']
  self.assertEqual(len(r),4);self.assertTrue(all(set(v['localizations'])=={'en','zh-Hans'} for v in r.values()))
  for key,value in r.items():
   if key.endswith('.title'):continue
   for language in ['en','zh-Hans']:self.assertIn('"'+value['localizations'][language]['stringUnit']['value']+'"',c)
  for key in ['oldTown','familyWeekend','rainyDay']:self.assertIn(key,c)
 def test_flow_admission_guards_local_only_and_existing_candidate(self):
  s=read('Core/PublishingAIDraftFlow.swift');part=s[s.index('    public var canUseIdeaSuggestion:'):s.index('    public var canGenerate:',s.index('    public var canUseIdeaSuggestion:'))]
  for token in ['!closed, !ownerRetired, !busy','guard isCurrent','storedCandidate == nil','Data(self.idea.utf8) == original','self.generation == stamp','self.ideaSuggestionRevision == revision','self.messageKey = nil; self.serverMessage = nil'] :self.assertIn(token,part)
  for forbidden in ['client.generate','loadQuota()','close()','accept(']:self.assertNotIn(forbidden,part)
  self.assertNotRegex(part,r'stored(?:Candidate|Quota)\s*=(?!=)')
 def test_normal_host_entry_and_stable_form_lifetime(self):
  h=read('App/PublishingAIDraftSheet.swift');v=read('App/PublishingAIPromptControls.swift')
  self.assertEqual(h.count('PublishingAIPromptControls(controller:'),1);self.assertEqual(h.count('.modifier(PublishingAIPromptLifetime('),1)
  self.assertIn('}.navigationTitle("contextPublish.ai.title")\n            .modifier(PublishingAIPromptLifetime(',h)
  row=v[v.index('@MainActor struct PublishingAIPromptControls:'):v.index('@MainActor struct PublishingAIPromptLifetime:')]
  for bad in ['onDisappear','onAppear','@StateObject','scenePhase','.sheet(']:self.assertNotIn(bad,row)
  self.assertIn('if flow.candidate == nil',row);self.assertIn('.buttonStyle(.borderless)',row)
  self.assertIn('token == self.generation',v);self.assertIn('controller.retire()',v);self.assertIn('.focused($ideaFocused)',h)
 def test_generate_quota_and_candidate_entry_stay_normal(self):
  h=read('App/PublishingAIDraftSheet.swift')
  for token in ['await model.flow.generate()','PublishingAIQuotaSection(flow: model.flow)','model.flow.accept(candidateGeneration: candidateGeneration)','await model.flow.loadQuota()','model.flow.close()']:self.assertIn(token,h)
  self.assertIn('tableName:"CreatorAIPrompts"',read('App/PublishingAIPromptControls.swift'))
if __name__=='__main__':unittest.main()
