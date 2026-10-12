"""Supplementary source contracts, not native execution."""
from pathlib import Path
import unittest,json
R=Path(__file__).resolve().parents[2]
class Contract(unittest.TestCase):
 @classmethod
 def setUpClass(c):
  c.core=(R/'Core/MerchantNPCFieldDraft.swift').read_text();c.session=(R/'App/MerchantNPCFieldSession.swift').read_text();c.view=(R/'App/MerchantNPCFieldEntry.swift').read_text()
 def contains(self,s,markers):
  for marker in markers:self.assertIn(marker,s)
 def test_exact_four_source_fields(self):self.assertIn('case name, greeting, persona, knowledge',self.core)
 def test_source_limits(self):self.contains(self.core,['case .name: return 32','case .greeting: return 60','case .persona: return 500','case .knowledge: return 2000','value.utf16.count > field.limit'])
 def test_source_multiline(self):self.assertIn('self == .persona || self == .knowledge',self.core);self.assertIn('session.buffer.field.multiline',self.view)
 def test_source_trim_and_required_name(self):self.contains(self.core,['value.trimmingCharacters(in: Self.sourceWhitespace)','field == .name && appliedValue.isEmpty','\\u{FEFF}']);self.assertNotIn('\\u{0085}',self.core)
 def test_raw_buffer_not_truncated(self):self.assertIn('buffer.value = raw',self.session);self.assertNotIn('.prefix(',self.core)
 def test_historical_noop(self):self.contains(self.core,['guard isDirty else { return nil }','guard isDirty else { return source }'])
 def test_exact_single_field_apply(self):
  for name in ['name','greeting','persona','knowledge']:self.assertIn('character.'+name+' = appliedValue',self.core)
  for name in ['avatar','auditStatus','enabled','auditReason']:self.assertNotIn('character.'+name+' =',self.core)
 def test_sibling_raw_identity(self):self.contains(self.core,['x == y','x.avatar','x.knowledge','x.auditReason.map { Data($0.utf8) }'])
 def test_auth_destination(self):self.contains(self.session,['c.reader.isConfigured','c.reader.isAuthenticated','draft.destination == c.destination','baseline.destination == c.destination','field.value(in: draft) != nil'])
 def test_owner_fences(self):self.contains(self.session,['document.revision == revision','c.reader.scope == scope','c.draftIdentity == identity','sameDraft(draft, original)','sameDraft(baseline, self.baseline)'])
 def test_busy_review_lock(self):self.contains(self.session,['!c.isBusy','!c.isLocked','c.confirmation == nil','!asksDiscard'])
 def test_consume_before_edit(self):
  s=self.session[self.session.index('func apply()'):];self.assertLess(s.index('cancel()'),s.index('document.edit(next)'))
 def test_dirty_cancel_keep(self):self.contains(self.session,['if buffer.isDirty { asksDiscard = true; return false }','guard isCurrent, asksDiscard else','buffer.value = ""'])
 def test_old_route_generation(self):self.contains(self.session,['generation == permit','self.generation == captured','guard session?.id == id else','self.session?.id == shownID'])
 def test_lifecycle_and_dismissal(self):self.contains(self.view,['.onChange(of: document.revision)','.onChange(of: document.coordinator.draftIdentity)','.onChange(of: document.coordinator.reader.scope)','.onChange(of: scenePhase)','.onDisappear { presentation.deactivate() }','.interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)'])
 def test_no_external_action(self):
  for s in ['URLSession','UserDefaults','FileManager','UIPasteboard','.load(','.save(','.confirm(','.grant','upload']:self.assertNotIn(s,self.core+self.session+self.view)
 def test_catalog_and_native_inventory(self):
  cat=json.loads((R/'Resources/MerchantNPCFieldLocalizations.fragment.json').read_text());self.assertEqual(len(cat),16)
  for v in cat.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
  for p,n in [('CoreTests/MerchantNPCFieldDraftTests.swift',14),('AppUnitTests/MerchantNPCFieldSessionTests.swift',21),('AppUITests/MerchantNPCFieldFlowTests.swift',5)]:self.assertEqual((R/'Tests'/p).read_text().count('func test'),n)
 def test_existing_fixture_no_save(self):
  ui=(R/'Tests/AppUITests/MerchantNPCFieldFlowTests.swift').read_text();self.assertIn('--uitesting-merchant-operations-fixture',ui);self.assertNotIn('merchant.operations.confirm',ui)
if __name__=='__main__':unittest.main(verbosity=2)
