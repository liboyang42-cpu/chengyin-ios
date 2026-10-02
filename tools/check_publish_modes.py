#!/usr/bin/env python3
"""Supplementary source assertions; never Swift compilation or runtime evidence."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'app-audit/lib'
class PublishingSourceChecks(unittest.TestCase):
 def test_exact_management_paths_are_source_backed(self):
  swift=(ROOT/'Core/PublishModesContracts.swift').read_text(); dart=(SOURCE/'data/models/my_project.dart').read_text()
  for path in re.findall(r'path = "(api/[^"]+)"',swift): self.assertIn('/'+path,dart)
 def test_read_paths_are_source_backed(self):
  swift=(ROOT/'Core/PublishModesContracts.swift').read_text()
  dart='\n'.join(p.read_text() for p in (SOURCE/'data/api').glob('*.dart'))
  for path in re.findall(r'path: "(api/[^"]+)"',swift): self.assertIn('/'+path,dart)
 def test_current_simple_page_hands_off(self):
  dart=(SOURCE/'feature/publish/publish_page.dart').read_text()
  self.assertIn("publishMode = 'ai_simple'",dart); self.assertIn("context.push('/publish/pro?mode=",dart)
  swift=(ROOT/'Core/PublishModesDomain.swift').read_text(); self.assertIn('professionalSeed',swift); self.assertIn('.string("ai_simple")',swift)
 def test_collaborators_field_does_not_use_pro_name(self):
  swift=(ROOT/'Core/PublishModesDomain.swift').read_text(); section=swift.split('public struct ActivityPublishDraft')[1].split('public struct PublishingTopicRewards')[0]
  self.assertIn('"collaborators"',section); self.assertNotIn('"collaboratorIds"',section)
 def test_category_parent_is_explicit(self):
  swift=(ROOT/'Core/PublishModesContracts.swift').read_text(); self.assertIn('"parentid": .string("0")',swift); self.assertIn('o["categoryName"]',swift)
 def test_no_live_default(self):
  s=(ROOT/'Core/PublishModesService.swift').read_text()
  self.assertIn('approval: OperationEndpointApproval? = nil',s); self.assertIn('journal: (any OperationPendingJournal)? = nil',s)
  self.assertNotIn('URLSession',s); self.assertNotIn('api/publisher/identity"',s)
  self.assertIn('init(enabled: Bool = false',(ROOT/'App/PublishingMapKitAdapter.swift').read_text())
 def test_journal_precedes_dispatch(self):
  s=(ROOT/'Core/PublishModesService.swift').read_text().split('public func submit')[1]
  self.assertLess(s.index('try journal.write(record)'),s.index('transport.send(request)'))
  self.assertIn('reviews[review.id] == review',s); self.assertIn('page.rows.first(where:',s)
 def test_identity_is_not_persisted(self):
  s=(ROOT/'Core/PublishModesDraftStore.swift').read_text(); self.assertNotIn('idCard',s); self.assertNotIn('realName',s)
  self.assertIn('baseline == baseline',s); self.assertIn('ownerKey == session.storageKey',s)
 def test_bilingual_catalog_coverage(self):
  catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
  for key,value in catalog.items():
   for lang in ['en','zh-Hans']: self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
  refs=set()
  for p in (ROOT/'App').glob('*.swift'): refs.update(re.findall(r'"(publishModes\.[A-Za-z][A-Za-z.]*)"',p.read_text()))
  refs={k for k in refs if not k.endswith('.') and not any(x in k for x in ['.quick.', '.activity.', '.management.', '.fixture.']) and k not in {'publishModes.home','publishModes.message'}}
  self.assertEqual(refs-set(catalog),set())
 def test_runtime_claims_are_explicit(self):
  s=(ROOT/'docs/publishing-modes-integration.md').read_text(); self.assertIn('NOT_RUN',s)
if __name__=='__main__': unittest.main(verbosity=2)
